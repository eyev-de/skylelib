import SwiftUI

/// Shows the device video stream. The view-model converts each raw frame into a
/// CGImage (cross-platform), which we display scaled to fit.
struct VideoCanvasView: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.2))
            if let image = image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.low)
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Text("No video").foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
