import ExternalAccessory
import Flutter
import Foundation
import UIKit

// Swift Package Manager builds the C FFI bridge as its own module; under
// CocoaPods the same declarations arrive through the pod umbrella header
// (flutter_skyle_ios.h), where this module does not exist.
#if canImport(flutter_skyle_bridge)
import flutter_skyle_bridge
#endif

public class FlutterSkylePlugin: NSObject, FlutterPlugin, StreamDelegate, EAAccessoryDelegate {
    private var accessory: EAAccessory?
    private var session: EASession?
    private let communicationProtocol = "de.eyev.eap"
    private let channel: FlutterMethodChannel

    private var writer: OutputStreamManager?

    // Dead-session recovery (see handleTransportFailure). The iOS transport is
    // push mode without a heartbeat, so the stream error / end events are the
    // only way to learn that the EASession died while the accessory is still
    // attached. All of this state is main-thread only.
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var sessionOpenedAt: Date?
    /// Delays before reopen attempt 1..n; later attempts use reconnectMaxDelay.
    private static let reconnectDelays: [TimeInterval] = [0.5, 1, 2, 4]
    private static let reconnectMaxDelay: TimeInterval = 5
    /// A session that lived at least this long counts as healthy: the next
    /// failure restarts the backoff at the first delay instead of continuing it
    /// (so a session that dies right after opening cannot reopen in a tight loop).
    private static let stableSessionSeconds: TimeInterval = 10

    // C client pointer (singleton, created by Dart FFI layer)
    private var clientPtr: OpaquePointer?

