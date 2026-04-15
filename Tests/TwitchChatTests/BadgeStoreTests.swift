// BadgeStoreTests.swift
// BadgeStore の URL解決ロジックテスト

import Testing
import Foundation
@testable import TwitchChat

@Suite("BadgeStoreTests")
struct BadgeStoreTests {

    // MARK: - URL解決ロジック（BadgeStore のファクトリメソッドを直接テスト）

    @Test("グローバルバッジのURLを正しく解決できる")
    func testResolveGlobalBadgeURL() async {
        let store = BadgeStore()

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
        let store = BadgeStore()

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
        let store = BadgeStore()

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
        let store = BadgeStore()
        await store.setGlobalBadges([
            "broadcaster": ["1": "https://example.com/badge.png"]
        ])

        let badge = Badge(name: "unknown-badge", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("存在しないバッジバージョンの場合はnilを返す")
    func testUnknownVersionReturnsNil() async {
        let store = BadgeStore()
        await store.setGlobalBadges([
            "subscriber": ["0": "https://example.com/sub.png"]
        ])

        let badge = Badge(name: "subscriber", version: "99999")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("GQLバッジレスポンスからURLマッピングを構築できる")
    func testBuildMappingFromGQLResponse() {
        let items = [
            GQLBadgeItem(id: "YnJvYWRjYXN0ZXI7MTs=", title: "Broadcaster",
                         imageURL: "https://example.com/broadcaster.png"),
            GQLBadgeItem(id: "bW9kZXJhdG9yOzE7", title: "Moderator",
                         imageURL: "https://example.com/moderator.png"),
            // 不正なIDは無視される
            GQLBadgeItem(id: "invalid!!!", title: "Invalid",
                         imageURL: "https://example.com/invalid.png")
        ]

        let mapping = BadgeStore.buildMapping(from: items)

        #expect(mapping["broadcaster"]?["1"] == "https://example.com/broadcaster.png")
        #expect(mapping["moderator"]?["1"] == "https://example.com/moderator.png")
        #expect(mapping["invalid"] == nil)
    }

    @Test("バッジ定義が未設定の場合はnilを返す")
    func testImageURLReturnsNilWhenNoBadgesSet() async {
        let store = BadgeStore()
        // setGlobalBadges/setChannelBadges を呼ばない状態
        let badge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: badge)
        #expect(url == nil)
    }

    @Test("空のバッジ名でも安全にnilを返す")
    func testEmptyBadgeNameReturnsNil() async {
        let store = BadgeStore()
        await store.setGlobalBadges(["broadcaster": ["1": "https://example.com/badge.png"]])
        let emptyNameBadge = Badge(name: "", version: "1")
        let url = await store.imageURL(for: emptyNameBadge)
        #expect(url == nil)
    }

    @Test("空のバージョンでも安全にnilを返す")
    func testEmptyVersionReturnsNil() async {
        let store = BadgeStore()
        await store.setGlobalBadges(["broadcaster": ["1": "https://example.com/badge.png"]])
        let emptyVersionBadge = Badge(name: "broadcaster", version: "")
        let url = await store.imageURL(for: emptyVersionBadge)
        #expect(url == nil)
    }

    @Test("並行アクセスしても安全に動作する")
    func testConcurrentAccessIsSafe() async {
        let store = BadgeStore()
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
}
