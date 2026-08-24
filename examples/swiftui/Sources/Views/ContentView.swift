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
                #if os(macOS)
                if !vm.hostControlNote.isEmpty {
                    Text(vm.hostControlNote)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                #endif
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

            // Skyle Link host controls: fire-and-forget commands to the
            // hub-hosting Skyle app (only delivered while this app is a link client)
            #if os(macOS)
            HStack(spacing: 10) {
                Toggle("Menu bar", isOn: $vm.hostMenuBarVisible)
                    .toggleStyle(.button)
                    .onChange(of: vm.hostMenuBarVisible) { vm.setHostMenuBarVisible($0) }
                Toggle("Pointer overlay", isOn: $vm.hostPointerVisible)
                    .toggleStyle(.button)
                    .onChange(of: vm.hostPointerVisible) { vm.setHostPointerVisible($0) }
                Button("Calibrate") { vm.startHostCalibration() }
            }
            #endif

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
