import Foundation
import CoreVideo
import CoreMedia

@main struct FrameInterpolationProbe {
    static func main() async {
        guard #available(macOS 26, *) else { print("unsupported OS"); return }
        let width = Int(CommandLine.arguments.dropFirst().first ?? "1280") ?? 1280
        let height = width * 9 / 16
        Task { try? await Task.sleep(for: .seconds(20)); print("probe timeout"); exit(2) }
        let engine = FrameInterpolationEngine(width: width, height: height)
        defer { engine.close() }
        do {
            print("supported=\(FrameInterpolationEngine.isSupported) requested=\(width)x\(height)")
            try await engine.prepare()
            let start = Date()
            var successes = 0
            while Date().timeIntervalSince(start) < 10 && successes < 6 {
                var inputs: [InterpolationImage] = []
                for frame in 0..<2 {
                    var pixel: CVPixelBuffer?
                    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
                    guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { exit(3) }
                    CVPixelBufferLockBaseAddress(pixel, [])
                    let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
                    let row = CVPixelBufferGetBytesPerRow(pixel)
                    for y in 0..<height { for x in 0..<width {
                        let offset = y * row + x * 4
                        let light: UInt8 = x > width / 3 + frame * 24 && x < width / 3 + 120 + frame * 24 ? 220 : 30
                        base[offset] = light; base[offset+1] = light; base[offset+2] = light; base[offset+3] = 255
                    } }
                    CVPixelBufferUnlockBaseAddress(pixel, [])
                    inputs.append(InterpolationImage(buffer: pixel, timestamp: CMTime(value: Int64(frame), timescale: 60)))
                }
                let began = Date()
                do {
                    let output = try await engine.interpolate(previous: inputs[0], current: inputs[1])
                    print("output=\(CVPixelBufferGetWidth(output.buffer))x\(CVPixelBufferGetHeight(output.buffer)) time_ms=\(Date().timeIntervalSince(began)*1000)")
                    successes += 1
                } catch {
                    print("processing error: \(error)")
                    if (error as NSError).code != -12911 { throw error }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
            if successes == 0 { exit(4) }
        } catch { print("failed: \(error)"); exit(1) }
    }
}
