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
    @Published var face: eap_complex_face?
    @Published var videoImage: CGImage?

    private let client = SkyleClient()
    private var state: eap_connection_state = EAP_STATE_DISCONNECTED

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
        client.start()
    }

    func shutdown() {
        client.stop()
    }

    /// Apply stream subscriptions for the current connection state + tab.
    func applyStreams() {
        guard state == EAP_STATE_LINK_SYNCED else { return }
        client.enableGaze(true)                              // always live
        client.enablePositioning(selection == .positioning)
        client.enableVideo(selection == .video)              // off when hidden saves bandwidth
    }

    private func handleState(_ s: eap_connection_state) {
        state = s
        switch s {
        case EAP_STATE_LINK_SYNCED:
            connectionLabel = "Streaming"
            connectionColor = Color(red: 0.18, green: 0.80, blue: 0.44)   // green
            applyStreams()
        case EAP_STATE_DISCONNECTED:
            connectionLabel = "Disconnected"
            connectionColor = .gray
            deviceInfo = ""
        case EAP_STATE_ERROR:
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
