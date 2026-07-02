import SwiftUI

/// Diagnostic positioning view, drawn in camera/sensor space (2464 × 2064) and
/// letterboxed into the available area — the same geometry the Flutter app uses.
struct PositioningCanvasView: View {
    static let sensorWidth: CGFloat = 2464
    static let sensorHeight: CGFloat = 2064

    let face: eap_complex_face?

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.sensorWidth, size.height / Self.sensorHeight)
            guard scale > 0 else { return }
            let drawW = Self.sensorWidth * scale
            let drawH = Self.sensorHeight * scale
            let ox = (size.width - drawW) / 2
            let oy = (size.height - drawH) / 2

            // Background panel
            let panel = Path(roundedRect: CGRect(x: ox, y: oy, width: drawW, height: drawH), cornerRadius: 10)
            context.fill(panel, with: .color(.black.opacity(0.2)))

            guard let face = face else {
                context.draw(
                    Text("Waiting for positioning data…").foregroundColor(.white.opacity(0.6)),
                    at: CGPoint(x: ox + drawW / 2, y: oy + drawH / 2))
                return
            }

            func map(_ x: Float, _ y: Float) -> CGPoint {
                CGPoint(x: ox + CGFloat(x) * scale, y: oy + CGFloat(y) * scale)
            }

            func isZero(_ p: eap_pointf) -> Bool { p.x == 0 && p.y == 0 }

            func drawEye(_ eye: eap_complex_eye) {
                // Eye bounding box (image-space uint16)
                let b = eye.bounding_rect
                if b.right > b.left && b.bottom > b.top {
                    let tl = map(Float(b.left), Float(b.top))
                    let br = map(Float(b.right), Float(b.bottom))
                    let rect = Path(CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y))
                    context.stroke(rect, with: .color(.white.opacity(0.4)), lineWidth: 1)
                }

                // Iris ring from the four extreme points
                let iris = eye.iris
                if !isZero(iris.center) {
                    let c = map(iris.center.x, iris.center.y)
                    let rx = CGFloat(abs(iris.right.x - iris.center.x) + abs(iris.left.x - iris.center.x)) / 2 * scale
                    let ry = CGFloat(abs(iris.bottom.y - iris.center.y) + abs(iris.top.y - iris.center.y)) / 2 * scale
                    if rx > 0 && ry > 0 {
                        let ring = Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry))
                        context.stroke(ring, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                    }
                }

                // Pupil: fitted (rotated) ellipse + centre dot
                let pupil = eye.pupil
                if !isZero(pupil.center) {
                    let c = map(pupil.ellipse.center.x, pupil.ellipse.center.y)
                    let rx = CGFloat(pupil.ellipse.size.width) / 2 * scale
                    let ry = CGFloat(pupil.ellipse.size.height) / 2 * scale
                    if rx > 0 && ry > 0 {
                        var rotated = context
                        rotated.translateBy(x: c.x, y: c.y)
                        rotated.rotate(by: .degrees(Double(pupil.ellipse.angle)))
                        let e = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
                        rotated.stroke(e, with: .color(.green), lineWidth: 1.5)
                    }
                    let dot = map(pupil.center.x, pupil.center.y)
                    let dotPath = Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5))
                    context.fill(dotPath, with: .color(.green))
                }

                // Glints
                for glint in [eye.left_glint.center, eye.right_glint.center] where !isZero(glint) {
                    let g = map(glint.x, glint.y)
                    let gp = Path(ellipseIn: CGRect(x: g.x - 2, y: g.y - 2, width: 4, height: 4))
                    context.fill(gp, with: .color(Color(red: 0.31, green: 0.76, blue: 0.97)))
                }
            }

            drawEye(face.eyes.left)
            drawEye(face.eyes.right)

            let lMm = face.eyes.left.iris.distance_mm
            let rMm = face.eyes.right.iris.distance_mm
            let distance = "Distance   L \(format(lMm))   R \(format(rMm))"
            context.draw(
                Text(distance).font(.system(size: 13)).foregroundColor(.white),
                at: CGPoint(x: ox + 10, y: oy + drawH - 18), anchor: .topLeading)
        }
    }

    private func format(_ mm: Float) -> String {
        mm > 0 ? String(format: "%.0f mm", mm) : "—"
    }
}
