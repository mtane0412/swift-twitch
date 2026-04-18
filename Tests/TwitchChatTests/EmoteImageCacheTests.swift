// EmoteImageCacheTests.swift
// EmoteImageCache の単体テスト
// URL 生成ロジックとエモート表示サイズを検証する（画像ダウンロードは外部依存のためテスト対象外）

import Foundation
import Testing
@testable import TwitchChat

/// EmoteImageCache のテストスイート
@Suite("EmoteImageCache テスト")
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
}
