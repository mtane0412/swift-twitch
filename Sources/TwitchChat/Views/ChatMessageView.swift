// ChatMessageView.swift
// チャットメッセージ 1 件を表示するビュー
// ユーザー名（色付き）・バッジ・メッセージ本文を横並びで表示する

import SwiftUI

/// チャットメッセージ 1 件の表示ビュー
///
/// - ユーザー名を Twitch 設定の色で表示
/// - バッジを絵文字で表現（broadcaster: 📡、moderator: ⚔️、subscriber: ★）
/// - メッセージ本文を通常テキストで表示
struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // バッジ表示
            if !message.badges.isEmpty {
                badgesView
            }

            // ユーザー名（Twitch 設定の色）
            Text(message.displayName)
                .fontWeight(.semibold)
                .foregroundStyle(usernameColor)
                + Text(": ")
                .foregroundStyle(.secondary)
                + Text(message.text)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
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
