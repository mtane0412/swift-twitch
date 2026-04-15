// BadgeImageView.swift
// バッジ1件を画像で表示するビュー
// 画像未取得時は絵文字フォールバック表示

import AppKit
import SwiftUI

/// Twitch バッジ1件を画像で表示するビュー
///
/// - `BadgeImageCache` を通じて非同期で画像を取得・表示する
/// - 画像取得前または取得失敗時は絵文字フォールバックで表示する
struct BadgeImageView: View {

    let badge: Badge
    let store: BadgeStore

    @State private var badgeImage: NSImage?

    var body: some View {
        Group {
            if let image = badgeImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(
                        width: BadgeImageCache.badgeDisplaySize,
                        height: BadgeImageCache.badgeDisplaySize
                    )
            } else {
                // 画像未取得時の絵文字フォールバック
                Text(fallbackEmoji(for: badge.name))
                    .font(.system(size: 11))
            }
        }
        .task(id: badge.name + "/" + badge.version) {
            // タスク再実行時に古い画像をクリアしてフォールバックを表示してから再取得する
            badgeImage = nil
            badgeImage = await BadgeImageCache.shared.image(for: badge, store: store)
        }
    }

    /// バッジ名に対応する絵文字フォールバックを返す
    private func fallbackEmoji(for badgeName: String) -> String {
        switch badgeName {
        case "broadcaster": return "📡"
        case "moderator": return "⚔️"
        case "subscriber": return "★"
        case "vip": return "💎"
        case "partner": return "✓"
        case "staff": return "🔧"
        default: return "•"
        }
    }
}
