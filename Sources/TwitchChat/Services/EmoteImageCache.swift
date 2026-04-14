// EmoteImageCache.swift
// Twitch エモート画像のキャッシュと非同期読み込みを管理するサービス
// NSCache ベースのメモリキャッシュで同一エモートの再ダウンロードを防ぐ
// アニメーション版（GIF）を優先的に取得し、未対応エモートはスタティック版にフォールバックする

import AppKit
import Foundation

/// Twitch エモート画像のキャッシュ管理クラス
///
/// - アニメーション版 URL（`/animated/`）を先に試み、失敗時はスタティック版（`/default/`）にフォールバック
/// - NSCache によるメモリキャッシュ（メモリプレッシャー時に自動解放）
/// - NSImage.size を `emoteDisplaySize` に設定してテキスト行高と一致させる
/// - シングルトンで全 View 間でキャッシュを共有
final class EmoteImageCache: @unchecked Sendable {

    /// シングルトンインスタンス
    static let shared = EmoteImageCache()

    /// エモートの表示サイズ（ポイント）
    ///
    /// 13pt フォントの行高（~18pt）に合わせた値。
    /// NSImage.size および AnimatedEmoteView のフレームサイズに使用する。
    static let emoteDisplaySize: CGFloat = 20

    /// エモート画像のメモリキャッシュ（キー: エモートID）
    private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        // よく使われるエモートは数十種類なので 500 件で十分
        c.countLimit = 500
        return c
    }()

    /// アニメーション版が存在するエモートIDの集合
    private var animatedEmoteIds: Set<String> = []

    /// animatedEmoteIds へのアクセスを保護するロック
    private let lock = NSLock()

    private init() {}

    // MARK: - 画像取得

    /// エモートIDから画像を取得する（キャッシュ優先）
    ///
    /// キャッシュにある場合は即時返却。ない場合は以下の順で取得する:
    /// 1. アニメーション版 URL（`/animated/`）を試みる
    /// 2. 失敗した場合はスタティック版 URL（`/default/`）にフォールバック
    ///
    /// - Parameter emoteId: Twitch エモートID（例: "25"）
    /// - Returns: ダウンロード済みの NSImage（`emoteDisplaySize` にリサイズ済み）。取得失敗時は nil
    func image(for emoteId: String) async -> NSImage? {
        let cacheKey = emoteId as NSString

        // キャッシュヒット: 即時返却
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // アニメーション版を先に試みる
        if let image = await download(emoteId: emoteId, type: "animated") {
            store(image, for: emoteId, isAnimated: true)
            return image
        }

        // スタティック版にフォールバック
        if let image = await download(emoteId: emoteId, type: "default") {
            store(image, for: emoteId, isAnimated: false)
            return image
        }

        return nil
    }

    /// エモートがアニメーション版かどうかを返す
    ///
    /// - Parameter emoteId: Twitch エモートID
    /// - Returns: アニメーション版が取得済みの場合 true
    func isAnimated(emoteId: String) -> Bool {
        lock.withLock { animatedEmoteIds.contains(emoteId) }
    }

    // MARK: - URL 生成

    /// エモート画像の CDN URL を生成する
    ///
    /// Twitch CDN のエモート画像 URL 形式:
    /// `https://static-cdn.jtvnw.net/emoticons/v2/{id}/{type}/dark/{scale}`
    ///
    /// - Parameters:
    ///   - emoteId: Twitch エモートID（例: "25"）
    ///   - type: 画像タイプ（`"default"` = スタティック PNG、`"animated"` = アニメーション GIF）
    ///   - scale: 画像スケール（デフォルト: `"2.0"`。Retina ディスプレイ対応）
    /// - Returns: 画像取得用 URL
    static func emoteURL(emoteId: String, type: String = "default", scale: String = "2.0") -> URL {
        // URL は固定形式のため force unwrap は安全
        URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/\(emoteId)/\(type)/dark/\(scale)")!
    }

    // MARK: - プライベートメソッド

    /// 指定タイプの画像を CDN からダウンロードする
    ///
    /// - Parameters:
    ///   - emoteId: Twitch エモートID
    ///   - type: 画像タイプ（`"default"` または `"animated"`）
    /// - Returns: ダウンロード成功時は NSImage、HTTP 200 以外または解析失敗時は nil
    private func download(emoteId: String, type: String) async -> NSImage? {
        let url = Self.emoteURL(emoteId: emoteId, type: type)
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        return image
    }

    /// 画像をキャッシュに保存し、表示サイズを設定する
    ///
    /// NSImage.size を設定することで、`Text(Image(nsImage:))` でのインライン表示サイズを
    /// `emoteDisplaySize` に揃える。ビットマップデータは変更しない。
    ///
    /// - Parameters:
    ///   - image: 保存する NSImage
    ///   - emoteId: Twitch エモートID
    ///   - isAnimated: アニメーション版かどうか
    private func store(_ image: NSImage, for emoteId: String, isAnimated: Bool) {
        image.size = NSSize(width: Self.emoteDisplaySize, height: Self.emoteDisplaySize)
        imageCache.setObject(image, forKey: emoteId as NSString)
        if isAnimated {
            lock.withLock { animatedEmoteIds.insert(emoteId) }
        }
    }
}
