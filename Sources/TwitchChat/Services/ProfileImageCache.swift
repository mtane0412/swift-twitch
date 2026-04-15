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

    /// inFlightTasks へのアクセスを保護するロック
    private let lock = NSLock()

    /// ダウンロード失敗時のログ出力に使用するロガー
    private let logger = Logger(subsystem: "dev.mtane.TwitchChat", category: "ProfileImageCache")

    private init() {}

    // MARK: - 画像取得

    /// プロフィール画像を取得する（キャッシュ優先・並行重複排除付き）
    ///
    /// - Parameters:
    ///   - userId: Twitch ユーザーID（キャッシュキーとして使用）
    ///   - imageUrl: プロフィール画像 URL 文字列
    /// - Returns: ダウンロード済みの NSImage（`displaySize` にリサイズ済み）。取得失敗時は nil
    func image(for userId: String, imageUrl: String) async -> NSImage? {
        let cacheKey = userId as NSString

        // キャッシュヒット: 即時返却
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = URL(string: imageUrl) else {
            logger.warning("プロフィール画像の URL が不正: \(imageUrl)")
            return nil
        }

        // 進行中タスクへの相乗り、または新規タスクの作成（排他制御）
        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inFlightTasks[userId] {
                return existing
            }
            let newTask = Task { [weak self] in
                guard let self else { return nil as NSImage? }
                defer { _ = self.lock.withLock { self.inFlightTasks.removeValue(forKey: userId) } }

                guard let image = await self.download(from: url) else { return nil }
                self.store(image, for: userId)
                return image
            }
            inFlightTasks[userId] = newTask
            return newTask
        }

        return await task.value
    }

    // MARK: - プライベートメソッド

    /// 指定 URL から画像をダウンロードする
    private func download(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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
            return image
        } catch {
            logger.warning("プロフィール画像ダウンロード失敗: \(url) - \(error)")
            return nil
        }
    }

    /// 画像をピクセルレベルでリサイズしてキャッシュに保存する
    ///
    /// NSImage.size の変更は描画サイズのみ変わりピクセルデータは保持されるため、
    /// ビットマップコンテキストに描画し直すことでメモリ使用量を削減する。
    private func store(_ image: NSImage, for userId: String) {
        let targetSize = NSSize(width: Self.displaySize, height: Self.displaySize)
        let resized: NSImage
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            bitmapRep.size = targetSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            image.draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
            NSGraphicsContext.restoreGraphicsState()
            let small = NSImage(size: targetSize)
            small.addRepresentation(bitmapRep)
            resized = small
        } else {
            // ビットマップ作成失敗時はサイズ設定のみのフォールバック
            image.size = targetSize
            resized = image
        }
        imageCache.setObject(resized, forKey: userId as NSString)
    }
}
