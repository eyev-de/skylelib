import Cocoa
import FlutterMacOS

/// Flutter EAP Plugin for macOS
///
/// Architecture:
/// - IOKit handles USB device communication (bulk transfers) entirely in C
/// - C bridge (flutter_eap_bridge_apple) provides FFI symbols for Dart
/// - Dart sets callbacks via FFI, Dart calls configureTransport via MethodChannel
/// - No Swift USB code needed - IOKit transport is configured in C
///
/// Multi-engine support:
/// - First engine to attach is primary (owns transport lifecycle)
/// - Secondary engines (overlays) share the same native client
public class FlutterEapPlugin: NSObject, FlutterPlugin {
    // Skyle eye tracker USB identifiers
    private static let skyleVendorId: UInt16 = 0x3729
    private static let skyleProductId: UInt16 = 0x7333

    // Global state - shared across engine instances
    private static var isPrimaryInitialized = false
    private static var isTransportConfigured = false
    private var isPrimary = false

    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Method channel for transport configuration (matching Android/iOS "flutter_eap/usb")
        let channel = FlutterMethodChannel(name: "flutter_eap/usb", binaryMessenger: registrar.messenger)
        let instance = FlutterEapPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)

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
        if let clientPtr = flutter_eap_get_instance() {
            flutter_eap_clear_callbacks(clientPtr)
            print("[FlutterEapPlugin macOS] handleAppWillTerminate: callbacks cleared")
        }
    }

    // MARK: - Engine Lifecycle

    /// Called by the Flutter engine before tearing down the Dart VM.
    /// Nulling out the Dart callback pointers here ensures the IOKit background
    /// thread cannot call a closed NativeCallable and trigger abort().
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if let clientPtr = flutter_eap_get_instance() {
            flutter_eap_clear_callbacks(clientPtr)
            print("[FlutterEapPlugin macOS] detachFromEngine: callbacks cleared")
        }
        if isPrimary {
            NotificationCenter.default.removeObserver(self)
            FlutterEapPlugin.isPrimaryInitialized = false
            FlutterEapPlugin.isTransportConfigured = false
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
        let clientPtr = flutter_eap_get_instance()
        guard let clientPtr = clientPtr else {
            print("[FlutterEapPlugin macOS] configureTransport: No client instance")
            return false
        }

        // Only configure transport once (shared across engines)
        if FlutterEapPlugin.isTransportConfigured {
            print("[FlutterEapPlugin macOS] Transport already configured")
            return true
        }

        // Configure IOKit USB transport entirely in C
        let configResult = flutter_eap_configure_iokit_transport(
            clientPtr,
            FlutterEapPlugin.skyleVendorId,
            FlutterEapPlugin.skyleProductId
        )

        if configResult == 0 {
            FlutterEapPlugin.isTransportConfigured = true
            print("[FlutterEapPlugin macOS] IOKit transport configured (VID=0x\(String(FlutterEapPlugin.skyleVendorId, radix: 16)), PID=0x\(String(FlutterEapPlugin.skyleProductId, radix: 16)))")
            return true
        } else {
            print("[FlutterEapPlugin macOS] Failed to configure IOKit transport: \(configResult)")
            return false
        }
    }
}
