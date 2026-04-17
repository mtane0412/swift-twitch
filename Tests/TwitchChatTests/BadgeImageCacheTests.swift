// BadgeImageCacheTests.swift
// BadgeImageCache のキャッシュキーと表示サイズのテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("BadgeImageCacheTests")
struct BadgeImageCacheTests {

    @Test("バッジの表示サイズが18ptである")
    func testBadgeDisplaySize() {
        #expect(BadgeImageCache.badgeDisplaySize == 18.0)
    }

    @Test("キャッシュキーが badgeName/version の形式である", arguments: [
        (Badge(name: "subscriber", version: "12"), "subscriber/12"),
        (Badge(name: "broadcaster", version: "1"), "broadcaster/1"),
        (Badge(name: "vip", version: "1"), "vip/1"),
        (Badge(name: "moderator", version: "1"), "moderator/1"),
        (Badge(name: "partner", version: "1"), "partner/1")
    ])
    func testCacheKey(badge: Badge, expectedKey: String) {
        let key = BadgeImageCache.cacheKey(for: badge)
        #expect(key == expectedKey)
    }
}
