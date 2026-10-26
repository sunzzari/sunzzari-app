import Foundation
import Security

/// One bookmarked recipe from Cathy's recipe app. Titles only on Home, by
/// Elisa's instruction (2026-10-25: "i dont need to see images in the sunzzari
/// app"), so nothing else from the feed record is decoded.
struct RecipeBookmark: Identifiable, Equatable, Decodable {
    let id: String
    let title: String
    let href: URL
}

/// Reads the recipe app's bookmarks feed (`GET /api/integrations/bookmarks`).
///
/// The feed key is shared by every bookmarks client and replacing it on the
/// server revokes all of them at once. It is pasted on each phone and kept in
/// the Keychain, never in the bundle or Secrets.swift, so a rotation needs
/// no app release.
final class RecipeBookmarksService: @unchecked Sendable {
    static let shared = RecipeBookmarksService()
    private init() {}

    enum FeedError: Error {
        case notConnected
        case keyRejected
        case server(Int)
        case unreadable
    }

    private struct Page: Decodable {
        let recipes: [RecipeBookmark]
        let nextCursor: String?
    }

    // MARK: - Key (Keychain)

    private let keychainService = "com.sunzzari.recipeBookmarks"
    private let keychainAccount = "feedKey"

    var hasKey: Bool { storedKey() != nil }

    func storedKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    func saveKey(_ key: String) -> Bool {
        deleteKey()
        let attrs: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String:      Data(key.utf8)
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Fetch

    /// Every bookmark, following the feed's cursor. `key` overrides the stored
    /// one so Connect can test a pasted key before saving it.
    func fetchBookmarks(key: String? = nil) async throws -> [RecipeBookmark] {
        guard let key = key ?? storedKey() else { throw FeedError.notConnected }

        var all: [RecipeBookmark] = []
        var cursor: String? = nil
        // The feed caps a page at 50; 20 pages is far past any real bookmark
        // count and stops a server bug from looping forever.
        for _ in 0..<20 {
            var comps = URLComponents(url: Constants.Recipes.bookmarksFeedURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "limit", value: "50")]
                + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { throw FeedError.keyRejected }
            guard status == 200 else { throw FeedError.server(status) }
            guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw FeedError.unreadable }

            all += page.recipes
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        // The feed orders by ID and has no bookmarked-at date, so sort by title.
        return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
