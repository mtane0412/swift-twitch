// BadgeStoreTests.swift
// BadgeStore の URL解決ロジックテスト

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// HelixAPIClientProtocol のテスト用モック
struct MockHelixAPIClient: HelixAPIClientProtocol {
    /// true の場合、URLError.userAuthenticationRequired を throw する（未ログイン状態のシミュレート）
    var shouldThrowAuthError: Bool = false

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        // テストでネットワークを呼ばないよう、デフォルトはサーバーエラーを throw する
        throw URLError(.badServerResponse)
    }
}

@Suite("BadgeStoreTests")
struct BadgeStoreTests {

    // MARK: - URL解決ロジック（BadgeStore のファクトリメソッドを直接テスト）

    @Test("グローバルバッジのURLを正しく解決できる")
    func testResolveGlobalBadgeURL() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())

        // グローバルバッジ定義を直接設定（テスト用）
        let broadcasterURL = "https://static-cdn.jtvnw.net/badges/v1/abc/2"
        await store.setGlobalBadges([
            "broadcaster": ["1": broadcasterURL]
        ])

        let badge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url?.absoluteString == broadcasterURL)
    }

    @Test("チャンネルバッジがグローバルバッジより優先される")
    func testChannelBadgeOverridesGlobal() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())

        let globalURL = "https://static-cdn.jtvnw.net/badges/v1/global-sub/2"
        let channelURL = "https://static-cdn.jtvnw.net/badges/v1/channel-sub/2"

        await store.setGlobalBadges([
            "subscriber": ["0": globalURL]
        ])
        await store.setChannelBadges([
            "subscriber": ["0": channelURL]
        ])

        let badge = Badge(name: "subscriber", version: "0")
        let url = await store.imageURL(for: badge)
        #expect(url?.absoluteString == channelURL)
    }

    @Test("チャンネルバッジにないバッジはグローバルにフォールバックする")
    func testFallbackToGlobalWhenNotInChannel() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())

        let globalURL = "https://static-cdn.jtvnw.net/badges/v1/broadcaster/2"
        await store.setGlobalBadges([
            "broadcaster": ["1": globalURL]
        ])
        await store.setChannelBadges([
            "subscriber": ["0": "https://example.com/sub.png"]
        ])

        let badge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url?.absoluteString == globalURL)
    }

    @Test("存在しないバッジ名の場合はnilを返す")
    func testUnknownBadgeReturnsNil() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        await store.setGlobalBadges([
            "broadcaster": ["1": "https://example.com/badge.png"]
        ])

        let badge = Badge(name: "未登録バッジ", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("存在しないバッジバージョンの場合はnilを返す")
    func testUnknownVersionReturnsNil() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        await store.setGlobalBadges([
            "subscriber": ["0": "https://example.com/sub.png"]
        ])

        let badge = Badge(name: "subscriber", version: "99999")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("Helixバッジセットからショートマッピングを構築できる")
    func testBuildMappingFromHelixBadgeSets() {
        // broadcaster バッジセット（バージョン 1）
        let broadcasterSet = HelixBadgeSet(
            setId: "broadcaster",
            versions: [
                HelixBadgeVersion(
                    id: "1",
                    imageUrl1x: "https://example.com/broadcaster/1",
                    imageUrl2x: "https://example.com/broadcaster/2",
                    imageUrl4x: "https://example.com/broadcaster/3",
                    title: "Broadcaster",
                    description: "放送者"
                )
            ]
        )
        // subscriber バッジセット（バージョン 0 と 3）
        let subscriberSet = HelixBadgeSet(
            setId: "subscriber",
            versions: [
                HelixBadgeVersion(
                    id: "0",
                    imageUrl1x: "https://example.com/sub0/1",
                    imageUrl2x: "https://example.com/sub0/2",
                    imageUrl4x: "https://example.com/sub0/3",
                    title: "サブスクライバー",
                    description: "初月サブスクライブ"
                ),
                HelixBadgeVersion(
                    id: "3",
                    imageUrl1x: "https://example.com/sub3/1",
                    imageUrl2x: "https://example.com/sub3/2",
                    imageUrl4x: "https://example.com/sub3/3",
                    title: "3ヶ月サブスクライバー",
                    description: "3ヶ月間サブスクライブ"
                )
            ]
        )

        let mapping = BadgeStore.buildMapping(from: [broadcasterSet, subscriberSet])

        // broadcaster バッジの 2x 画像 URL が正しくマッピングされること
        #expect(mapping["broadcaster"]?["1"] == "https://example.com/broadcaster/2")
        // subscriber バッジのバージョン 0 の 2x 画像 URL が正しくマッピングされること
        #expect(mapping["subscriber"]?["0"] == "https://example.com/sub0/2")
        // subscriber バッジのバージョン 3 の 2x 画像 URL が正しくマッピングされること
        #expect(mapping["subscriber"]?["3"] == "https://example.com/sub3/2")
    }

    @Test("空のバッジセット配列からは空マッピングを構築する")
    func testBuildMappingFromEmptyBadgeSets() {
        let mapping = BadgeStore.buildMapping(from: [])
        #expect(mapping.isEmpty)
    }

    @Test("バッジ定義が未設定の場合はnilを返す")
    func testImageURLReturnsNilWhenNoBadgesSet() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        // setGlobalBadges/setChannelBadges を呼ばない状態
        let badge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("空のバッジ名でも安全にnilを返す")
    func testEmptyBadgeNameReturnsNil() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        await store.setGlobalBadges(["broadcaster": ["1": "https://example.com/badge.png"]])
        let emptyNameBadge = Badge(name: "", version: "1")
        let url = await store.imageURL(for: emptyNameBadge)
        #expect(url == nil)
    }

    @Test("空のバージョンでも安全にnilを返す")
    func testEmptyVersionReturnsNil() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        await store.setGlobalBadges(["broadcaster": ["1": "https://example.com/badge.png"]])
        let emptyVersionBadge = Badge(name: "broadcaster", version: "")
        let url = await store.imageURL(for: emptyVersionBadge)
        #expect(url == nil)
    }

    @Test("並行アクセスしても安全に動作する")
    func testConcurrentAccessIsSafe() async {
        let store = BadgeStore(apiClient: MockHelixAPIClient())
        // 複数タスクが並行して読み書きしてもクラッシュしないことを確認
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await store.setGlobalBadges(
                        ["broadcaster": ["1": "https://example.com/badge-\(i).png"]]
                    )
                }
                group.addTask {
                    _ = await store.imageURL(for: Badge(name: "broadcaster", version: "1"))
                }
            }
        }
        // 全タスク完了後に結果が一貫していることを確認
        let url = await store.imageURL(for: Badge(name: "broadcaster", version: "1"))
        #expect(url != nil)
    }

    @Test("トークンが未設定の場合はグローバルバッジフェッチをスキップする")
    func testFetchGlobalBadgesSkippedWhenNoToken() async {
        // shouldThrowAuthError: true = 未ログイン状態をシミュレート
        let store = BadgeStore(apiClient: MockHelixAPIClient(shouldThrowAuthError: true))

        await store.fetchGlobalBadges()

        // トークン未取得の場合はバッジが空のままで、次回接続時に再取得できること
        let badge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("トークンが未設定の場合はチャンネルバッジフェッチをスキップする")
    func testFetchChannelBadgesSkippedWhenNoToken() async {
        // shouldThrowAuthError: true = 未ログイン状態をシミュレート
        let store = BadgeStore(apiClient: MockHelixAPIClient(shouldThrowAuthError: true))

        await store.fetchChannelBadges(channelId: "12345678")

        // トークン未取得の場合はバッジが空のままであること
        let badge = Badge(name: "subscriber", version: "0")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }
}
