import CryptoKit
import Foundation
import IndieCore

public struct RecipeValidation: Codable, Sendable, Equatable {
    public let recipes: [GameRecipe]
    public let warnings: [String]
}

public struct RecipeRepository: Sendable {
    public let recipes: [GameRecipe]

    public init(recipes: [GameRecipe]) { self.recipes = recipes }

    public static func builtIn() throws -> RecipeRepository {
        guard let directory = PackagedResources.bundle(
            named: "MacGamingUncle_IndieCatalog", development: Bundle.module
        )?.resourceURL else {
            throw IndieError.notFound(L("内置配方资源缺失"))
        }
        return RecipeRepository(recipes: try load(from: directory).recipes)
    }

    public static func load(from directory: URL) throws -> RecipeValidation {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            throw IndieError.notFound(L("无法读取配方目录：\(directory.path)"))
        }
        var recipes: [GameRecipe] = []
        var warnings: [String] = []
        var ids: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            do {
                let recipe = try IndieJSON.decoder().decode(GameRecipe.self, from: Data(contentsOf: url))
                guard recipe.schemaVersion == 1 else { throw IndieError.invalidData(L("未知 schemaVersion")) }
                guard !recipe.id.isEmpty, !recipe.name.isEmpty, !recipe.profiles.isEmpty else { throw IndieError.invalidData(L("缺少 id、name 或 profiles")) }
                guard ids.insert(recipe.id).inserted else { throw IndieError.invalidData(L("重复配方 id：\(recipe.id)")) }
                recipes.append(recipe)
            } catch {
                warnings.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return RecipeValidation(recipes: recipes.sorted { $0.id < $1.id }, warnings: warnings)
    }

    public func match(_ analysis: GameAnalysis) -> GameRecipe? {
        if let appID = analysis.identity.steamAppID,
           let exact = recipes.first(where: { $0.steamAppIDs.contains(appID) }) { return exact }
        let executable = analysis.identity.executableName.lowercased()
        return recipes.first { $0.executableNames.contains(executable) }
    }
}
