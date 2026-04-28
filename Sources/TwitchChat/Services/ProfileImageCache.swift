// ProfileImageCache.swift
// Twitch ユーザーのプロフィール画像キャッシュと非同期読み込みを管理するサービス
// NSCache ベースのメモリキャッシュで同一ユーザーの再ダウンロードを防ぐ

import AppKit
import Foundation
import os

/// Twitch ユーザープロフィール画像のキャッシュ管理クラス
///
/// - `ProfileImageStore` から画像 URL を解決し、CDN からダウンロード
/// - NSCache によるメモリキャッシュ（メモリプレッシャー時に自動解放）
/// - 同一ユーザーへの並行リクエストを1回のダウンロードに集約する in-flight 管理
/// - シングルトンで全 View 間でキャッシュを共有
///
/// ## @unchecked Sendable について
/// `imageCache`（NSCache）はスレッドセーフであり、`inFlightTasks` は `NSLock` で保護されている。
/// このクラスのすべての可変プロパティはスレッドセーフに管理されているため @unchecked Sendable を付与している。
/// 将来的に可変プロパティを追加する場合は、NSCache の利用または NSLock での保護が必要。
final class ProfileImageCache: @unchecked Sendable {

    /// シングルトンインスタンス
    static let shared = ProfileImageCache()

    /// プロフィール画像の表示サイズ（ポイント）
    ///
    /// サイドバーの行高に合わせた値
    static let displaySize: CGFloat = 28

    /// プロフィール画像のメモリキャッシュ（キー: userId）
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    /// 進行中のダウンロードタスク（キー: userId）
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    /// inFlightTasks / persistence へのアクセスを保護するロック
    private let lock = NSLock()

    /// ダウンロード失敗時のログ出力に使用するロガー
    private let logger = Logger(subsystem: "dev.mtane.TwitchChat", category: "ProfileImageCache")

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

    /// プロフィール画像を取得する（キャッシュ優先・並行重複排除付き）
    ///
    /// - Parameters:
    ///   - userId: Twitch ユーザーID（キャッシュキーとして使用）
    ///   - imageUrl: プロフィール画像 URL
    /// - Returns: ダウンロード済みの NSImage（`displaySize` にリサイズ済み）。取得失敗時は nil
    func image(for userId: String, imageUrl: URL) async -> NSImage? {
        let cacheKey = userId as NSString

        // キャッシュヒット: 即時返却
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // 進行中タスクへの相乗り、または新規タスクの作成（排他制御）
        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inFlightTasks[userId] {
                return existing
            }
            let newTask = Task { [weak self] in
                guard let self else { return nil as NSImage? }
                defer { _ = self.lock.withLock { self.inFlightTasks.removeValue(forKey: userId) } }

                let persistence = self.currentPersistence
                let l2Key = ImageCacheKey(kind: .profile, identifier: userId)

                // L2 ルックアップ
                if let ps = persistence,
                   let data = await ps.loadImageData(key: l2Key),
                   let image = NSImage(data: data) {
                    let resized = self.store(image, for: userId)
                    return resized
                }

                // L3 HTTP ダウンロード
                guard let (image, data) = await self.download(from: imageUrl) else { return nil }
                let resized = self.store(image, for: userId)
                if let ps = persistence {
                    try? await ps.saveImageData(data, key: l2Key, mime: "image/png")
                }
                return resized
            }
            inFlightTasks[userId] = newTask
            return newTask
        }

        return await task.value
    }

    // MARK: - プライベートメソッド

    /// 指定 URL から画像をダウンロードする（L2 保存用に生データも返す）
    private func download(from url: URL) async -> (NSImage, Data)? {
        do {
            let (data, response) = try await ImageDownloadSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("プロフィール画像レスポンスが HTTPURLResponse でない: \(url)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                logger.warning("プロフィール画像取得 HTTP \(httpResponse.statusCode): \(url)")
                return nil
            }
            guard let image = NSImage(data: data) else {
                logger.warning("プロフィール画像データを NSImage に変換できない: \(url)")
                return nil
            }
            return (image, data)
        } catch {
            logger.warning("プロフィール画像ダウンロード失敗: \(url) - \(error)")
            return nil
        }
    }

    /// 画像を CoreGraphics でピクセルレベルにリサイズしてキャッシュに保存する
    ///
    /// NSGraphicsContext はメインスレッド以外での使用が未定義動作のため、
    /// CoreGraphics ベースの CGContext でリサイズする（バックグラウンドスレッドセーフ）。
    /// リサイズ後の NSImage を返すことで L2 ヒット時に呼び出し元が直接返却できる。
    @discardableResult
    private func store(_ image: NSImage, for userId: String) -> NSImage {
        let targetSize = NSSize(width: Self.displaySize, height: Self.displaySize)
        let resized: NSImage
        // CGImage を取得して CoreGraphics コンテキストでリサイズ描画する
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            let pixelSize = Int(targetSize.width)
            if let cgContext = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ),
            let scaledCGImage = { cgContext.draw(cgImage, in: CGRect(origin: .zero, size: targetSize)); return cgContext.makeImage() }() {
                resized = NSImage(cgImage: scaledCGImage, size: targetSize)
            } else {
                // CGContext 作成失敗時はサイズ設定のみのフォールバック
                image.size = targetSize
                resized = image
            }
        } else {
            // CGImage 変換失敗時はサイズ設定のみのフォールバック
            image.size = targetSize
            resized = image
        }
        imageCache.setObject(resized, forKey: userId as NSString)
        return resized
    }

#if DEBUG
    /// テスト用: 永続化サービスを差し替える（nil でリセット）
    func attachPersistenceForTesting(_ service: (any PersistenceService)?) {
        lock.withLock { self.persistence = service }
    }
#endif
}
