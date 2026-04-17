// FollowedChannelStoreTests.swift
// FollowedChannelStore の単体テスト
// MockAPIClient を使ってネットワーク通信なしでストア振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// FollowedChannelStore / チャンネル検索用の Helix API クライアントモック
///
/// `pages` に複数ページ分のデータをセットすることでページネーションのテストに対応する
actor MockFollowedChannelAPIClient: HelixAPIClientProtocol {
    /// 返すチャンネルデータのページ一覧（呼び出し順に返す）
    var pages: [[HelixFollowedChannelData]] = [[]]
    /// チャンネル検索結果
    var searchResultsToReturn: [HelixSearchChannelData] = []
    /// true の場合、URLError.userAuthenticationRequired を throw する
    var shouldThrowAuthError: Bool = false
    /// get() が呼ばれた回数（呼び出し検証用）
    private(set) var callCount = 0

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        if T.self == HelixFollowedChannelsResponse.self {
            // callCount に対応するページを返し、最後のページ以外はカーソルを付与する
            let pageIndex = min(callCount, pages.count - 1)
            let pageData = pages[pageIndex]
            let hasMorePages = callCount < pages.count - 1
            let cursor = hasMorePages ? "cursor_page_\(callCount + 1)" : nil
            callCount += 1
            let response = HelixFollowedChannelsResponse(
                data: pageData,
                pagination: HelixPaginationCursor(cursor: cursor)
            )
            return response as! T  // swiftlint:disable:this force_cast
        }
        if T.self == HelixSearchChannelsResponse.self {
            callCount += 1
            let response = HelixSearchChannelsResponse(data: searchResultsToReturn)
            return response as! T  // swiftlint:disable:this force_cast
        }
        throw URLError(.badServerResponse)
    }
}

// MARK: - MockFollowedChannelAPIClient ヘルパー

extension MockFollowedChannelAPIClient {
    func setPages(_ pages: [[HelixFollowedChannelData]]) {
        self.pages = pages
    }
    func setSearchResults(_ results: [HelixSearchChannelData]) {
        self.searchResultsToReturn = results
    }
    func setAuthError(_ value: Bool) {
        self.shouldThrowAuthError = value
    }
}

// MARK: - テストデータファクトリ

/// テスト用フォロー済みチャンネルデータを生成するヘルパー
private func makeHelixChannel(
    broadcasterId: String = "111111",
    broadcasterLogin: String = "テストチャンネル",
    broadcasterName: String = "テストチャンネル表示名"
) -> HelixFollowedChannelData {
    HelixFollowedChannelData(
        broadcasterId: broadcasterId,
        broadcasterLogin: broadcasterLogin,
        broadcasterName: broadcasterName
    )
}

/// テスト用チャンネル検索結果データを生成するヘルパー
private func makeHelixSearchChannel(
    id: String = "111111",
    broadcasterLogin: String = "検索チャンネル",
    displayName: String = "検索チャンネル表示名",
    gameName: String = "マインクラフト",
    isLive: Bool = true
) -> HelixSearchChannelData {
    HelixSearchChannelData(
        id: id,
        broadcasterLogin: broadcasterLogin,
        displayName: displayName,
        gameName: gameName,
        isLive: isLive
    )
}

// MARK: - FollowedChannelStore テスト

@Suite("FollowedChannelStore テスト")
@MainActor
struct FollowedChannelStoreTests {

    // MARK: - fetchAll: 基本動作

    @Test("fetchAll: チャンネル一覧を取得してキャッシュする")
    func fetchAllStoresChannels() async {
        // 前提: 2件のチャンネルを返すモック
        let apiClient = MockFollowedChannelAPIClient()
        await apiClient.setPages([[
            makeHelixChannel(broadcasterId: "1", broadcasterLogin: "alice", broadcasterName: "Alice"),
            makeHelixChannel(broadcasterId: "2", broadcasterLogin: "bob", broadcasterName: "Bob")
        ]])
        let store = FollowedChannelStore(apiClient: apiClient, userId: "自分のユーザーID")

        await store.fetchAll()

        // 検証: 2件がキャッシュされている
        #expect(store.channels.count == 2)
        #expect(store.channels[0].broadcasterLogin == "alice")
        #expect(store.channels[1].broadcasterLogin == "bob")
    }

