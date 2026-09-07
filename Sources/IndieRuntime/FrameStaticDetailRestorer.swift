import Foundation
import Metal
import CoreVideo
import VideoToolbox

/// Optional experimental post-pass. Restores original pixels only where a 5x5
/// neighbourhood is unchanged in both source frames. No HUD coordinates/ground truth.
/// Queue-confined; this is not a general solution for moving UI or occlusions.
final class FrameStaticDetailRestorer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let cache: CVMetalTextureCache
    private let pool: CVPixelBufferPool
    private let transfer: VTPixelTransferSession

    init(width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Self.failure("Metal unavailable")
        }
        self.device = device; self.queue = queue
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void restore_static(texture2d<float, access::read> a [[texture(0)]],
                                   texture2d<float, access::read> b [[texture(1)]],
                                   texture2d<float, access::read> generated [[texture(2)]],
                                   texture2d<float, access::write> output [[texture(3)]],
                                   uint2 p [[thread_position_in_grid]]) {
            if (p.x >= output.get_width() || p.y >= output.get_height()) return;
            float change = 0.0;
            int2 limit = int2(output.get_width()-1, output.get_height()-1);
            for (int y=-2; y<=2; ++y) {
                for (int x=-2; x<=2; ++x) {
                    uint2 q = uint2(clamp(int2(p)+int2(x,y), int2(0), limit));
                    float3 d = abs(a.read(q).rgb - b.read(q).rgb);
                    change = max(change, max(d.r, max(d.g,d.b)));
                }
            }
            output.write(change < (0.5/255.0) ? b.read(p) : generated.read(p), p);
        }
        """, options: nil)
        guard let function = library.makeFunction(name: "restore_static") else { throw Self.failure("Kernel unavailable") }
        pipeline = try device.makeComputePipelineState(function: function)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw Self.failure("Texture cache unavailable")
        }
        self.cache = cache
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height, kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool else {
            throw Self.failure("Buffer pool unavailable")
        }
        self.pool = pool
        var transfer: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) == noErr, let transfer else {
            throw Self.failure("Pixel transfer unavailable")
        }
        self.transfer = transfer
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Indie.StaticDetail", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func buffer() throws -> CVPixelBuffer {
        var pixel: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &pixel) == kCVReturnSuccess, let pixel else {
            throw Self.failure("Restoration pool exhausted")
        }
        return pixel
    }
    private func texture(_ buffer: CVPixelBuffer) throws -> CVMetalTexture {
        var texture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture) == kCVReturnSuccess,
              let texture else { throw Self.failure("Expected Metal-compatible BGRA source") }
        return texture
    }
    func restore(previous: CVPixelBuffer, current: CVPixelBuffer, generated: CVPixelBuffer) throws -> CVPixelBuffer {
        let converted = try buffer(), output = try buffer()
        guard VTPixelTransferSessionTransferImage(transfer, from: generated, to: converted) == noErr else {
            throw Self.failure("Generated frame conversion failed")
        }
        let wrappers = try [previous, current, converted, output].map(texture)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw Self.failure("Metal command unavailable")
        }
        encoder.setComputePipelineState(pipeline)
        for (index, wrapper) in wrappers.enumerated() { encoder.setTexture(CVMetalTextureGetTexture(wrapper), index: index) }
        encoder.dispatchThreads(MTLSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output), depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        withExtendedLifetime(wrappers) {}
        guard command.status == .completed else { throw command.error ?? Self.failure("GPU restoration failed") }
        return output
    }
    deinit { VTPixelTransferSessionInvalidate(transfer) }
}
