import CoreGraphics
import Foundation

/// Which stream the content area is showing.
enum ViewMode: Hashable {
    case positioning
    case video
}

/// Read a fixed C `char[N]` tuple (e.g. `firmware`) into a Swift String,
/// stopping at the first NUL.
func cTupleToString<T>(_ tuple: T, maxLength: Int) -> String {
    withUnsafeBytes(of: tuple) { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        var out = [UInt8]()
        for i in 0..<min(maxLength, bytes.count) {
            let b = bytes[i]
            if b == 0 { break }
            out.append(b)
        }
        return String(decoding: out, as: UTF8.self)
    }
}

/// Build a displayable image from a raw device video frame.
/// Channels: 1 = grayscale, 3 = RGB, 4 = RGBA. Output is RGBX (alpha ignored).
func makeCGImage(width: Int, height: Int, channels: Int, pixels: [UInt8]) -> CGImage? {
    guard width > 0, height > 0, !pixels.isEmpty else { return nil }

    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let count = pixels.count
    for i in 0..<(width * height) {
        let s = i * channels
        let d = i * 4
        if channels == 1 {
            let g = s < count ? pixels[s] : 0
            rgba[d] = g; rgba[d + 1] = g; rgba[d + 2] = g
        } else {
            rgba[d]     = s < count ? pixels[s] : 0
            rgba[d + 1] = s + 1 < count ? pixels[s + 1] : 0
            rgba[d + 2] = s + 2 < count ? pixels[s + 2] : 0
        }
        rgba[d + 3] = 255
    }

    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent)
}
