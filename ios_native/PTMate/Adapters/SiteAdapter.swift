import Foundation

protocol SiteAdapter {
    var siteConfig: SiteConfig { get }

    func initialize(_ config: SiteConfig) async throws

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail

    func fetchComments(
        _ id: String,
        pageNumber: Int,
        pageSize: Int
    ) async throws -> TorrentCommentList

    func genDlToken(id: String, url: String?) async throws -> String

    func queryHistory(tids: [String]) async throws -> [String: Any]

    func toggleCollection(torrentId: String, make: Bool) async throws

    func testConnection() async throws -> Bool

    func getSearchCategories() async throws -> [SearchCategoryConfig]
}

extension SiteAdapter {
    func fetchMemberProfile(apiKey: String? = nil) async throws -> MemberProfile {
        try await fetchMemberProfile(apiKey: apiKey)
    }

    func searchTorrents(
        keyword: String? = nil,
        pageNumber: Int = 1,
        pageSize: Int = 30,
        onlyFav: Int? = nil,
        additionalParams: [String: Any]? = nil
    ) async throws -> TorrentSearchResult {
        try await searchTorrents(
            keyword: keyword,
            pageNumber: pageNumber,
            pageSize: pageSize,
            onlyFav: onlyFav,
            additionalParams: additionalParams
        )
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String? = nil,
        detailUrl: String? = nil
    ) async throws -> TorrentDetail {
        try await fetchTorrentDetail(id, description: description, detailUrl: detailUrl)
    }

    func fetchComments(
        _ id: String,
        pageNumber: Int = 1,
        pageSize: Int = 20
    ) async throws -> TorrentCommentList {
        try await fetchComments(id, pageNumber: pageNumber, pageSize: pageSize)
    }

    func genDlToken(id: String, url: String? = nil) async throws -> String {
        try await genDlToken(id: id, url: url)
    }
}
