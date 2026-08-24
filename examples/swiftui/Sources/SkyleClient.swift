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
    var onState: ((skyle_connection_state) -> Void)?
    var onGaze: ((Float, Float, UInt8, Bool) -> Void)?
    var onPositioning: ((skyle_complex_face) -> Void)?
    var onVideo: ((Int, Int, Int, [UInt8]) -> Void)?
    var onVersion: ((String, UInt64) -> Void)?

    func start() {
        guard let c = skyle_client_get_instance() else { return }
        client = c
        setupTransport()   // phase 1 — transport (starts background I/O)
        setupCallbacks()   // phase 2 — message callbacks
        #if os(macOS)
        // Skyle Link supervisor (callback-less mode): the app keeps owning the
        // registered IOKit transport; the supervisor elects OWNER (serve a hub
        // over it) or CLIENT (share the tracker over a loopback socket) and
        // stashes / restores the transport across the swaps itself.
        skyle_link_set_identity("skyle-swiftui-example", UInt8(SKYLE_LINK_TIER_DEFAULT.rawValue), true)
        skyle_link_set_supervisor_enabled(true)
        // While on a local link the supervisor owns the connection; a manual
        // connect would fight it (never force-disconnect while supervised).
        if !skyle_client_is_local_link(c) {
            skyle_client_connect(c)
        }
        #else
        skyle_client_connect(c)
        #endif
    }

    func stop() {
        #if os(macOS)
        // Deliberate supervisor stop first: OWNER hands the hub over, CLIENT
        // closes the socket - before the transport underneath goes away.
        skyle_link_set_supervisor_enabled(false)
        #endif
        if let c = client {
            skyle_client_disconnect(c)
            skyle_client_stop_background(c)
        }
        #if os(macOS)
        if let i = iokit { skyle_transport_iokit_destroy(i); iokit = nil }
        #elseif os(iOS)
        tickTimer?.invalidate(); tickTimer = nil
        accessory?.stop(); accessory = nil
        #endif
    }

    // MARK: - Streaming control

    func enableGaze(_ enable: Bool) { if let c = client { skyle_client_enable_gaze(c, enable) } }
    func enablePositioning(_ enable: Bool) { if let c = client { skyle_client_enable_positioning(c, enable) } }
    func enableVideo(_ enable: Bool) { if let c = client { skyle_client_enable_video(c, enable) } }

    // MARK: - Skyle Link host control (macOS only; commands to the hub-hosting Skyle app)

    #if os(macOS)
    /// Fire-and-forget host-control command over the local link. Returns the raw
    /// `skyle_result`; `SKYLE_ERROR_INVALID_STATE` means this app is not a link
    /// client right now (e.g. it owns the tracker itself).
    @discardableResult
    func sendHostControl(id: UInt16, value: [UInt8]) -> skyle_result {
        guard let c = client else { return SKYLE_ERROR_INVALID_STATE }
        return value.withUnsafeBufferPointer { buf in
            skyle_link_send_host_control(c, id, buf.baseAddress, UInt16(buf.count))
        }
    }

    @discardableResult
    func setHostMenuBarVisible(_ visible: Bool) -> skyle_result {
        sendHostControl(id: UInt16(SKYLE_LINK_CONTROL_MENU_BAR.rawValue), value: [visible ? 1 : 0])
    }

    @discardableResult
    func setHostPointerVisible(_ visible: Bool) -> skyle_result {
        sendHostControl(id: UInt16(SKYLE_LINK_CONTROL_POINTER_OVERLAY.rawValue), value: [visible ? 1 : 0])
    }

    @discardableResult
    func startHostCalibration() -> skyle_result {
        sendHostControl(id: UInt16(SKYLE_LINK_CONTROL_START_CALIBRATION.rawValue), value: []) // empty value = app default points
    }
    #endif

    // MARK: - Transport (platform-specific)

    #if os(macOS)
    private func setupTransport() {
        guard let c = client else { return }
        var cfg = skyle_transport_iokit_config(
            vendor_id: Self.vendorId,
            product_id: Self.productId,
            timeout_ms: 1000,
            verbose: false)
        iokit = skyle_transport_iokit_create(&cfg)

        var transport = skyle_transport_config()
        transport.transport_write = skyle_transport_iokit_write
        transport.transport_read = skyle_transport_iokit_read
        transport.transport_user_data = UnsafeMutableRawPointer(iokit)
        transport.usb_device_check = skyle_transport_iokit_get_check_callback()
        transport.connect_timeout_ms = 10000
        transport.reconnect_interval_ms = 2000
        skyle_client_set_transport(c, &transport)
    }
    #elseif os(iOS)
    private func setupTransport() {
        guard let c = client else { return }
        let ea = ExternalAccessoryTransport(client: c)
        accessory = ea
        let ctx = Unmanaged.passUnretained(ea).toOpaque()

        // Push transport: the platform feeds RX bytes; this write callback is
        // invoked by the library's send thread.
        skyle_client_set_push_transport(c, { data, length, user in
            guard let user = user else { return -1 }
            let t = Unmanaged<ExternalAccessoryTransport>.fromOpaque(user).takeUnretainedValue()
            return t.write(data, length: length)
        }, nil, ctx)

        ea.start()

        // Push mode needs a periodic tick for heartbeat / timeout / reconnect.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            if let c = self?.client { skyle_client_tick(c) }
        }
    }
    #endif

    // MARK: - Callbacks

    private func setupCallbacks() {
        guard let c = client else { return }
        var cfg = skyle_callback_config()
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

        skyle_client_set_callbacks(c, &cfg)
    }
}
