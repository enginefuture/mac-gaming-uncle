import Foundation
@preconcurrency import VideoToolbox
@preconcurrency import CoreVideo
import CoreMedia

/// Deliberately limited to SDK-documented dyadic phases. Not arbitrary 6x.
public enum FrameInterpolationMultiplier: Int, Sendable, CaseIterable {
    case double = 2
    case quadruple = 4
    public var configurationDepth: Int { self == .double ? 1 : 2 }
    public var phases: [Double] { (1..<rawValue).map { Double($0) / Double(rawValue) } }
}

/// Immutable ownership envelope for buffers crossing the capture/processor queues.
public struct InterpolationImage: @unchecked Sendable {
    public let buffer: CVPixelBuffer
    public let timestamp: CMTime
    public init(buffer: CVPixelBuffer, timestamp: CMTime) {
        self.buffer = buffer
        self.timestamp = timestamp
    }
}

@available(macOS 26.0, *)
public final class FrameInterpolationEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "indie.interpolation.processor", qos: .userInitiated)
    private let processor = VTFrameProcessor()
    private var configuration: VTLowLatencyFrameInterpolationConfiguration?
    private var sourcePool: CVPixelBufferPool?
    private var destinationPool: CVPixelBufferPool?
    private var transfer: VTPixelTransferSession?
    private var busy = false
    private var closed = false
    private let width: Int
    private let height: Int
    private let multiplier: FrameInterpolationMultiplier
    private let preserveStaticDetails: Bool
    private var staticRestorer: FrameStaticDetailRestorer?

    public static var isSupported: Bool { VTLowLatencyFrameInterpolationConfiguration.isSupported }
    public init(width: Int, height: Int, multiplier: FrameInterpolationMultiplier = .double, preserveStaticDetails: Bool = false) {
        self.width = width; self.height = height; self.multiplier = multiplier
        self.preserveStaticDetails = preserveStaticDetails
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "Indie.FrameInterpolation", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    /// Starts the ML session on a private queue, never on the UI/capture thread.
    public func prepare() async throws {
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard !self.closed, self.configuration == nil, Self.isSupported, self.width > 0, self.height > 0,
                          let config = VTLowLatencyFrameInterpolationConfiguration(
                            frameWidth: self.width, frameHeight: self.height, numberOfInterpolatedFrames: self.multiplier.configurationDepth
                          ) else { throw Self.failure("Interpolation is unavailable at this resolution.") }
                    self.sourcePool = try Self.pool(config.sourcePixelBufferAttributes)
                    self.destinationPool = try Self.pool(config.destinationPixelBufferAttributes)
                    guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &self.transfer) == noErr else {
                        throw Self.failure("Could not create pixel conversion session.")
                    }
                    try self.processor.startSession(configuration: config)
                    self.configuration = config
                    if self.preserveStaticDetails {
                        self.staticRestorer = try FrameStaticDetailRestorer(width: self.width, height: self.height)
                    }
                    reply.resume()
                } catch { reply.resume(throwing: error) }
            }
        }
    }

    private static func pool(_ attributes: [String: Any]) throws -> CVPixelBufferPool {
        var attributes = attributes
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] as [String: Any]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool else {
            throw failure("Could not allocate compatible image pool.")
        }
        return pool
    }

    private static func buffer(_ pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        guard let pool else { throw failure("Processor is not ready.") }
        var result: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result) == kCVReturnSuccess, let result else {
            throw failure("Could not allocate interpolation image.")
        }
        return result
    }

    /// Exactly one request can be in flight. No retry loop or unbounded queue.
    public func interpolate(previous: InterpolationImage, current: InterpolationImage) async throws -> InterpolationImage {
        let frames = try await interpolateBatch(previous: previous, current: current)
        return frames[frames.count / 2]
    }

    /// One motion-analysis request supplies all configured phases. Default remains 2x.
    /// The caller must pace these timestamps; completion count is not display FPS.
    public func interpolateBatch(previous: InterpolationImage, current: InterpolationImage) async throws -> [InterpolationImage] {
        try await withCheckedThrowingContinuation { reply in
            queue.async {
                do {
                    guard !self.closed, !self.busy, self.configuration != nil, let transfer = self.transfer else {
                        throw Self.failure("Processor is unavailable or busy.")
                    }
                    let gap = CMTimeSubtract(current.timestamp, previous.timestamp)
                    guard previous.timestamp.isNumeric, current.timestamp.isNumeric,
                          gap.isNumeric, gap.seconds > 0, gap.seconds <= 0.1 else {
                        throw Self.failure("Invalid or discontinuous interpolation timestamps.")
                    }
                    for image in [previous, current] {
                        guard CVPixelBufferGetWidth(image.buffer) == self.width, CVPixelBufferGetHeight(image.buffer) == self.height else {
                            throw Self.failure("Capture dimensions changed; restart interpolation.")
                        }
                    }
                    let a = try Self.buffer(self.sourcePool)
                    let b = try Self.buffer(self.sourcePool)
                    guard VTPixelTransferSessionTransferImage(transfer, from: previous.buffer, to: a) == noErr,
                          VTPixelTransferSessionTransferImage(transfer, from: current.buffer, to: b) == noErr else {
                        throw Self.failure("Unsupported input image format.")
                    }
                    let result = try self.multiplier.phases.map { phase in
                        InterpolationImage(buffer: try Self.buffer(self.destinationPool),
                                           timestamp: CMTimeAdd(previous.timestamp, CMTimeMultiplyByFloat64(gap, multiplier: phase)))
                    }
                    let destinations = try result.map { image in
                        guard let frame = VTFrameProcessorFrame(buffer: image.buffer, presentationTimeStamp: image.timestamp) else {
                            throw Self.failure("Invalid destination frame.")
                        }
                        return frame
                    }
                    guard let first = VTFrameProcessorFrame(buffer: a, presentationTimeStamp: previous.timestamp),
                          let second = VTFrameProcessorFrame(buffer: b, presentationTimeStamp: current.timestamp),
                          let parameters = VTLowLatencyFrameInterpolationParameters(
                            sourceFrame: second, previousFrame: first,
                            interpolationPhase: self.multiplier.phases.map(Float.init), destinationFrames: destinations
                          ) else { throw Self.failure("Invalid interpolation frame parameters.") }
                    self.busy = true
                    self.processor.process(parameters: parameters) { _, error in
                        self.queue.async {
                            self.busy = false
                            if let error { reply.resume(throwing: error) }
                            else {
                                do {
                                    let restored = try result.map { image in
                                        guard let restorer = self.staticRestorer else { return image }
                                        return InterpolationImage(buffer: try restorer.restore(previous: previous.buffer,
                                            current: current.buffer, generated: image.buffer), timestamp: image.timestamp)
                                    }
                                    reply.resume(returning: restored)
                                } catch { reply.resume(throwing: error) }
                            }
                            if self.closed { self.dispose() }
                        }
                    }
                } catch { reply.resume(throwing: error) }
            }
        }
    }

    public func close() {
        queue.async { self.closed = true; if !self.busy { self.dispose() } }
    }
    private func dispose() {
        if configuration != nil { processor.endSession() }
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
        configuration = nil; transfer = nil; sourcePool = nil; destinationPool = nil; staticRestorer = nil
    }
}
