import IndieCore
import Foundation

public struct GPTKDownloadSnapshot: Sendable, Equatable {
    public let completedImage: URL?
    public let partialDownload: URL?
    public let partialSize: Int64

    public init(completedImage: URL?, partialDownload: URL?, partialSize: Int64) {
        self.completedImage = completedImage
        self.partialDownload = partialDownload
        self.partialSize = partialSize
    }
}

public enum GPTKDownloadWatcher {
    public static func scan(_ directory: URL, fileManager: FileManager = .default) -> GPTKDownloadSnapshot {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let files = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )) ?? []
        let matching = files.compactMap { url -> (URL, URLResourceValues)? in
            guard isGPTK4Name(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (url, values)
        }
        let ordered = matching.sorted {
            ($0.1.contentModificationDate ?? .distantPast) > ($1.1.contentModificationDate ?? .distantPast)
        }
        let completed = ordered.first { $0.0.pathExtension.lowercased() == "dmg" }?.0
        let partial = ordered.first {
            ["crdownload", "download", "part"].contains($0.0.pathExtension.lowercased())
        }
        return GPTKDownloadSnapshot(
            completedImage: completed,
            partialDownload: partial?.0,
            partialSize: Int64(partial?.1.fileSize ?? 0)
        )
    }

    public static func isGPTK4Name(_ name: String) -> Bool {
        let normalized = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        // Apple's general GPTK image contains documentation and samples only.
        // D3DMetal lives in the separately listed Windows evaluation environment.
        let product = normalized.contains("evaluation environment for windows games")
        guard product else { return false }
        return normalized.range(of: #"(^|[^0-9])4(?:[. ]|$)"#, options: .regularExpression) != nil
    }
}
