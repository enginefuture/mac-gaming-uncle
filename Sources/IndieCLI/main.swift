import Foundation
import IndieCatalog
import IndieCore
import IndieRuntime

@main
struct IndieCLI {
    static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            let json = arguments.firstIndex(of: "--json").map { arguments.remove(at: $0); return true } ?? false
            guard let command = arguments.first else { throw IndieError.invalidArgument(usage) }
            arguments.removeFirst()
            let output: AnyEncodable
            switch command {
            case "doctor":
                output = AnyEncodable(await SystemProbe().run())
            case "pe":
                guard let path = arguments.first else { throw IndieError.invalidArgument("pe 需要 EXE 路径") }
                output = AnyEncodable(try PEAnalyzer.analyze(at: URL(fileURLWithPath: path)))
            case "steam-scan":
                guard let path = arguments.first else { throw IndieError.invalidArgument("steam-scan 需要 steamapps 路径") }
                output = AnyEncodable(try SteamScanner.scan(steamApps: URL(fileURLWithPath: path, isDirectory: true)))
            case "recipes":
                guard arguments.first == "validate", arguments.count >= 2 else { throw IndieError.invalidArgument("recipes validate 需要配方目录") }
                output = AnyEncodable(try RecipeRepository.load(from: URL(fileURLWithPath: arguments[1], isDirectory: true)))
            case "manifest":
                guard arguments.first == "verify", arguments.count >= 3 else { throw IndieError.invalidArgument("manifest verify <manifest.json> <public-key-base64>") }
                let manifest = try IndieJSON.decoder().decode(RuntimeManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
                try ManifestSecurity.verify(manifest, publicKeyBase64: arguments[2])
                output = AnyEncodable(["valid": "true", "runtime": manifest.id, "version": manifest.version.description])
            case "gptk":
                guard arguments.first == "import", arguments.count >= 2 else { throw IndieError.invalidArgument("gptk import 需要 Apple GPTK DMG 或目录") }
                output = AnyEncodable(try await GPTKImporter(paths: .userDefault).importFromAppleImage(URL(fileURLWithPath: arguments[1])))
            case "wine":
                if arguments.first == "latest" {
                    output = AnyEncodable(try await CommunityWineBootstrapper(paths: .userDefault).latest())
                } else if arguments.first == "gaming-install" {
                    output = AnyEncodable(try await CommunityIndieWineBootstrapper(paths: .userDefault).installLatest())
                } else if arguments.first == "local-install", arguments.count >= 2 {
                    output = AnyEncodable(try await CommunityIndieWineBootstrapper(paths: .userDefault).installLocalBuild(
                        from: URL(fileURLWithPath: arguments[1], isDirectory: true)
                    ))
                } else {
                    throw IndieError.invalidArgument("wine latest | wine gaming-install | wine local-install <runtime-root>")
                }
            case "dxvk":
                guard arguments.first == "install", arguments.count >= 2 else {
                    throw IndieError.invalidArgument("dxvk install <bottle-root>")
                }
                let bottle = BottleRecord(
                    name: "DXVK", root: URL(fileURLWithPath: arguments[1], isDirectory: true), runtimeID: "diagnostic"
                )
                let overlay = try await CommunityDXVKBootstrapper(paths: .userDefault).installLatest()
                output = AnyEncodable(try BottleDXVKInstaller.install(overlay: overlay, in: bottle))
            case "steam":
                guard arguments.first == "repair", arguments.count >= 2 else { throw IndieError.invalidArgument("steam repair <bottle-root> [wrapper.exe]") }
                let bottle = BottleRecord(name: "Steam", root: URL(fileURLWithPath: arguments[1], isDirectory: true), runtimeID: "diagnostic")
                let wrapper = arguments.count >= 3
                    ? URL(fileURLWithPath: arguments[2])
                    : SteamCompatibilityManager.bundledWrapperURL()
                guard let wrapper else { throw IndieError.notFound("找不到 Steam WebHelper 包装器") }
                output = AnyEncodable(try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper))
            case "fonts":
                guard arguments.first == "repair", arguments.count >= 3 else {
                    throw IndieError.invalidArgument("fonts repair <bottle-root> <runtime-root>")
                }
                let bottle = BottleRecord(
                    name: "Fonts", root: URL(fileURLWithPath: arguments[1], isDirectory: true), runtimeID: CommunityIndieWineBootstrapper.runtimeID
                )
                let provider = WineRuntimeProvider(
                    manifest: CommunityIndieWineBootstrapper.manifest,
                    root: URL(fileURLWithPath: arguments[2], isDirectory: true)
                )
                try await provider.prepareBottleForInstaller(bottle)
                output = AnyEncodable(["repaired": "true", "bottle": bottle.root.path])
            case "bottle":
                guard arguments.first == "create", arguments.count >= 4 else { throw IndieError.invalidArgument("bottle create <name> <manifest.json> <runtime-root>") }
                let manifest = try IndieJSON.decoder().decode(RuntimeManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
                let paths = IndiePaths.userDefault
                let store = StateStore(databaseURL: paths.database)
                let provider = WineRuntimeProvider(manifest: manifest, root: URL(fileURLWithPath: arguments[3], isDirectory: true))
                output = AnyEncodable(try await BottleManager(paths: paths, store: store).create(name: arguments[1], runtime: provider))
            default:
                throw IndieError.invalidArgument("未知命令：\(command)\n\n\(usage)")
            }
            try printOutput(output, json: json)
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static let usage = """
    indiectl [--json] <command>

      doctor
      pe <game.exe>
      steam-scan <steamapps-directory>
      recipes validate <recipes-directory>
      manifest verify <manifest.json> <ed25519-public-key-base64>
      gptk import <apple-gptk.dmg|mounted-directory>
      wine latest
      wine gaming-install
      wine local-install <runtime-root>
      dxvk install <bottle-root>
      steam repair <bottle-root> [wrapper.exe]
      fonts repair <bottle-root> <runtime-root>
      bottle create <name> <manifest.json> <runtime-root>
    """

    private static func printOutput(_ value: AnyEncodable, json: Bool) throws {
        let data = try IndieJSON.encoder(pretty: true).encode(value)
        if json { print(String(decoding: data, as: UTF8.self)) }
        else if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in object.keys.sorted() { print("\(key): \(object[key]!)") }
        } else { print(String(decoding: data, as: UTF8.self)) }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { encodeClosure = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
