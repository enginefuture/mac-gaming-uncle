import XCTest
import IndieCore
@testable import IndieCatalog

final class Dota2RecipeTests: XCTestCase {
    func testDota2RecipeMatchesBootstrapperWithoutDirectXImports() throws {
        let repository = try RecipeRepository.builtIn()
        for identity in [GameIdentity(steamAppID: 570, executableName: "dota2.exe"),
                         GameIdentity(executableName: "dota2.exe")] {
            let analysis = GameAnalysis(identity: identity, architecture: .x86_64,
                                        directX: .none, antiCheat: .none, importedLibraries: [])
            let recipe = try XCTUnwrap(repository.match(analysis))
            XCTAssertEqual(recipe.profiles.map(\.renderer), [.d3dMetal, .dxmt])
            XCTAssertEqual(recipe.profiles.first?.arguments, ["-dx11"])
            XCTAssertEqual(recipe.profiles.first?.syncBackend, .wineserver)
            XCTAssertEqual(recipe.profiles.first?.metalFX, false)
            XCTAssertEqual(recipe.profiles.first?.metal4, false)
        }
    }
}
