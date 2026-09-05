import IndieCore
import Foundation

public struct SteamStoreItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UInt64
    public let name: String
    public let imageURL: URL?
    public let originalPrice: Int?
    public let finalPrice: Int?
    public let currency: String?
    public let discountPercent: Int

    public init(
        id: UInt64,
        name: String,
        imageURL: URL?,
        originalPrice: Int?,
        finalPrice: Int?,
        currency: String?,
        discountPercent: Int
    ) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.originalPrice = originalPrice
        self.finalPrice = finalPrice
        self.currency = currency
        self.discountPercent = discountPercent
    }
}

public struct SteamStoreCatalog: Codable, Sendable, Equatable {
    public let specials: [SteamStoreItem]
    public let topSellers: [SteamStoreItem]
    public let newReleases: [SteamStoreItem]

    public init(specials: [SteamStoreItem], topSellers: [SteamStoreItem], newReleases: [SteamStoreItem]) {
        self.specials = specials
        self.topSellers = topSellers
        self.newReleases = newReleases
    }
}

public enum SteamNativeStoreService {
    public static func featured(session: URLSession = .shared) async throws -> SteamStoreCatalog {
        let url = URL(string: "https://store.steampowered.com/api/featuredcategories?cc=CN&l=\(AppLanguage.steamLanguage)")!
        let response: FeaturedResponse = try await request(url, session: session)
        return SteamStoreCatalog(
            specials: response.specials.items.map(\.storeItem),
            topSellers: response.topSellers.items.map(\.storeItem),
            newReleases: response.newReleases.items.map(\.storeItem)
        )
    }

    public static func search(_ term: String, session: URLSession = .shared) async throws -> [SteamStoreItem] {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [
            .init(name: "term", value: term),
            .init(name: "l", value: AppLanguage.steamLanguage),
            .init(name: "cc", value: "CN"),
        ]
        let response: SearchResponse = try await request(components.url!, session: session)
        return response.items.map { item in
            SteamStoreItem(
                id: item.id,
                name: item.name,
                imageURL: item.tinyImage.flatMap(URL.init(string:)),
                originalPrice: item.price?.initial,
                finalPrice: item.price?.final,
                currency: item.price?.currency,
                discountPercent: item.price.map { price in
                    guard price.initial > 0 else { return 0 }
                    return max(0, Int(((1 - Double(price.final) / Double(price.initial)) * 100).rounded()))
                } ?? 0
            )
        }
    }

    private static func request<T: Decodable>(_ url: URL, session: URLSession) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacGamingUncle/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct FeaturedResponse: Decodable {
        let specials: Category
        let topSellers: Category
        let newReleases: Category

        enum CodingKeys: String, CodingKey {
            case specials
            case topSellers = "top_sellers"
            case newReleases = "new_releases"
        }
    }

    private struct Category: Decodable { let items: [FeaturedItem] }

    private struct FeaturedItem: Decodable {
        let id: UInt64
        let name: String
        let discountPercent: Int?
        let originalPrice: Int?
        let finalPrice: Int?
        let currency: String?
        let largeCapsuleImage: String?
        let headerImage: String?

        enum CodingKeys: String, CodingKey {
            case id, name, currency
            case discountPercent = "discount_percent"
            case originalPrice = "original_price"
            case finalPrice = "final_price"
            case largeCapsuleImage = "large_capsule_image"
            case headerImage = "header_image"
        }

        var storeItem: SteamStoreItem {
            SteamStoreItem(
                id: id,
                name: name,
                imageURL: (largeCapsuleImage ?? headerImage).flatMap(URL.init(string:)),
                originalPrice: originalPrice,
                finalPrice: finalPrice,
                currency: currency,
                discountPercent: discountPercent ?? 0
            )
        }
    }

    private struct SearchResponse: Decodable { let items: [SearchItem] }
    private struct SearchItem: Decodable {
        let id: UInt64
        let name: String
        let tinyImage: String?
        let price: SearchPrice?

        enum CodingKeys: String, CodingKey {
            case id, name, price
            case tinyImage = "tiny_image"
        }
    }
    private struct SearchPrice: Decodable {
        let currency: String
        let initial: Int
        let final: Int
    }
}

public enum SteamNativeStoreCache {
    public static func load(from url: URL) -> SteamStoreCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamStoreCatalog.self, from: data)
    }

    public static func save(_ catalog: SteamStoreCatalog, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: url, options: .atomic)
    }
}
