import Foundation

public struct FrameContentSignature: Equatable, Sendable {
    public let luma: [UInt8]
    public init(luma: [UInt8]) { self.luma = luma }
    public func isSceneCut(from previous: Self) -> Bool {
        guard !luma.isEmpty, luma.count == previous.luma.count else { return true }
        let difference = zip(luma, previous.luma).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(difference) / Double(luma.count * 255) > 0.35
    }
}