    @Test("fetchAll: userId が nil の場合、取得をスキップする")
    func fetchAllSkipsWhenUserIdIsNil() async {
        let apiClient = MockFollowedChannelAPIClient()
        let store = FollowedChannelStore(apiClient: apiClient, userId: nil)

        await store.fetchAll()

        // 検証: API が呼ばれず channels は空のまま
        let count = await apiClient.callCount
        #expect(count == 0)
        #expect(store.channels.isEmpty)
    }

    @Test("fetchAll: 認証エラーの場合、サイレントにスキップする")
    func fetchAllSilentlySkipsOnAuthError() async {
        let apiClient = MockFollowedChannelAPIClient()
        await apiClient.setAuthError(true)
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")

        await store.fetchAll()

        // 検証: エラーが表面に出ず channels は空のまま
        #expect(store.channels.isEmpty)
    }

    // MARK: - fetchAll: ページネーション

    @Test("fetchAll: ページネーションで複数ページのチャンネルを全件取得する")
    func fetchAllHandlesPagination() async {
        // 前提: 2ページに分かれたデータ（各2件）
        let apiClient = MockFollowedChannelAPIClient()
        await apiClient.setPages([
            [makeHelixChannel(broadcasterId: "1", broadcasterLogin: "alice"),
             makeHelixChannel(broadcasterId: "2", broadcasterLogin: "bob")],
            [makeHelixChannel(broadcasterId: "3", broadcasterLogin: "charlie"),
             makeHelixChannel(broadcasterId: "4", broadcasterLogin: "diana")]
        ])
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")

        await store.fetchAll()

        // 検証: 2ページ分の合計4件が取得される
        #expect(store.channels.count == 4)
        let apiCallCount = await apiClient.callCount
        #expect(apiCallCount == 2)
    }

    // MARK: - searchChannels

    @Test("searchChannels: クエリを渡すと検索結果を返す")
    func searchChannelsReturnsResults() async {
        let apiClient = MockFollowedChannelAPIClient()
        await apiClient.setSearchResults([
            makeHelixSearchChannel(broadcasterLogin: "ninja", displayName: "Ninja", gameName: "Fortnite")
        ])
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")

        let results = await store.searchChannels(query: "ninja")

        #expect(results.count == 1)
        #expect(results[0].broadcasterLogin == "ninja")
        #expect(results[0].gameName == "Fortnite")
    }

    @Test("searchChannels: 空文字列のクエリは API を呼ばずに空配列を返す")
    func searchChannelsSkipsEmptyQuery() async {
        let apiClient = MockFollowedChannelAPIClient()
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")

        let results = await store.searchChannels(query: "")

        let apiCallCount = await apiClient.callCount
        #expect(apiCallCount == 0)
        #expect(results.isEmpty)
    }

    @Test("searchChannels: スペースのみのクエリは API を呼ばずに空配列を返す")
    func searchChannelsSkipsWhitespaceOnlyQuery() async {
        let apiClient = MockFollowedChannelAPIClient()
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")

        let results = await store.searchChannels(query: "   ")

        let apiCallCount = await apiClient.callCount
        #expect(apiCallCount == 0)
        #expect(results.isEmpty)
    }

    // MARK: - clear

    @Test("clear: チャンネル一覧を空にする")
    func clearEmptiesChannels() async {
        let apiClient = MockFollowedChannelAPIClient()
        await apiClient.setPages([[
            makeHelixChannel(broadcasterId: "1", broadcasterLogin: "alice")
        ]])
        let store = FollowedChannelStore(apiClient: apiClient, userId: "ユーザーID")
        await store.fetchAll()
        #expect(!store.channels.isEmpty)

        // 操作: clear を呼ぶ
        store.clear()

        #expect(store.channels.isEmpty)
    }
}
