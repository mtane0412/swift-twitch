// StreamRow.swift
// サイドバーのフォロー中ストリーマー1行表示
// プロフィール画像・ストリーマー名・ゲーム名・視聴者数をコンパクトに表示する

import SwiftUI

/// フォロー中ストリーマーの1行表示コンポーネント
///
/// サイドバーの「ライブ」セクションで使用する
struct StreamRow: View {
    let stream: FollowedStream
    let profileImageStore: ProfileImageStore

    var body: some View {
        HStack(spacing: 8) {
            // プロフィール画像（円形アイコン）
            ProfileImageView(
                userId: stream.userId,
                imageUrl: profileImageStore.profileImageUrl(for: stream.userId)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(stream.userName)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(stream.gameName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    // 視聴者数（1000以上はK表示）
                    Text(formatViewerCount(stream.viewerCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 視聴者数を読みやすい形式にフォーマットする
    ///
    /// - 1000未満: そのまま表示
    /// - 1000以上: 「12.3K」形式
    private func formatViewerCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK", k)
        }
        return "\(count)"
    }
}
