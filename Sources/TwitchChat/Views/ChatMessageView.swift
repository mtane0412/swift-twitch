// ChatMessageView.swift
// チャットメッセージ 1 件を表示するビュー
// ユーザー名（色付き）・バッジ・メッセージ本文（アニメーションエモート含む）を横並びで表示する

import AppKit
import SwiftUI

/// チャットメッセージ 1 件の表示ビュー
///
/// - ユーザー名を Twitch 設定の色で表示
/// - バッジを絵文字で表現（broadcaster: 📡、moderator: ⚔️、subscriber: ★）
/// - メッセージ本文を FlowLayout でレンダリングし、エモートを AnimatedEmoteView でインライン表示
/// - アニメーション GIF エモートは `NSImageView.animates = true` で自動再生
/// - エモート未読み込み時はエモート名をグレーテキストのプレースホルダとして表示
struct ChatMessageView: View {

    let message: ChatMessage

    /// ダウンロード済みエモート画像（キー: エモートID）
    @State private var emoteImages: [String: NSImage] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // バッジ表示
            if !message.badges.isEmpty {
                badgesView
            }

            // メッセージ全体を FlowLayout でレンダリング
            // ユーザー名・コロン・メッセージ本文をすべてフロー内に配置することで
            // テキストとエモート画像が自然に折り返す
            FlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
                // ユーザー名 + コロン（1つの Text ビューとして連結）
                (Text(message.displayName)
                    .fontWeight(.semibold)
                    .foregroundStyle(usernameColor)
                    + Text(": ")
                    .foregroundStyle(.secondary))
                    .fixedSize()

                // メッセージ本文のセグメント
                ForEach(Array(message.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let str):
                        Text(str)
                            .foregroundStyle(.primary)
                            // 長いテキストセグメントは幅に収まるよう折り返す
                            .fixedSize(horizontal: false, vertical: true)

                    case .emote(let id, let name):
                        if let nsImage = emoteImages[id] {
                            // 画像取得済み: AnimatedEmoteView でインライン表示（GIF 対応）
                            AnimatedEmoteView(
                                image: nsImage,
                                isAnimated: EmoteImageCache.shared.isAnimated(emoteId: id)
                            )
                        } else {
                            // 未取得: エモート名をプレースホルダとして表示
                            Text(name)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .task(id: message.id) {
            await loadEmoteImages()
        }
    }

    /// 必要なエモート画像を非同期ダウンロードする
    private func loadEmoteImages() async {
        // ユニークなエモートIDを収集
        let emoteIds = Set(message.segments.compactMap { segment -> String? in
            if case .emote(let id, _) = segment { return id }
            return nil
        })
        guard !emoteIds.isEmpty else { return }

        // 並行ダウンロード
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for id in emoteIds {
                group.addTask {
                    let image = await EmoteImageCache.shared.image(for: id)
                    return (id, image)
                }
            }
            for await (id, image) in group {
                if let image {
                    emoteImages[id] = image
                }
            }
        }
    }

    /// バッジを絵文字で表示
    private var badgesView: some View {
        HStack(spacing: 2) {
            ForEach(message.badges, id: \.name) { badge in
                Text(badgeEmoji(for: badge.name))
                    .font(.system(size: 11))
            }
        }
    }

    /// バッジ名に対応する絵文字を返す
    private func badgeEmoji(for badgeName: String) -> String {
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

    /// Twitch の色設定を SwiftUI の Color に変換する
    private var usernameColor: Color {
        guard let hex = message.colorHex, hex.hasPrefix("#"), hex.count == 7 else {
            return .accentColor
        }
        let r = Double(Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255
        let g = Double(Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255
        let b = Double(Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255
        return Color(red: r, green: g, blue: b)
    }
}
