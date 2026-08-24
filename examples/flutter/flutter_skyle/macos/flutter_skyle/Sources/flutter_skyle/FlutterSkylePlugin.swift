import Cocoa
import FlutterMacOS

// Swift Package Manager builds the C FFI bridge as its own module; under
// CocoaPods the same declarations arrive through the pod umbrella header
// (flutter_skyle_macos.h), where this module does not exist.
#if canImport(flutter_skyle_bridge)
import flutter_skyle_bridge
#endif

/// Flutter EAP Plugin for macOS
///
/// Architecture:
/// - IOKit handles USB device communication (bulk transfers) entirely in C
/// - C bridge (flutter_skyle_bridge_apple) provides FFI symbols for Dart
/// - Dart sets callbacks via FFI, Dart calls configureTransport via MethodChannel
/// - No Swift USB code needed - IOKit transport is configured in C
///
/// Multi-engine support:
/// - First engine to attach is primary (owns transport lifecycle)
/// - Secondary engines (overlays) share the same native client
public class FlutterSkylePlugin: NSObject, FlutterPlugin {
    // Skyle eye tracker USB identifiers
    private static let skyleVendorId: UInt16 = 0x3729
    private static let skyleProductId: UInt16 = 0x7333

    // Global state - shared across engine instances
    private static var isPrimaryInitialized = false
    private static var isTransportConfigured = false
    // Live engine count: the native callback table holds one subscriber per
    // engine (multi-engine fan-out), so clear-all is only safe once the LAST
    // engine detaches.
    private static var engineCount = 0
    private var isPrimary = false

    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Method channel for transport configuration (matching Android/iOS "flutter_skyle/usb")
        let channel = FlutterMethodChannel(name: "flutter_skyle/usb", binaryMessenger: registrar.messenger)
        let instance = FlutterSkylePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        engineCount += 1

        if !isPrimaryInitialized {
            isPrimaryInitialized = true
            instance.isPrimary = true

            // Mirror iOS handleWillTerminate. Clearing callbacks here ensures
            // the IOKit background thread cannot invoke a closed NativeCallable
            // and trigger DLRT_GetFfiCallbackMetadata -> abort() during shutdown.
            NotificationCenter.default.addObserver(
                instance,
                selector: #selector(handleAppWillTerminate(_:)),
                name: NSApplication.willTerminateNotification,
                object: nil
            )
        }
    }

    @objc private func handleAppWillTerminate(_ notification: Notification) {
        if let clientPtr = flutter_skyle_get_instance() {
            flutter_skyle_clear_callbacks(clientPtr)
            print("[FlutterSkylePlugin macOS] handleAppWillTerminate: callbacks cleared")
        }
    }

    // MARK: - Engine Lifecycle

    /// Called by the Flutter engine before tearing down the Dart VM.
    ///
    /// Each engine holds its own subscriber in the native fan-out table and
    /// removes it in Dart (SkyleClientFfi.destroy). Clearing ALL callbacks here
    /// would wipe the OTHER engines' subscriptions, so the safety net (for an
    /// engine that dies without running its Dart destroy - the IOKit thread
    /// must not call a closed NativeCallable and abort) only fires when the
    /// LAST engine detaches.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        FlutterSkylePlugin.engineCount -= 1
        if FlutterSkylePlugin.engineCount <= 0, let clientPtr = flutter_skyle_get_instance() {
            flutter_skyle_clear_callbacks(clientPtr)
            print("[FlutterSkylePlugin macOS] detachFromEngine: last engine detached, callbacks cleared")
        }
        if isPrimary {
            NotificationCenter.default.removeObserver(self)
            FlutterSkylePlugin.isPrimaryInitialized = false
            FlutterSkylePlugin.isTransportConfigured = false
        }
    }

    // MARK: - Method Channel Handler

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

    /// Called from Dart after FFI callbacks are set up.
    /// Configures IOKit USB transport on the C library's singleton client.
    private func configureTransport() -> Bool {
        // Get the singleton C client (already created by Dart FFI layer)
        let clientPtr = flutter_skyle_get_instance()
        guard let clientPtr = clientPtr else {
            print("[FlutterSkylePlugin macOS] configureTransport: No client instance")
            return false
        }

        // Only configure transport once (shared across engines)
        if FlutterSkylePlugin.isTransportConfigured {
            print("[FlutterSkylePlugin macOS] Transport already configured")
            return true
        }

        // Configure IOKit USB transport entirely in C
        let configResult = flutter_skyle_configure_iokit_transport(
            clientPtr,
            FlutterSkylePlugin.skyleVendorId,
            FlutterSkylePlugin.skyleProductId
        )

        if configResult == 0 {
            FlutterSkylePlugin.isTransportConfigured = true
            print("[FlutterSkylePlugin macOS] IOKit transport configured (VID=0x\(String(FlutterSkylePlugin.skyleVendorId, radix: 16)), PID=0x\(String(FlutterSkylePlugin.skyleProductId, radix: 16)))")
            return true
        } else {
            print("[FlutterSkylePlugin macOS] Failed to configure IOKit transport: \(configResult)")
            return false
        }
    }
}
