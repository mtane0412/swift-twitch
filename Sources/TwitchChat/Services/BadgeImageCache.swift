// BadgeImageCache.swift
// Twitch バッジ画像のキャッシュと非同期読み込みを管理するサービス
// NSCache ベースのメモリキャッシュで同一バッジの再ダウンロードを防ぐ

import AppKit
import Foundation
import os

/// Twitch バッジ画像のキャッシュ管理クラス
///
/// - `BadgeStore` から画像 URL を解決し、CDN からダウンロード
/// - NSCache によるメモリキャッシュ（メモリプレッシャー時に自動解放）
/// - 同一バッジへの並行リクエストを1回のダウンロードに集約する in-flight 管理
/// - シングルトンで全 View 間でキャッシュを共有
final class BadgeImageCache: @unchecked Sendable {

    /// シングルトンインスタンス
    static let shared = BadgeImageCache()

    /// バッジの表示サイズ（ポイント）
    ///
    /// テキスト行高に合わせた値。NSImage.size および BadgeImageView のフレームサイズに使用する。
    static let badgeDisplaySize: CGFloat = 18

    /// バッジ画像のメモリキャッシュ（キー: "badgeName/version"）
    private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    /// 進行中のダウンロードタスク（キー: "badgeName/version"）
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    /// inFlightTasks / persistence へのアクセスを保護するロック
    private let lock = NSLock()

    /// バッジ画像取得失敗時のログ出力に使用するロガー
    private let logger = Logger(subsystem: "dev.mtane.TwitchChat", category: "BadgeImageCache")

    /// L2 ディスクキャッシュサービス（nil の場合は L2 スキップ）
    private var persistence: (any PersistenceService)?

    private init() {}

    /// L2 永続化サービスを注入する（アプリ起動時に TwitchChatApp から呼ぶ）
    func attachPersistence(_ service: any PersistenceService) {
        lock.withLock { self.persistence = service }
    }

    private var currentPersistence: (any PersistenceService)? {
        lock.withLock { persistence }
    }

    // MARK: - 画像取得

    /// バッジ画像を取得する（キャッシュ優先・並行重複排除付き）
    ///
    /// - Parameters:
    ///   - badge: 表示対象のバッジ
    ///   - store: バッジ定義ストア（URL解決に使用）
    /// - Returns: ダウンロード済みの NSImage（`badgeDisplaySize` にリサイズ済み）。取得失敗時は nil
    func image(for badge: Badge, store: BadgeStore) async -> NSImage? {
        let key = Self.cacheKey(for: badge)
        let cacheKey = key as NSString

        // キャッシュヒット: 即時返却
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // 進行中タスクへの相乗り、または新規タスクの作成（排他制御）
        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inFlightTasks[key] {
                return existing
            }
            let newTask = Task { [weak self] in
                guard let self else { return nil as NSImage? }
                defer { _ = self.lock.withLock { self.inFlightTasks.removeValue(forKey: key) } }

                let persistence = self.currentPersistence
                let l2Key = ImageCacheKey(kind: .badge, identifier: "\(badge.name):\(badge.version)")

                // L2 ルックアップ
                if let ps = persistence,
                   let data = await ps.loadImageData(key: l2Key),
                   let image = NSImage(data: data) {
                    self.store(image, for: key)
                    return image
                }

                // L3 HTTP ダウンロード
                guard let url = await store.imageURL(for: badge),
                      let (image, data) = await self.download(from: url) else { return nil }
                self.store(image, for: key)
                if let ps = persistence {
                    try? await ps.saveImageData(data, key: l2Key, mime: "image/png")
                }
                return image
            }
            inFlightTasks[key] = newTask
            return newTask
        }

        return await task.value
    }

    // MARK: - 静的ユーティリティ

    /// バッジのキャッシュキーを生成する
    ///
    /// - Parameter badge: 対象のバッジ
    /// - Returns: "badgeName/version" 形式のキー文字列
    static func cacheKey(for badge: Badge) -> String {
        "\(badge.name)/\(badge.version)"
    }

    // MARK: - プライベートメソッド

    /// 指定 URL から画像をダウンロードする（L2 保存用に生データも返す）
    private func download(from url: URL) async -> (NSImage, Data)? {
        do {
            let (data, response) = try await ImageDownloadSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("バッジ画像レスポンスが HTTPURLResponse でない: \(url)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                logger.warning("バッジ画像取得 HTTP \(httpResponse.statusCode): \(url)")
                return nil
            }
            guard let image = NSImage(data: data) else {
                logger.warning("バッジ画像データを NSImage に変換できない: \(url)")
                return nil
            }
            return (image, data)
        } catch {
            logger.warning("バッジ画像ダウンロード失敗: \(url) - \(error)")
            return nil
        }
    }

    /// 画像をキャッシュに保存し、表示サイズを設定する
    private func store(_ image: NSImage, for key: String) {
        image.size = NSSize(width: Self.badgeDisplaySize, height: Self.badgeDisplaySize)
        imageCache.setObject(image, forKey: key as NSString)
    }

#if DEBUG
    /// テスト用: 永続化サービスを差し替える（nil でリセット）
    func attachPersistenceForTesting(_ service: (any PersistenceService)?) {
        lock.withLock { self.persistence = service }
    }
#endif
}
