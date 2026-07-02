import ExternalAccessory
import Flutter
import Foundation
import UIKit

public class FlutterEapPlugin: NSObject, FlutterPlugin, StreamDelegate, EAAccessoryDelegate {
    private var accessory: EAAccessory?
    private var session: EASession?
    private let communicationProtocol = "de.eyev.eap"
    private let channel: FlutterMethodChannel

    private var writer: OutputStreamManager?

    // C client pointer (singleton, created by Dart FFI layer)
    private var clientPtr: OpaquePointer?

    // Multi-engine support
    private static var isPrimaryInitialized = false
    private static var primaryInstance: FlutterEapPlugin?
    private var isPrimary = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_eap/usb", binaryMessenger: registrar.messenger())
        let instance = FlutterEapPlugin(channel: channel)
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Transport Configuration

    private func configureTransport() -> Bool {
        guard let ptr = flutter_eap_get_instance() else {
            print("[FlutterEapPlugin] configureTransport: No client instance")
            return false
        }
        clientPtr = ptr

        // Retain self for C callbacks
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Configure push-based transport (write callback + device check, no background thread)
        let configResult = flutter_eap_configure_push_transport(
            ptr,
            FlutterEapPlugin.transportWrite,
            FlutterEapPlugin.deviceCheck,
            selfPtr
        )

        if configResult != 0 {
            print("[FlutterEapPlugin] configureTransport: Failed to configure push transport (\(configResult))")
            return false
        }

        // Try to connect if accessory is already present
        connect()

        print("[FlutterEapPlugin] Push transport configured")
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

        let plugin = Unmanaged<FlutterEapPlugin>.fromOpaque(userData).takeUnretainedValue()

        guard let writer = plugin.writer else {
            return -1
        }

        let bytes = Data(bytes: data, count: Int(length))
        writer.enqueueData(bytes)
        return Int32(length)
    }

    /// Device check callback — called by C library to check if device is connected.
    static let deviceCheck: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { userData in
        guard let userData = userData else { return false }
        let plugin = Unmanaged<FlutterEapPlugin>.fromOpaque(userData).takeUnretainedValue()
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
                flutter_eap_connect(ptr)
            }
            return
        }

        guard let newSession = EASession(accessory: accessory, forProtocol: communicationProtocol) else {
            print("[FlutterEapPlugin] Failed to create EASession")
            return
        }

        self.session = newSession

        if let inputStream = newSession.inputStream {
            inputStream.delegate = self
            inputStream.schedule(in: RunLoop.current, forMode: .default)
            inputStream.open()
        }

        if let outputStream = newSession.outputStream {
            writer = OutputStreamManager(outputStream: outputStream)
        }

        print("[FlutterEapPlugin] Session opened for \(accessory.name)")

        // Set C client to LINK_SYNCED (EASession handles iAP2 handshake)
        if let ptr = clientPtr {
            flutter_eap_connect(ptr)
        }
    }

    func closeSession() {
        // Re-entry guard: both EAAccessoryDidDisconnect notification and the
        // EAAccessoryDelegate callback fire on unplug, so closeSession() can
        // be called twice. Without this guard the second call still calls
        // flutter_eap_disconnect and may race with stream teardown.
        guard session != nil || writer != nil || accessory != nil else {
            return
        }

        // Disconnect C client first so no further FFI sends will succeed.
        if let ptr = clientPtr {
            flutter_eap_disconnect(ptr)
        }

        // Stop the writer SYNCHRONOUSLY before releasing the session. close()
        // drains the writeQueue and tears down the output stream while the
        // EASession is still alive - guarantees no in-flight stream.write()
        // can run after the EASession is released and the iAP2/USB endpoint
        // is gone (which is what crashes iOS on physical unplug).
        writer?.close()
        writer = nil

        if let inputStream = session?.inputStream {
            inputStream.close()
            inputStream.remove(from: RunLoop.current, forMode: .default)
            inputStream.delegate = nil
        }

        session = nil
        accessory = nil

        print("[FlutterEapPlugin] Session closed")
    }

    // MARK: - StreamDelegate

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            if aStream == session?.inputStream {
                print("[FlutterEapPlugin] Input stream opened")
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
            print("[FlutterEapPlugin] Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
        case Stream.Event.endEncountered:
            if aStream == session?.inputStream {
                print("[FlutterEapPlugin] Input stream ended")
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
                    flutter_eap_process_data(ptr, buffer, UInt16(min(bytesRead, Int(UInt16.max))))
                }
            } else if bytesRead < 0 {
                print("[FlutterEapPlugin] Read error from input stream")
                break
            }
        }
    }

    // MARK: - Accessory Notifications

    @objc
    private func didConnectAccessory(_ notification: NSNotification) {
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
        if let acc = self.accessory, !acc.isConnected {
            print("[FlutterEapPlugin] Accessory disconnected: \(acc.name)")
            closeSession()
        }
    }

    public func accessoryDidDisconnect(_ accessory: EAAccessory) {
        print("[FlutterEapPlugin] accessoryDidDisconnect: \(accessory.name)")
        closeSession()
    }

    // MARK: - Engine Lifecycle

    /// Called by the Flutter engine before tearing down the Dart VM.
    /// Nulling out the Dart callback pointers here ensures that any EA data
    /// arriving on the next RunLoop turn cannot call a closed NativeCallable
    /// and trigger DLRT_GetFfiCallbackMetadata -> abort().
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if let ptr = clientPtr {
            flutter_eap_clear_callbacks(ptr)
            clientPtr = nil
            print("[FlutterEapPlugin] detachFromEngine: callbacks cleared")
        }
        if isPrimary {
            NotificationCenter.default.removeObserver(self)
            FlutterEapPlugin.isPrimaryInitialized = false
            FlutterEapPlugin.primaryInstance = nil
        }
    }

    @objc private func handleWillTerminate(_ notification: NSNotification) {
        if let ptr = clientPtr {
            flutter_eap_clear_callbacks(ptr)
            print("[FlutterEapPlugin] handleWillTerminate: callbacks cleared")
        }
    }

    // MARK: - Helpers

    private func printAccessoryDetails(accessory: EAAccessory) {
        let description = """
        [FlutterEapPlugin] Accessory: \(accessory.name)
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
