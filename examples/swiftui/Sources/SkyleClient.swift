import Foundation

/// Thin Swift wrapper over the skylelib C client.
///
/// Owns the platform transport (built-in IOKit on macOS, ExternalAccessory push
/// mode on iPadOS), registers the C callbacks, and re-emits decoded data through
/// Swift closures. **All `on*` closures fire on the library's background I/O
/// thread** — subscribers must hop to the main thread before touching the UI.
final class SkyleClient {
    static let vendorId: UInt16 = 0x3729
    static let productId: UInt16 = 0x7333

    private var client: OpaquePointer?

    #if os(macOS)
    private var iokit: OpaquePointer?
    #elseif os(iOS)
    private var accessory: ExternalAccessoryTransport?
    private var tickTimer: Timer?
    #endif

    // Events (raised on a background thread).
    var onState: ((eap_connection_state) -> Void)?
    var onGaze: ((Float, Float, UInt8, Bool) -> Void)?
    var onPositioning: ((eap_complex_face) -> Void)?
    var onVideo: ((Int, Int, Int, [UInt8]) -> Void)?
    var onVersion: ((String, UInt64) -> Void)?

    func start() {
        guard let c = eap_client_get_instance() else { return }
        client = c
        setupTransport()   // phase 1 — transport (starts background I/O)
        setupCallbacks()   // phase 2 — message callbacks
        eap_client_connect(c)
    }

    func stop() {
        if let c = client {
            eap_client_disconnect(c)
            eap_client_stop_background(c)
        }
        #if os(macOS)
        if let i = iokit { eap_transport_iokit_destroy(i); iokit = nil }
        #elseif os(iOS)
        tickTimer?.invalidate(); tickTimer = nil
        accessory?.stop(); accessory = nil
        #endif
    }

    // MARK: - Streaming control

    func enableGaze(_ enable: Bool) { if let c = client { eap_client_enable_gaze(c, enable) } }
    func enablePositioning(_ enable: Bool) { if let c = client { eap_client_enable_positioning(c, enable) } }
    func enableVideo(_ enable: Bool) { if let c = client { eap_client_enable_video(c, enable) } }

    // MARK: - Transport (platform-specific)

    #if os(macOS)
    private func setupTransport() {
        guard let c = client else { return }
        var cfg = eap_transport_iokit_config(
            vendor_id: Self.vendorId,
            product_id: Self.productId,
            timeout_ms: 1000,
            verbose: false)
        iokit = eap_transport_iokit_create(&cfg)

        var transport = eap_transport_config()
        transport.transport_write = eap_transport_iokit_write
        transport.transport_read = eap_transport_iokit_read
        transport.transport_user_data = UnsafeMutableRawPointer(iokit)
        transport.usb_device_check = eap_transport_iokit_get_check_callback()
        transport.connect_timeout_ms = 10000
        transport.reconnect_interval_ms = 2000
        eap_client_set_transport(c, &transport)
    }
    #elseif os(iOS)
    private func setupTransport() {
        guard let c = client else { return }
        let ea = ExternalAccessoryTransport(client: c)
        accessory = ea
        let ctx = Unmanaged.passUnretained(ea).toOpaque()

        // Push transport: the platform feeds RX bytes; this write callback is
        // invoked by the library's send thread.
        eap_client_set_push_transport(c, { data, length, user in
            guard let user = user else { return -1 }
            let t = Unmanaged<ExternalAccessoryTransport>.fromOpaque(user).takeUnretainedValue()
            return t.write(data, length: length)
        }, nil, ctx)

        ea.start()

        // Push mode needs a periodic tick for heartbeat / timeout / reconnect.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            if let c = self?.client { eap_client_tick(c) }
        }
    }
    #endif

    // MARK: - Callbacks

    private func setupCallbacks() {
        guard let c = client else { return }
        var cfg = eap_callback_config()
        cfg.user_data = Unmanaged.passUnretained(self).toOpaque()

        cfg.on_state_change = { _, _, newState, user in
            guard let user = user else { return }
            let me = Unmanaged<SkyleClient>.fromOpaque(user).takeUnretainedValue()
            me.onState?(newState)
        }

        cfg.on_gaze = { _, gaze, user in
            guard let gaze = gaze, let user = user else { return }
            let me = Unmanaged<SkyleClient>.fromOpaque(user).takeUnretainedValue()
            let both = gaze.pointee.both
            let valid = both.smoothed.x != 0 || both.smoothed.y != 0
            me.onGaze?(both.smoothed.x, both.smoothed.y, both.type, valid)
        }

        cfg.on_positioning = { _, positioning, user in
            guard let positioning = positioning, let user = user else { return }
            let me = Unmanaged<SkyleClient>.fromOpaque(user).takeUnretainedValue()
            me.onPositioning?(positioning.pointee.face)
        }

        cfg.on_video = { _, video, user in
            guard let video = video, let user = user else { return }
            let me = Unmanaged<SkyleClient>.fromOpaque(user).takeUnretainedValue()
            let r = video.pointee
            let len = Int(r.pixel_data_length)
            var bytes = [UInt8](repeating: 0, count: len)
            if let src = r.pixel_data, len > 0 {
                bytes.withUnsafeMutableBytes { dst in
                    if let base = dst.baseAddress { memcpy(base, src, len) }
                }
            }
            me.onVideo?(Int(r.width), Int(r.height), Int(r.channels), bytes)
        }

        cfg.on_version = { _, version, user in
            guard let version = version, let user = user else { return }
            let me = Unmanaged<SkyleClient>.fromOpaque(user).takeUnretainedValue()
            let firmware = cTupleToString(version.pointee.firmware, maxLength: 32)
            me.onVersion?(firmware, version.pointee.serial)
        }

        eap_client_set_callbacks(c, &cfg)
    }
}
