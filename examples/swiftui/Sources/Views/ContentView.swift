import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: SkyleViewModel

    var body: some View {
        VStack(spacing: 14) {

            // Connection indicator + device info
            HStack(spacing: 8) {
                Circle()
                    .fill(vm.connectionColor)
                    .frame(width: 14, height: 14)
                Text(vm.connectionLabel)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(vm.deviceInfo)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Segmented control
            Picker("View", selection: $vm.selection) {
                Text("Positioning").tag(ViewMode.positioning)
                Text("Video").tag(ViewMode.video)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .onChange(of: vm.selection) { _ in vm.applyStreams() }

            // Content area
            Group {
                switch vm.selection {
                case .positioning:
                    PositioningCanvasView(face: vm.face)
                case .video:
                    VideoCanvasView(image: vm.videoImage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Gaze readout
            HStack {
                Text(vm.gazeText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        }
        .padding(16)
        .background(Color(white: 0.1).ignoresSafeArea())
    }
}
