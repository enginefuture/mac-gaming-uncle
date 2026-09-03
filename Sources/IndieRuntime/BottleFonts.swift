import Foundation
import IndieCore

public struct BottleFontRegistration: Sendable, Equatable {
    public let installedFonts: [URL]
    public let registryFile: URL
    public let registryWindowsPath: String
}

public enum BottleFonts {
    private struct HostFont {
        let source: URL
        let destinationName: String
        let registryNames: [String]
        let familyName: String
        let supportsCJK: Bool
    }

    private static let hostFonts = [
        HostFont(
            source: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf"),
            destinationName: "arial.ttf",
            registryNames: ["Arial (TrueType)"],
            familyName: "Arial",
            supportsCJK: false
        ),
        HostFont(
            source: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
            destinationName: "arialuni.ttf",
            registryNames: ["Arial Unicode MS (TrueType)"],
            familyName: "Arial Unicode MS",
            supportsCJK: true
        ),
        // Steam's Chromium UI does not consistently honor Wine's GDI font
        // replacement table. Register a real CJK family in the Windows font
        // catalog so DirectWrite/Skia can discover it for glyph fallback.
        HostFont(
            source: URL(fileURLWithPath: "/System/Library/Fonts/Hiragino Sans GB.ttc"),
            destinationName: "hiraginosansgb.ttc",
            registryNames: [
                "Hiragino Sans GB (TrueType)",
                "Hiragino Sans GB W3 (TrueType)",
                "Hiragino Sans GB W6 (TrueType)",
            ],
            familyName: "Hiragino Sans GB",
            supportsCJK: true
        ),
    ]

    private static let replacements = [
        "MS Shell Dlg", "MS Shell Dlg 2", "MS Sans Serif", "Tahoma",
        "Microsoft YaHei", "Microsoft YaHei UI", "Dengxian", "SimSun", "NSimSun",
        "SimSun-ExtB", "SimHei", "FangSong", "KaiTi", "SimKai",
        "Microsoft JhengHei", "Microsoft JhengHei UI", "MingLiU", "PMingLiU",
        "MingLiU-ExtB", "PMingLiU-ExtB", "MS UI Gothic", "Meiryo", "Meiryo UI",
        "Malgun Gothic",
    ]

    public static func prepare(in bottle: BottleRecord) throws -> BottleFontRegistration {
        let fontsDirectory = bottle.root.appendingPathComponent("drive_c/windows/Fonts", isDirectory: true)
        let tempDirectory = bottle.root.appendingPathComponent("drive_c/windows/temp", isDirectory: true)
        try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        var installed: [URL] = []
        var installedFonts: [(font: HostFont, destination: URL)] = []
        for font in hostFonts where FileManager.default.fileExists(atPath: font.source.path) {
            let destination = fontsDirectory.appendingPathComponent(font.destinationName)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let staging = fontsDirectory.appendingPathComponent(".\(font.destinationName)-\(UUID().uuidString)")
                do {
                    try FileManager.default.copyItem(at: font.source, to: staging)
                    try FileManager.default.moveItem(at: staging, to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    throw error
                }
            }
            installed.append(destination)
            installedFonts.append((font, destination))
        }
        guard let cjkFont = installedFonts.last(where: { $0.font.supportsCJK }) else {
            throw IndieError.notFound("这台 Mac 没有可用于 Wine 的中文字体")
        }

        let registryFile = tempDirectory.appendingPathComponent("indie-cjk-fonts.reg")
        let registryText = registryContents(installedFonts: installedFonts, cjkFont: cjkFont)
        var registryData = Data([0xff, 0xfe])
        registryData.append(registryText.data(using: .utf16LittleEndian)!)
        try registryData.write(to: registryFile, options: .atomic)

        return BottleFontRegistration(
            installedFonts: installed,
            registryFile: registryFile,
            registryWindowsPath: try WinePath.windowsPath(for: registryFile, in: bottle)
        )
    }

    private static func registryContents(
        installedFonts: [(font: HostFont, destination: URL)],
        cjkFont: (font: HostFont, destination: URL)
    ) -> String {
        let fontEntries = installedFonts.flatMap { installed in
            installed.font.registryNames.map { "\"\($0)\"=\"\(installed.destination.lastPathComponent)\"" }
        }
        let cjkFamily = cjkFont.font.familyName
        let preferredLink = "\(cjkFont.destination.lastPathComponent),\(cjkFont.font.familyName)"
        let links = [preferredLink] + installedFonts
            .filter { $0.font.supportsCJK && $0.destination != cjkFont.destination }
            .map { "\($0.destination.lastPathComponent),\($0.font.familyName)" }
        let linkedFamilies = [
            "Arial", "Arial Unicode MS", "Segoe UI", "Tahoma",
            "Microsoft Sans Serif", "Motiva Sans", "Helvetica",
        ]
        var lines = [
            "Windows Registry Editor Version 5.00",
            "",
            "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]",
        ]
        lines.append(contentsOf: fontEntries)
        lines.append(contentsOf: [
            "",
            "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Fonts]",
        ])
        lines.append(contentsOf: fontEntries)
        // Wine rebuilds the machine-wide font catalog during startup. Keeping
        // a per-user registration makes the copied fonts visible to CEF even
        // after that refresh.
        lines.append(contentsOf: [
            "",
            "[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]",
        ])
        lines.append(contentsOf: fontEntries)
        lines.append(contentsOf: [
            "",
            "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink]",
        ])
        lines.append(contentsOf: linkedFamilies.map {
            "\"\($0)\"=hex(7):\(multiStringHex(links))"
        })
        lines.append(contentsOf: [
            "",
            "[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink]",
        ])
        lines.append(contentsOf: linkedFamilies.map {
            "\"\($0)\"=hex(7):\(multiStringHex(links))"
        })
        lines.append(contentsOf: [
            "",
            "[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]",
        ])
        lines.append(contentsOf: replacements.map { "\"\($0)\"=\"\(cjkFamily)\"" })
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private static func multiStringHex(_ values: [String]) -> String {
        let value = values.joined(separator: "\0") + "\0\0"
        let bytes = value.data(using: .utf16LittleEndian) ?? Data()
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ",")
    }
}