    // Multi-engine support
    private static var isPrimaryInitialized = false
    private static var primaryInstance: FlutterSkylePlugin?
    private var isPrimary = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_skyle/usb", binaryMessenger: registrar.messenger())
        let instance = FlutterSkylePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)

        if !isPrimaryInitialized {
            isPrimaryInitialized = true
            instance.isPrimary = true
            primaryInstance = instance

            EAAccessoryManager.shared().registerForLocalNotifications()
            NotificationCenter.default.addObserver(
                instance,
                selector: #selector(didConnectAccessory(_:)),
                name: Notification.Name.EAAccessoryDidConnect,
                object: nil
            )
            NotificationCenter.default.addObserver(
                instance,
                selector: #selector(didDisconnectAccessory(_:)),
                name: Notification.Name.EAAccessoryDidDisconnect,
                object: nil
            )
            NotificationCenter.default.addObserver(
                instance,
                selector: #selector(handleWillTerminate(_:)),
                name: UIApplication.willTerminateNotification,
                object: nil
            )
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configureTransport":
            let success = configureTransport()
            result(success)
        case "debugSimulateTransportFailure":
            // Testing only: runs the same handler as a real stream error.
            result(simulateTransportFailure())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Transport Configuration

    private func configureTransport() -> Bool {
        guard let ptr = flutter_skyle_get_instance() else {
            print("[FlutterSkylePlugin] configureTransport: No client instance")
            return false
        }
        clientPtr = ptr

        // Retain self for C callbacks
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Configure push-based transport (write callback + device check, no background thread)
        let configResult = flutter_skyle_configure_push_transport(
            ptr,
            FlutterSkylePlugin.transportWrite,
            FlutterSkylePlugin.deviceCheck,
            selfPtr
        )

        if configResult != 0 {
            print("[FlutterSkylePlugin] configureTransport: Failed to configure push transport (\(configResult))")
            return false
        }

        // Try to connect if accessory is already present
        connect()

        print("[FlutterSkylePlugin] Push transport configured")
        return true
    }

    // MARK: - C Transport Callbacks

    /// Write callback — called by C library when it needs to send data.
    /// Writes to the EASession output stream via OutputStreamManager.
    static let transportWrite: @convention(c) (
        UnsafePointer<UInt8>?, UInt16, UnsafeMutableRawPointer?
    ) -> Int32 = { data, length, userData in
        guard let userData = userData,
              let data = data,
              length > 0 else {
            return -1
        }

        let plugin = Unmanaged<FlutterSkylePlugin>.fromOpaque(userData).takeUnretainedValue()

        // A failed or closed writer (the EASession died) can never deliver the
        // bytes - report the failure instead of pretending success.
        guard let writer = plugin.writer, writer.isWritable else {
            return -1
        }

        let bytes = Data(bytes: data, count: Int(length))
        writer.enqueueData(bytes)
        return Int32(length)
    }

    /// Device check callback — called by C library to check if device is connected.
    static let deviceCheck: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { userData in
        guard let userData = userData else { return false }
        let plugin = Unmanaged<FlutterSkylePlugin>.fromOpaque(userData).takeUnretainedValue()
        return plugin.accessory?.isConnected ?? false
    }

    // MARK: - Connection Management

    private func connect() {
        if let _ = session {
            // Session already open
            return
        }

        if let acc = accessory, acc.isConnected {
            openSession(accessory: acc)
            return
        }

        // Find connected accessory
        let accessoryManager = EAAccessoryManager.shared()
        for acc in accessoryManager.connectedAccessories {
            if acc.protocolStrings.contains(communicationProtocol) {
                printAccessoryDetails(accessory: acc)
                self.accessory = acc
                acc.delegate = self
                openSession(accessory: acc)
                return
            }
        }
    }

    func openSession(accessory: EAAccessory) {
        if session != nil {
            // Already open
            if let ptr = clientPtr {
                flutter_skyle_connect(ptr)
            }
            return
        }

        guard let newSession = EASession(accessory: accessory, forProtocol: communicationProtocol) else {
            print("[FlutterSkylePlugin] Failed to create EASession")
            return
        }

        self.session = newSession
        sessionOpenedAt = Date()
        // A session is up (normal connect notification or our own reopen): a
        // pending scheduled reopen is obsolete. The backoff counter is kept
        // until the session proves stable (see handleTransportFailure).
        cancelReconnect(resetBackoff: false)

        if let inputStream = newSession.inputStream {
            inputStream.delegate = self
            inputStream.schedule(in: RunLoop.current, forMode: .default)
            inputStream.open()
        }

        if let outputStream = newSession.outputStream {
            let manager = OutputStreamManager(outputStream: outputStream)
            manager.onFailure = { [weak self] failed in
                self?.handleTransportFailure(source: failed, reason: "output stream failed")
            }
            writer = manager
        }

        print("[FlutterSkylePlugin] Session opened for \(accessory.name)")

        // Set C client to LINK_SYNCED (EASession handles iAP2 handshake)
        if let ptr = clientPtr {
            flutter_skyle_connect(ptr)
        }
    }

    func closeSession() {
        // Re-entry guard: both EAAccessoryDidDisconnect notification and the
        // EAAccessoryDelegate callback fire on unplug, so closeSession() can
        // be called twice. Without this guard the second call still calls
        // flutter_skyle_disconnect and may race with stream teardown.
        guard session != nil || writer != nil || accessory != nil else {
            return
        }

        // Disconnect C client first so no further FFI sends will succeed.
        if let ptr = clientPtr {
            flutter_skyle_disconnect(ptr)
        }

        // Stop the writer SYNCHRONOUSLY before releasing the session. close()
        // drains the writeQueue and tears down the output stream while the
        // EASession is still alive - guarantees no in-flight stream.write()
        // can run after the EASession is released and the iAP2/USB endpoint
        // is gone (which is what crashes iOS on physical unplug).
        writer?.onFailure = nil
        writer?.close()
        writer = nil

        if let inputStream = session?.inputStream {
            inputStream.close()
            inputStream.remove(from: RunLoop.current, forMode: .default)
            inputStream.delegate = nil
        }

        session = nil
        accessory = nil

        print("[FlutterSkylePlugin] Session closed")
    }

    // MARK: - Dead session recovery

    /// Debug entry point (method channel `debugSimulateTransportFailure`):
    /// behaves like a stream error on the open session. Returns false when no
    /// session is open (nothing to fail).
    private func simulateTransportFailure() -> Bool {
        guard session != nil || writer != nil else {
            print("[FlutterSkylePlugin] debugSimulateTransportFailure: no session open")
            return false
        }
        handleTransportFailure(source: nil, reason: "debug simulation")
        return true
    }

    /// The EASession is dead while the accessory may still be attached (stream
    /// error / end on the input or output stream). Without this the C client
    /// stays LINK_SYNCED over dead streams forever, because push mode has no
    /// heartbeat: close the session (drives the client to DISCONNECTED so Dart
    /// sees the link go down) and reopen a fresh EASession after a short delay.
    ///
    /// Callable from any thread. The work is always deferred to the main queue,
    /// so a StreamDelegate callback has returned before its stream gets closed
    /// and OutputStreamManager's callback is off its own write queue (close()
    /// blocks on it). `source` is the stream / writer that reported the failure
    /// (nil = unconditional); a report from a session that was already replaced
    /// is dropped, which also makes the handler idempotent when both streams
    /// report the same failure.
    private func handleTransportFailure(source: AnyObject?, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.clientPtr != nil else { return }
            guard self.session != nil || self.writer != nil else { return }
            if let source = source, source !== self.session?.inputStream, source !== self.writer {
                return
            }

            print("[FlutterSkylePlugin] Transport failure (\(reason)) - closing session")

            let accessoryGone = !(self.accessory?.isConnected ?? true)
            if let opened = self.sessionOpenedAt, Date().timeIntervalSince(opened) >= FlutterSkylePlugin.stableSessionSeconds {
                self.reconnectAttempt = 0
            }
            self.closeSession()

            if accessoryGone {
                // A real unplug: the accessory notifications own the reconnect.
                print("[FlutterSkylePlugin] Accessory is gone - waiting for it to reconnect")
                return
            }
            self.scheduleReconnect()
        }
    }

    /// Schedules the next reopen attempt: 0.5s, 1s, 2s, 4s, then every 5s.
    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let delays = FlutterSkylePlugin.reconnectDelays
        let delay = reconnectAttempt < delays.count ? delays[reconnectAttempt] : FlutterSkylePlugin.reconnectMaxDelay
        reconnectAttempt += 1
        let item = DispatchWorkItem { [weak self] in
            self?.performReconnect()
        }
        reconnectWorkItem = item
        print("[FlutterSkylePlugin] Reopening session in \(delay)s (attempt \(reconnectAttempt))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performReconnect() {
        reconnectWorkItem = nil
        // Plugin detached, or a session already came up through the normal
        // connect notification: nothing to do.
        guard clientPtr != nil, session == nil else { return }

        let present = EAAccessoryManager.shared().connectedAccessories.contains {
            $0.isConnected && $0.protocolStrings.contains(communicationProtocol)
        }
        guard present else {
            // Accessory unplugged meanwhile: didConnectAccessory reopens on replug.
            print("[FlutterSkylePlugin] Reopen: accessory gone, waiting for it to reconnect")
            reconnectAttempt = 0
            return
        }

        connect()
        if session == nil {
            print("[FlutterSkylePlugin] Reopen failed (no EASession), retrying")
            scheduleReconnect()
        } else {
            print("[FlutterSkylePlugin] Reopen succeeded")
        }
    }

    private func cancelReconnect(resetBackoff: Bool) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        if resetBackoff {
            reconnectAttempt = 0
        }
    }

    // MARK: - StreamDelegate

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            if aStream == session?.inputStream {
                print("[FlutterSkylePlugin] Input stream opened")
            }
        case Stream.Event.hasBytesAvailable:
            if aStream == session?.inputStream {
                if let inputStream = session?.inputStream {
                    readAndProcessData(from: inputStream)
                }
            }
        case Stream.Event.hasSpaceAvailable:
            break
        case Stream.Event.errorOccurred:
            print("[FlutterSkylePlugin] Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
            if aStream === session?.inputStream {
                handleTransportFailure(source: aStream, reason: "input stream error")
            }
        case Stream.Event.endEncountered:
            if aStream === session?.inputStream {
                print("[FlutterSkylePlugin] Input stream ended")
                handleTransportFailure(source: aStream, reason: "input stream ended")
            }
        default:
            break
        }
    }

    /// Read available bytes from input stream and feed to C parser
    private func readAndProcessData(from inputStream: InputStream) {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                // Feed raw bytes to C library for parsing
                if let ptr = clientPtr {
                    flutter_skyle_process_data(ptr, buffer, UInt16(min(bytesRead, Int(UInt16.max))))
                }
            } else if bytesRead < 0 {
                print("[FlutterSkylePlugin] Read error from input stream")
                break
            }
        }
    }

    // MARK: - Accessory Notifications

    @objc
    private func didConnectAccessory(_ notification: NSNotification) {
        // A real (re)connect takes over from any scheduled reopen.
        cancelReconnect(resetBackoff: true)
        if let acc = notification.userInfo?[EAAccessoryKey] as? EAAccessory,
           acc.protocolStrings.contains(communicationProtocol) {
            printAccessoryDetails(accessory: acc)
            self.accessory = acc
            acc.delegate = self
            openSession(accessory: acc)
        } else {
            connect()
        }
    }

    @objc
    private func didDisconnectAccessory(_ notification: NSNotification) {
        // A real accessory disconnect: the notifications own reconnecting now.
        // Our failure handler may already have cleared self.accessory, so match
        // on the notification's accessory too.
        let gone = notification.userInfo?[EAAccessoryKey] as? EAAccessory
        if gone == nil || gone?.protocolStrings.contains(communicationProtocol) == true || self.accessory != nil {
            cancelReconnect(resetBackoff: true)
        }
        if let acc = self.accessory, !acc.isConnected {
            print("[FlutterSkylePlugin] Accessory disconnected: \(acc.name)")
            closeSession()
        }
    }

    public func accessoryDidDisconnect(_ accessory: EAAccessory) {
        print("[FlutterSkylePlugin] accessoryDidDisconnect: \(accessory.name)")
        cancelReconnect(resetBackoff: true)
        closeSession()
    }

    // MARK: - Engine Lifecycle

    /// Called by the Flutter engine before tearing down the Dart VM.
    /// Nulling out the Dart callback pointers here ensures that any EA data
    /// arriving on the next RunLoop turn cannot call a closed NativeCallable
    /// and trigger DLRT_GetFfiCallbackMetadata -> abort().
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        cancelReconnect(resetBackoff: true)
        if let ptr = clientPtr {
            flutter_skyle_clear_callbacks(ptr)
            clientPtr = nil
            print("[FlutterSkylePlugin] detachFromEngine: callbacks cleared")
        }
        if isPrimary {
            NotificationCenter.default.removeObserver(self)
            FlutterSkylePlugin.isPrimaryInitialized = false
            FlutterSkylePlugin.primaryInstance = nil
        }
    }

    @objc private func handleWillTerminate(_ notification: NSNotification) {
        cancelReconnect(resetBackoff: true)
        if let ptr = clientPtr {
            flutter_skyle_clear_callbacks(ptr)
            print("[FlutterSkylePlugin] handleWillTerminate: callbacks cleared")
        }
    }

    // MARK: - Helpers

    private func printAccessoryDetails(accessory: EAAccessory) {
        let description = """
        [FlutterSkylePlugin] Accessory: \(accessory.name)
          Manufacturer: \(accessory.manufacturer)
          Model: \(accessory.modelNumber)
          Serial: \(accessory.serialNumber)
          FW: \(accessory.firmwareRevision)
          Connected: \(accessory.isConnected)
          Protocols: \(accessory.protocolStrings.joined(separator: ", "))
        """
        print(description)
    }
}
