// EmoteImageCacheTests.swift
// EmoteImageCache の単体テスト
// URL 生成ロジック・表示サイズ・L2 キャッシュ統合を検証する

import AppKit
import Foundation
import Testing
@testable import TwitchChat

/// EmoteImageCache のテストスイート
///
/// シングルトン EmoteImageCache.shared の状態を共有するため、テストを順次実行する。
@Suite("EmoteImageCache テスト", .serialized)
struct EmoteImageCacheTests {

    // MARK: - スタティック URL 生成

    @Test("デフォルト（スタティック）で正しいエモート URL を生成できる")
    func デフォルトでスタティックエモートURLを生成できる() {
        // 前提: エモートID "25"（Kappa）でデフォルト（スタティック）URL
        let url = EmoteImageCache.emoteURL(emoteId: "25")
        // 検証: Twitch CDN のスタティック URL が生成される
        #expect(url.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/2.0")
    }

    @Test("スタティック・スケール 1.0 で正しいエモート URL を生成できる")
    func スタティックスケール1でエモートURLを生成できる() {
        // 前提: エモートID "1902"（LUL）でスタティック、スケール 1.0
        let url = EmoteImageCache.emoteURL(emoteId: "1902", scale: "1.0")
        // 検証: 指定スケールのスタティック URL が生成される
        #expect(url.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/1902/default/dark/1.0")
    }

    @Test("スタティック・スケール 3.0 で正しいエモート URL を生成できる")
    func スタティックスケール3でエモートURLを生成できる() {
        // 前提: 高解像度スケール 3.0 の指定
        let url = EmoteImageCache.emoteURL(emoteId: "305954156", scale: "3.0")
        // 検証: 3.0 スケールのスタティック URL が生成される
        #expect(url.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/305954156/default/dark/3.0")
    }

    // MARK: - アニメーション URL 生成

    @Test("アニメーション URL を生成できる")
    func アニメーションURLを生成できる() {
        // 前提: エモートID "25" のアニメーション版
        let url = EmoteImageCache.emoteURL(emoteId: "25", type: "animated")
        // 検証: /animated/ パスの URL が生成される
        #expect(url.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/animated/dark/2.0")
    }

    @Test("アニメーション・スケール 1.0 で URL を生成できる")
    func アニメーションスケール1でURLを生成できる() {
        // 前提: アニメーション版、スケール 1.0
        let url = EmoteImageCache.emoteURL(emoteId: "1902", type: "animated", scale: "1.0")
        // 検証: /animated/ パスの 1.0 スケール URL が生成される
        #expect(url.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/1902/animated/dark/1.0")
    }

    // MARK: - 表示サイズ

    @Test("エモート表示サイズが 20pt である")
    func エモート表示サイズが20ptである() {
        // 前提: 13pt フォントの行高に合わせてエモート表示サイズは 20pt と定義されている
        // 検証: 定数が 20pt であることを確認（リグレッション防止）
        #expect(EmoteImageCache.emoteDisplaySize == 20)
    }

    // MARK: - 同期キャッシュ読み取り

    @Test("キャッシュ未登録のエモートは cachedImage(for:) で nil を返す")
    func cachedImageReturnsNilForUncachedEmote() {
        // 前提: キャッシュに登録されていないエモートID
        // 検証: nil が返る（ダウンロードは発生しない）
        let result = EmoteImageCache.shared.cachedImage(for: "未登録エモートID_テスト用_\(UUID())")
        #expect(result == nil)
    }

    // MARK: - GIF 生データキャッシュ

    @Test("キャッシュ未登録のエモートは gifData(for:) で nil を返す")
    func gifDataReturnsNilForUncachedEmote() {
        // 前提: キャッシュに登録されていないエモートID
        // 検証: nil が返る（ダウンロードは発生しない）
        let result = EmoteImageCache.shared.gifData(for: "未登録GIFエモートID_テスト用_\(UUID())")
        #expect(result == nil)
    }

    @Test("storeForTesting で登録した GIF データが gifData(for:) で取得できる")
    func gifDataReturnsCachedData() {
        // 前提: テスト用エモートID と GIF データを直接キャッシュに登録する
        let emoteId = "テスト用GIFエモートID_\(UUID())"
        let testGIFData = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) // "GIF89a" バイト列
        EmoteImageCache.shared.storeForTesting(gifData: testGIFData, for: emoteId)

        // 実行: gifData(for:) で取得する
        let result = EmoteImageCache.shared.gifData(for: emoteId)

        // 検証: 登録したデータが取得できる
        #expect(result == testGIFData)
    }

    // MARK: - L2 キャッシュ統合

    @Test("L1 ヒット時は loadImageData を呼ばない")
    func L1ヒット時はloadImageDataを呼ばない() async {
        // 前提: テスト用エモートID で L1 に画像を直接登録する
        let emoteId = "エモートID_L1テスト_\(UUID())"
        defer { EmoteImageCache.shared.clearForTesting() }

        let mock = MockPersistenceService()
        EmoteImageCache.shared.attachPersistence(mock)

        // テスト用の画像を L1 に直接登録する（L1 ヒットを確実にするため）
        let testImage = makeTestNSImage()
        EmoteImageCache.shared.storeImageForTesting(testImage, for: emoteId)

        // 実行: image(for:) を呼ぶ（L1 ヒットのはず）
        let result = await EmoteImageCache.shared.image(for: emoteId)

        // 検証: 画像が返った
        #expect(result != nil)
        // 検証: L2 は参照されなかった
        let loadCount = await mock.loadImageDataCallCount
        #expect(loadCount == 0)
    }

    @Test("L2 に有効な画像データがある場合は HTTP なしで画像を返す")
    func L2ヒット時はHTTPなしで画像を返す() async {
        // 前提: テスト用エモートID の static キーを L2（モック）に事前投入する
        let emoteId = "エモートID_L2テスト_\(UUID())"
        defer { EmoteImageCache.shared.clearForTesting() }

        let mock = MockPersistenceService()
        guard let pngData = makeMiniPNGData() else {
            Issue.record("テスト用 PNG データ生成失敗")
            return
        }
        // static キーを L2 に投入（animated は投入しない）
        let staticKey = ImageCacheKey(kind: .emote, identifier: "\(emoteId):2.0:static")
        await mock.seedImageData(pngData, key: staticKey)
        EmoteImageCache.shared.attachPersistence(mock)

        // 実行: image(for:) を呼ぶ（L2 ヒットで返るはず）
        let result = await EmoteImageCache.shared.image(for: emoteId)

        // 検証: 画像が返った（L2 から復元）
        #expect(result != nil)
        // 検証: loadImageData が呼ばれた（animated: 1回 miss + static: 1回 hit）
        let loadCount = await mock.loadImageDataCallCount
        #expect(loadCount == 2)
        // 検証: L2 保存は呼ばれなかった（HTTP は不発火）
        let saveCount = await mock.saveImageDataCallCount
        #expect(saveCount == 0)
    }

    // MARK: - テスト用ヘルパー

    /// テスト用の最小 NSImage を生成する（L1 直接登録用）
    private func makeTestNSImage() -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20))
    }

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
