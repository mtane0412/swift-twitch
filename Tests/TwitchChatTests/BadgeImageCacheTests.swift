// BadgeImageCacheTests.swift
// BadgeImageCache のキャッシュキー・表示サイズ・L2 キャッシュ統合のテスト

import AppKit
import Foundation
import Testing
@testable import TwitchChat

/// シングルトン BadgeImageCache.shared の状態を共有するため、テストを順次実行する。
@Suite("BadgeImageCacheTests", .serialized)
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

    // MARK: - L2 キャッシュ統合

    @Test("L2 に有効な画像データがある場合は BadgeStore・HTTP なしで画像を返す")
    func L2ヒット時はHTTPなしでバッジ画像を返す() async {
        // 前提: サブスクライバーバッジの L2 データをモックに投入する
        let badge = Badge(name: "subscriber", version: "12")
        let mock = MockPersistenceService()
        guard let pngData = makeMiniPNGData() else {
            Issue.record("テスト用 PNG データ生成失敗")
            return
        }
        let l2Key = ImageCacheKey(kind: .badge, identifier: "subscriber:12")
        await mock.seedImageData(pngData, key: l2Key)

        BadgeImageCache.shared.attachPersistence(mock)
        defer { BadgeImageCache.shared.attachPersistenceForTesting(nil) }

        // 前提: BadgeStore のダミー（L2 ヒット時は imageURL は呼ばれない）
        let dummyStore = BadgeStore(apiClient: MockHelixAPIClient())

        // 実行: image(for:store:) を呼ぶ（L2 ヒットで返るはず）
        let result = await BadgeImageCache.shared.image(for: badge, store: dummyStore)

        // 検証: 画像が返った（L2 から復元）
        #expect(result != nil)
        // 検証: loadImageData が1回呼ばれた
        let loadCount = await mock.loadImageDataCallCount
        #expect(loadCount == 1)
        // 検証: L2 保存は呼ばれなかった（HTTP は不発火）
        let saveCount = await mock.saveImageDataCallCount
        #expect(saveCount == 0)
    }

    // MARK: - テスト用ヘルパー

    /// CoreGraphics で 2×2 ピクセルの PNG データを生成する（L2 シード用）
    private func makeMiniPNGData() -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
