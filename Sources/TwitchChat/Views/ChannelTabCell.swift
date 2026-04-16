// ChannelTabCell.swift
// チャンネルタブバーの個別タブセルビュー
// ViewThatFits で「アイコン+名前+×」→「アイコン+×」→「アイコンのみ」の 3 段階で幅に応じて縮退する

import SwiftUI

/// チャンネルタブバーの 1 タブを表すセルビュー
///
/// - `ViewThatFits` により、利用可能な幅が狭い場合は自動的にコンパクト表示へ縮退する
/// - アイコンには接続状態（緑/黄/赤/灰）の色付きボーダーを表示する
/// - 選択中タブはアクセントカラーの薄い背景で強調する
/// - × ボタンは選択中またはホバー時に表示し、押下で `onClose` を呼ぶ
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

    private static let iconSize: CGFloat = 20
    private static let closeIconSize: CGFloat = 7

    var body: some View {
        Button(action: onSelect) {
            ViewThatFits(in: .horizontal) {
                // フル表示: アイコン + 名前 + × ボタン
                fullLabel
                // 中間表示: アイコン + × ボタン
                compactLabel
                // 最小表示: アイコンのみ（ホバー/選択中に × オーバーレイ）
                iconOnly
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
    }

    // MARK: - サブビュー

    private var icon: some View {
        ProfileImageView(userId: userId, imageUrl: profileImageUrl, size: Self.iconSize)
            .overlay {
                Circle()
                    .strokeBorder(viewModel.connectionState.connectionColor, lineWidth: 2)
            }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: Self.closeIconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var fullLabel: some View {
        HStack(spacing: 4) {
            icon
            Text(displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 40)
            closeButton
        }
    }

    private var compactLabel: some View {
        HStack(spacing: 4) {
            icon
            closeButton
        }
    }

    private var iconOnly: some View {
        icon
            .overlay(alignment: .topTrailing) {
                if isHovered || isSelected {
                    closeButton
                        .font(.system(size: Self.closeIconSize - 1))
                        .padding(2)
                        .background(Circle().fill(.bar))
                        .offset(x: 4, y: -4)
                }
            }
    }
}
