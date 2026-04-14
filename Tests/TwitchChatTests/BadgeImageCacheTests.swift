// BadgeImageCacheTests.swift
// BadgeImageCache のキャッシュキーと表示サイズのテスト

import Testing
import Foundation
@testable import TwitchChat

@Suite("BadgeImageCacheTests")
struct BadgeImageCacheTests {

    @Test("バッジの表示サイズが18ptである")
    func testBadgeDisplaySize() {
        #expect(BadgeImageCache.badgeDisplaySize == 18.0)
    }

    @Test("キャッシュキーが badgeName/version の形式である")
    func testCacheKey() {
        let badge = Badge(name: "subscriber", version: "12")
        let key = BadgeImageCache.cacheKey(for: badge)
        #expect(key == "subscriber/12")
    }

    @Test("broadcaster バッジのキャッシュキーが正しい")
    func testBroadcasterCacheKey() {
        let badge = Badge(name: "broadcaster", version: "1")
        let key = BadgeImageCache.cacheKey(for: badge)
        #expect(key == "broadcaster/1")
    }

    @Test("バッジ名にスラッシュが含まれない通常バッジのキーが正しい")
    func testVipCacheKey() {
        let badge = Badge(name: "vip", version: "1")
        let key = BadgeImageCache.cacheKey(for: badge)
        #expect(key == "vip/1")
    }
}
