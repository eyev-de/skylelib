import CoreGraphics
import SwiftUI

/// Observable state for the UI. Subscribes to `SkyleClient` (whose callbacks run
/// on a background thread) and republishes everything on the main thread.
final class SkyleViewModel: ObservableObject {
    @Published var connectionLabel = "Disconnected"
    @Published var connectionColor = Color.gray
    @Published var deviceInfo = ""
    @Published var gazeText = "Gaze: —"
    @Published var selection: ViewMode = .positioning
    @Published var face: skyle_complex_face?
    @Published var videoImage: CGImage?
    #if os(macOS)
    // Skyle Link host controls (toggle state is app-local; the commands only
    // reach a hub-hosting Skyle app while this app is a link client).
    @Published var hostMenuBarVisible = true
    @Published var hostPointerVisible = true
    @Published var hostControlNote = ""
    // What the hub-hosting Skyle app reports back (HOST_STATE); nil = unknown.
    @Published var hostMenuBarReported: Bool?
    @Published var hostPointerReported: Bool?
    #endif

    private let client = SkyleClient()
    private var state: skyle_connection_state = SKYLE_STATE_DISCONNECTED

    init() {
        client.onState = { [weak self] s in
            DispatchQueue.main.async { self?.handleState(s) }
        }
        client.onGaze = { [weak self] x, y, type, valid in
            let text = valid
                ? String(format: "Gaze: (%.0f, %.0f) px · %@", x, y, Self.movementName(type))
                : "Gaze: —"
            DispatchQueue.main.async { self?.gazeText = text }
        }
        client.onPositioning = { [weak self] face in
            DispatchQueue.main.async { self?.face = face }
        }
        client.onVideo = { [weak self] w, h, ch, bytes in
            let image = makeCGImage(width: w, height: h, channels: ch, pixels: bytes)
            DispatchQueue.main.async { self?.videoImage = image }
        }
        client.onVersion = { [weak self] firmware, serial in
            let info = firmware.isEmpty ? "Skyle · SN \(serial)" : "Skyle · FW \(firmware) · SN \(serial)"
            DispatchQueue.main.async { self?.deviceInfo = info }
        }
        #if os(macOS)
        client.onHostVisibility = { [weak self] controlId, visible in
            DispatchQueue.main.async { self?.applyHostVisibility(controlId: controlId, visible: visible) }
        }
        #endif
        client.start()
    }

    func shutdown() {
        client.stop()
    }

    /// Apply stream subscriptions for the current connection state + tab.
    func applyStreams() {
        guard state == SKYLE_STATE_LINK_SYNCED else { return }
        client.enableGaze(true)                              // always live
        client.enablePositioning(selection == .positioning)
        client.enableVideo(selection == .video)              // off when hidden saves bandwidth
    }

    #if os(macOS)
    // MARK: - Skyle Link host controls

    func setHostMenuBarVisible(_ visible: Bool) {
        noteHostControl("Menu bar", client.setHostMenuBarVisible(visible))
    }

    func setHostPointerVisible(_ visible: Bool) {
        noteHostControl("Pointer", client.setHostPointerVisible(visible))
    }

    func startHostCalibration() {
        noteHostControl("Calibrate", client.startHostCalibration())
    }

    private func noteHostControl(_ what: String, _ result: skyle_result) {
        hostControlNote = result == SKYLE_OK
            ? "\(what): sent"
            : "\(what): refused (\(result.rawValue), not a link client)"
    }

    private func applyHostVisibility(controlId: UInt16, visible: Bool?) {
        switch controlId {
        case UInt16(SKYLE_LINK_CONTROL_MENU_BAR.rawValue): hostMenuBarReported = visible
        case UInt16(SKYLE_LINK_CONTROL_POINTER_OVERLAY.rawValue): hostPointerReported = visible
        default: break
        }
    }

    /// Re-read both host visibilities (the library reports unknown as soon as
    /// the link to the hub is gone, without a callback).
    private func syncHostVisibility() {
        let menu = UInt16(SKYLE_LINK_CONTROL_MENU_BAR.rawValue)
        let pointer = UInt16(SKYLE_LINK_CONTROL_POINTER_OVERLAY.rawValue)
        applyHostVisibility(controlId: menu, visible: client.hostVisibility(id: menu))
        applyHostVisibility(controlId: pointer, visible: client.hostVisibility(id: pointer))
    }

    var hostVisibilityNote: String {
        func word(_ v: Bool?) -> String { v == nil ? "unknown" : v! ? "visible" : "hidden" }
        return "Host reports: menu bar \(word(hostMenuBarReported)), pointer \(word(hostPointerReported))"
    }
    #endif

    private func handleState(_ s: skyle_connection_state) {
        state = s
        #if os(macOS)
        syncHostVisibility() // the link may have died with this edge
        #endif
        switch s {
        case SKYLE_STATE_LINK_SYNCED:
            connectionLabel = "Streaming"
            connectionColor = Color(red: 0.18, green: 0.80, blue: 0.44)   // green
            applyStreams()
        case SKYLE_STATE_DISCONNECTED:
            connectionLabel = "Disconnected"
            connectionColor = .gray
            deviceInfo = ""
        case SKYLE_STATE_ERROR:
            connectionLabel = "Error"
            connectionColor = Color(red: 0.91, green: 0.30, blue: 0.24)   // red
        default:
            connectionLabel = "Connecting…"
            connectionColor = Color(red: 0.95, green: 0.77, blue: 0.06)   // amber
        }
    }

    private static func movementName(_ type: UInt8) -> String {
        switch type {
        case 0: return "Fixation"
        case 1: return "Saccade"
        default: return "Unknown"
        }
    }
}
