// ChannelTabCell.swift
// チャンネルタブバーの個別タブセルビュー
// Chrome スタイルのタブデザイン：上部角丸の形状、アクティブタブはコンテンツエリアと繋がる

import SwiftUI

/// チャンネルタブバーの 1 タブを表すセルビュー
///
/// - アクティブタブは `windowBackgroundColor` でコンテンツエリアと同色になり「繋がって見える」
/// - 非アクティブタブは少し暗い背景色で区別する
/// - `UnevenRoundedRectangle` で上部のみ角丸のタブ形状を実現する
/// - × ボタンはホバー中または選択中のタブにのみ表示する
struct ChannelTabCell: View {

    /// このタブに対応する ChatViewModel
    let viewModel: ChatViewModel
    /// このタブが選択中かどうか
    let isSelected: Bool
    /// タブに表示する名前（フォロー中は表示名、フォロー外は channelLogin）
    let displayName: String
    /// プロフィール画像 URL（nil の場合はプレースホルダーを表示）
    let profileImageUrl: URL?
    /// Twitch ユーザーID（プロフィール画像キャッシュのキー）
    let userId: String
    /// タブ選択時のコールバック
    let onSelect: () -> Void
    /// タブを閉じる（チャンネルから退出する）コールバック
    let onClose: () -> Void

    @State private var isHovered = false

    // MARK: - 定数

    /// アイコンサイズ（ポイント）
    private static let iconSize: CGFloat = 16
    /// × ボタンのアイコンサイズ（ポイント）
    private static let closeIconSize: CGFloat = 7
    /// タブの上部角丸半径
    private static let cornerRadius: CGFloat = 8
    /// タブの通常高さ（非アクティブ）
    static let inactiveHeight: CGFloat = 30
    /// タブのアクティブ高さ（Divider を 1pt 隠すため +1）
    static let activeHeight: CGFloat = 32

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                // プロフィールアイコン
                ProfileImageView(userId: userId, imageUrl: profileImageUrl, size: Self.iconSize)

                // チャンネル名（truncation あり）
                Text(displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // × ボタン（選択中またはホバー時のみ表示）
                if isSelected || isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: Self.closeIconSize, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    // × ボタンの幅を確保して他のタブの幅計算が安定するよう hidden で埋め
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: Self.closeIconSize, weight: .medium))
                        .hidden()
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        // アクティブタブはコンテンツ領域と繋げるため 1pt 高くする
        .frame(height: isSelected ? Self.activeHeight : Self.inactiveHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .top) {
            tabBackground
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - タブ背景

    /// Chrome 風の上部角丸タブ形状の背景
    ///
    /// - アクティブタブ: `controlBackgroundColor`（チャット欄の背景色と一致）で塗り、
    ///   左右・上部に細いボーダーを付ける
    /// - 非アクティブタブ: 塗りは透明（タブバー背景と完全に同化）にして目立たせない
    ///   ホバー時のみ薄い塗りで存在を示す
    private var tabBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.cornerRadius
        )
        return ZStack {
            if isSelected {
                // アクティブタブ: チャット欄（controlBackgroundColor）と同色
                // ボーダーなし（下端の線をなくしてコンテンツと繋げる）
                shape
                    .fill(Color(.controlBackgroundColor))
            } else {
                // 非アクティブタブ: 透明（タブバー背景に同化）
                // ホバー時のみ薄い塗りで存在をほのめかす
                shape
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            }
        }
        .frame(height: isSelected ? Self.activeHeight : Self.inactiveHeight)
    }
}
