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
/// - 同一エモートへの並行リクエストを1回のダウンロードに集約する in-flight 管理
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

    /// 進行中のダウンロードタスク（キー: エモートID）
    ///
    /// 同一エモートへの並行リクエストを1回のダウンロードに集約し、重複ネットワーク通信を防ぐ。
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    /// animatedEmoteIds / inFlightTasks へのアクセスを保護するロック
    private let lock = NSLock()

    private init() {}

    // MARK: - 画像取得

    /// エモートIDから画像を取得する（キャッシュ優先・並行重複排除付き）
    ///
    /// 取得順序:
    /// 1. キャッシュヒットなら即時返却
    /// 2. 進行中タスクがあれば結果を待つ（重複ダウンロード回避）
    /// 3. 新規タスクを作成: アニメーション版 → スタティック版の順でダウンロード
    ///
    /// - Parameter emoteId: Twitch エモートID（例: "25"）
    /// - Returns: ダウンロード済みの NSImage（`emoteDisplaySize` にリサイズ済み）。取得失敗時は nil
    func image(for emoteId: String) async -> NSImage? {
        let cacheKey = emoteId as NSString

        // キャッシュヒット: 即時返却
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // 進行中タスクへの相乗り、または新規タスクの作成（排他制御）
        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inFlightTasks[emoteId] {
                return existing
            }
            let newTask = Task { [weak self] in
                guard let self else { return nil as NSImage? }
                defer { _ = self.lock.withLock { self.inFlightTasks.removeValue(forKey: emoteId) } }

                // アニメーション版を先に試みる
                if let image = await self.download(emoteId: emoteId, type: "animated") {
                    self.store(image, for: emoteId, isAnimated: true)
                    return image
                }
                // スタティック版にフォールバック
                if let image = await self.download(emoteId: emoteId, type: "default") {
                    self.store(image, for: emoteId, isAnimated: false)
                    return image
                }
                return nil
            }
            inFlightTasks[emoteId] = newTask
            return newTask
        }

        return await task.value
    }

    /// エモートがアニメーション版かどうかを返す
    ///
    /// - Parameter emoteId: Twitch エモートID
    /// - Returns: アニメーション版が取得済みの場合 true
    func isAnimated(emoteId: String) -> Bool {
        lock.withLock { animatedEmoteIds.contains(emoteId) }
    }

    /// キャッシュ済みのエモート画像を同期的に返す（ダウンロードは行わない）
    ///
    /// NSTextAttachment の描画など、非同期処理が使えない文脈で使用する。
    /// キャッシュにない場合は nil を返す。ダウンロードが必要な場合は `image(for:)` を使用すること。
    ///
    /// - Parameter emoteId: Twitch エモートID
    /// - Returns: キャッシュ済みの NSImage、未キャッシュの場合は nil
    func cachedImage(for emoteId: String) -> NSImage? {
        imageCache.object(forKey: emoteId as NSString)
    }

    /// 入力欄インライン表示用のスタティックエモート画像を取得する
    ///
    /// アニメーションエモートはスタティック版（PNG）をダウンロードして返す。
    /// NSTextAttachment はアニメーション GIF を再生できないため、
    /// 入力欄ではスタティック版を使用してフレームが固まって見える問題を防ぐ。
    /// 非アニメーションエモートはキャッシュ済み画像をそのまま返す。
    ///
    /// - Parameter emoteId: Twitch エモートID
    /// - Returns: スタティック NSImage。取得失敗時は nil
    func staticImage(for emoteId: String) async -> NSImage? {
        if isAnimated(emoteId: emoteId) {
            // アニメーションエモートはスタティック版を都度ダウンロードする
            // （スタティック版の独立したキャッシュは持たないが頻度が低いため許容する）
            return await download(emoteId: emoteId, type: "default")
        }
        // 非アニメーションはキャッシュから返す（なければ通常取得）
        return await image(for: emoteId)
    }

    // MARK: - URL 生成

    /// エモート画像の CDN URL を生成する
    ///
    /// Twitch CDN のエモート画像 URL 形式:
    /// `https://static-cdn.jtvnw.net/emoticons/v2/{id}/{type}/dark/{scale}`
    ///
    /// - Parameters:
    ///   - emoteId: Twitch エモートID（例: "25"）。URL パスコンポーネントとして percent-encode される
    ///   - type: 画像タイプ（`"default"` = スタティック PNG、`"animated"` = アニメーション GIF）
    ///   - scale: 画像スケール（デフォルト: `"2.0"`。Retina ディスプレイ対応）
    /// - Returns: 画像取得用 URL
    static func emoteURL(emoteId: String, type: String = "default", scale: String = "2.0") -> URL {
        // URLComponents でパスコンポーネントを安全にパーセントエンコードする
        var components = URLComponents()
        components.scheme = "https"
        components.host = "static-cdn.jtvnw.net"
        components.path = "/emoticons/v2/\(emoteId)/\(type)/dark/\(scale)"
        // emoteId は数値文字列、type・scale は固定値のため URL 構築は常に成功する
        return components.url!
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
            _ = lock.withLock { animatedEmoteIds.insert(emoteId) }
        }
    }
}
