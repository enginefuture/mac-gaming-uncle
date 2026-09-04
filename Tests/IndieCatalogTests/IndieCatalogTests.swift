import Foundation
import XCTest
@testable import IndieCatalog
@testable import IndieCore

final class IndieCatalogTests: XCTestCase {
    func testVDFParsesNestedObjectsAndEscapes() throws {
        let source = #"""
        "libraryfolders"
        {
            "0" { "path" "/Games/Steam" }
            // a comment
            "contentstatsid" "123"
        }
        """#
        let value = try VDFParser.parse(data: Data(source.utf8))
        let root = value["libraryfolders"]?.object
        XCTAssertEqual(root?["0"]?.object?["path"]?.string, "/Games/Steam")
    }

    func testPEAnalysisDetectsArchitectureRendererAndAntiCheat() throws {
        var data = Data(repeating: 0, count: 4096)
        data[0] = 0x4d; data[1] = 0x5a
        data[0x3c] = 0x80
        data[0x80] = 0x50; data[0x81] = 0x45
        data[0x84] = 0x64; data[0x85] = 0x86
        data.append(Data("d3d12.dll\0vgk.sys\0".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).exe")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let result = try PEAnalyzer.analyze(at: url)
        XCTAssertEqual(result.architecture, .x86_64)
        XCTAssertEqual(result.directX, .d3d12)
        XCTAssertEqual(result.antiCheat, .kernel)
    }

    func testRecipePrefersSteamIdentity() {
        let byName = GameRecipe(id: "name", name: "Name", executableNames: ["game.exe"], profiles: [.init(renderer: .wineD3D)])
        let bySteam = GameRecipe(id: "steam", name: "Steam", steamAppIDs: [99], profiles: [.init(renderer: .dxmt)])
        let analysis = GameAnalysis(identity: .init(steamAppID: 99, executableName: "game.exe"), architecture: .x86_64, directX: .d3d11, antiCheat: .none, importedLibraries: [])
        XCTAssertEqual(RecipeRepository(recipes: [byName, bySteam]).match(analysis)?.id, "steam")
    }

    func testGrimDawnPrefersD3DMetalWithDXMTFallback() throws {
        let repository = try RecipeRepository.builtIn()
        let analysis = GameAnalysis(
            identity: GameIdentity(steamAppID: 219990, executableName: "Grim Dawn.exe"),
            architecture: .x86_64,
            directX: .d3d11,
            antiCheat: .none,
            importedLibraries: ["d3d11.dll"]
        )
        let recipe = try XCTUnwrap(repository.match(analysis))
        XCTAssertEqual(recipe.profiles.map(\.renderer), [.d3dMetal, .dxmt, .wineD3D])
        XCTAssertEqual(recipe.profiles.first?.metalFX, false)
    }

    func testBuiltInRecipesLoad() throws {
        let repository = try RecipeRepository.builtIn()
        XCTAssertTrue(repository.recipes.contains { $0.id == "indie.compatibility-lab.d3d12" })
        let analysis = GameAnalysis(
            identity: GameIdentity(steamAppID: 4_364_910, executableName: "RuinsOfDawn-Win64-Shipping.exe"),
            architecture: .x86_64, directX: .d3d12, antiCheat: .none,
            importedLibraries: ["d3d12.dll"]
        )
        let recipe = repository.match(analysis)
        XCTAssertEqual(recipe?.id, "indie.steam.4364910.ruins-of-dawn")
        XCTAssertTrue(recipe?.profiles.first?.arguments.contains("-norhithread") == true)
    }

    func testSteamScannerMapsWindowsDriveInsideBottle() throws {
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }
        let primary = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let secondary = prefix.appendingPathComponent("drive_c/Games/steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondary.appendingPathComponent("common/Test Game"), withIntermediateDirectories: true)
        let folders = #"""
        "libraryfolders" { "0" { "path" "C:\\Games" } }
        """#
        try Data(folders.utf8).write(to: primary.appendingPathComponent("libraryfolders.vdf"))
        let manifest = #"""
        "AppState" { "appid" "1234" "name" "Test Game" "installdir" "Test Game" "buildid" "99" }
        """#
        try Data(manifest.utf8).write(to: secondary.appendingPathComponent("appmanifest_1234.acf"))
        let games = try SteamScanner.scan(steamApps: primary)
        XCTAssertEqual(games.first?.appID, 1234)
        XCTAssertEqual(games.first?.buildID, "99")
        XCTAssertEqual(games.first?.installDirectory.standardizedFileURL, secondary.appendingPathComponent("common/Test Game").standardizedFileURL)
    }

    func testSteamExecutableResolverPrefersTopLevelGameLauncher() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-executable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let shipping = root.appendingPathComponent("RuinsOfDawn/Binaries/Win64/RuinsOfDawn-Win64-Shipping.exe")
        let launcher = root.appendingPathComponent("RuinsOfDawn.exe")
        let prerequisite = root.appendingPathComponent("Engine/Extras/Redist/UE4PrereqSetup.exe")
        for file in [shipping, launcher, prerequisite] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: file)
        }
        let game = SteamGame(
            appID: 4364910, name: "Ruins of Dawn", installDirectory: root,
            buildID: "1", manifestURL: root.appendingPathComponent("appmanifest.acf")
        )
        XCTAssertEqual(
            try SteamExecutableResolver.preferredExecutable(for: game).standardizedFileURL,
            launcher.standardizedFileURL
        )
        XCTAssertEqual(
            try SteamExecutableResolver.shippingExecutable(for: game).standardizedFileURL,
            shipping.standardizedFileURL
        )
    }

    func testSteamExecutableResolverPrefersMatchingX64GameOverLegacyRootBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-x64-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Grim Dawn.exe")
        let x64 = root.appendingPathComponent("x64/Grim Dawn.exe")
        for file in [legacy, x64] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: file)
        }
        let game = SteamGame(
            appID: 219990, name: "Grim Dawn", installDirectory: root,
            buildID: "1", manifestURL: root.appendingPathComponent("appmanifest.acf")
        )
        XCTAssertEqual(
            try SteamExecutableResolver.preferredExecutable(for: game).standardizedFileURL,
            x64.standardizedFileURL
        )
        XCTAssertEqual(
            try SteamExecutableResolver.shippingExecutable(for: game).standardizedFileURL,
            x64.standardizedFileURL
        )
    }

    func testGrimDawnCompatibilityBacksUpAndEnablesClassicHUD() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-grim-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("drive_c/users/player/Documents/My Games/Grim Dawn/Settings")
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        let options = settings.appendingPathComponent("options.txt")
        let original = "uiScale                   = 0.5\nstandardHUD               = false\n"
        try original.write(to: options, atomically: true, encoding: .utf8)

        let first = try GrimDawnCompatibility.enableClassicHUD(bottleRoot: root)
        XCTAssertTrue(first.changed)
        XCTAssertTrue(try String(contentsOf: options, encoding: .utf8).contains("standardHUD               = true"))
        let backup = settings.appendingPathComponent("options.txt.indie-before-classic-hud")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)

        let second = try GrimDawnCompatibility.enableClassicHUD(bottleRoot: root)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
    }
}
