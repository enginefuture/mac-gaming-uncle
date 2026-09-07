import Foundation

/// Retina mode is prefix-wide. Different policies must not share a live session.
public struct SteamDisplayPolicy: Codable, Equatable, Sendable {
    public let retinaEnabled: Bool
    public let topology: String

    public init(retinaEnabled: Bool, topology: String) {
        self.retinaEnabled = retinaEnabled
        self.topology = topology
    }

    public var registryArguments: [String] {
        ["reg", "add", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode",
         "/t", "REG_SZ", "/d", retinaEnabled ? "Y" : "N", "/f"]
    }
}
