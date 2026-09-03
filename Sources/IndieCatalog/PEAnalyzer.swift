import CryptoKit
import Foundation
import IndieCore

public enum PEAnalyzer {
    public static func analyze(at url: URL, steamAppID: UInt64? = nil) throws -> GameAnalysis {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 4096), header.count >= 64,
              header[0] == 0x4d, header[1] == 0x5a else {
            throw IndieError.invalidData("不是有效的 Windows PE 可执行文件")
        }
        let peOffset = Int(readUInt32(header, at: 0x3c))
        try handle.seek(toOffset: 0)
        guard let extended = try handle.read(upToCount: max(4096, peOffset + 32)), extended.count >= peOffset + 8,
              extended[peOffset] == 0x50, extended[peOffset + 1] == 0x45,
              extended[peOffset + 2] == 0, extended[peOffset + 3] == 0 else {
            throw IndieError.invalidData("PE 文件头损坏")
        }
        let machine = readUInt16(extended, at: peOffset + 4)
        let architecture: CPUArchitecture = switch machine {
        case 0x014c: .i386
        case 0x8664: .x86_64
        case 0xaa64: .arm64
        default: .unknown
        }

        try handle.seek(toOffset: 0)
        var hash = SHA256()
        var carry = Data()
        var libraries: Set<String> = []
        var antiCheat: AntiCheatStatus = .none
        let warnings: [String] = []
        let needles = [
            "d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll",
            "easyanticheat_x64.dll", "easyanticheat_eos.sys", "battleye", "bedaisy.sys", "vgk.sys", "faceit.sys", "xigncode3", "gameguard.des", "npggnt.des", "ricochet.sys"
        ]
        let needleData = Dictionary(uniqueKeysWithValues: needles.map { ($0, Data($0.utf8)) })
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hash.update(data: chunk)
            var scan = carry
            scan.append(chunk)
            // PE files are mostly binary. Decoding every megabyte as Unicode,
            // lowercasing it and running localized String searches made large
            // UE executables take minutes to inspect. Imported DLL names are
            // ASCII, so fold only ASCII bytes and search Data directly.
            scan.withUnsafeMutableBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for index in bytes.indices where bytes[index] >= 0x41 && bytes[index] <= 0x5a {
                    bytes[index] += 0x20
                }
            }
            for needle in needles where !libraries.contains(needle) {
                if let bytes = needleData[needle], scan.range(of: bytes) != nil {
                    libraries.insert(needle)
                }
            }
            carry = chunk.suffix(256)
        }
        let kernelMarkers: Set<String> = [
            "bedaisy.sys", "vgk.sys", "faceit.sys", "ricochet.sys",
            "xigncode3", "gameguard.des", "npggnt.des",
        ]
        let userModeMarkers: Set<String> = ["easyanticheat_x64.dll", "easyanticheat_eos.sys", "battleye"]
        if !libraries.isDisjoint(with: kernelMarkers) {
            antiCheat = .kernel
        } else if !libraries.isDisjoint(with: userModeMarkers) {
            antiCheat = .unknown
        }
        let checksum = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let directX: DirectXVersion
        if libraries.contains("d3d12.dll") { directX = .d3d12 }
        else if libraries.contains("d3d11.dll") { directX = .d3d11 }
        else if libraries.contains("d3d10.dll") || libraries.contains("d3d10core.dll") { directX = .d3d10 }
        else if libraries.contains("d3d9.dll") { directX = .d3d9 }
        else if libraries.contains("d3d8.dll") { directX = .d3d8 }
        else { directX = .none }

        return GameAnalysis(
            identity: GameIdentity(steamAppID: steamAppID, executableSHA256: checksum, executableName: url.lastPathComponent),
            architecture: architecture,
            directX: directX,
            antiCheat: antiCheat,
            importedLibraries: libraries,
            warnings: warnings
        )
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
