// ConnectedChannelIconStrip.swift
// 接続中チャンネルのプロフィールアイコンを横並び表示するビュー
// サイドバーの「ライブ」セクション先頭に配置し、アイコンクリックで対応タブへフォーカスする

import SwiftUI

/// 接続中チャンネルのプロフィールアイコンを横並びで表示するストリップビュー
///
/// - 接続状態（connected/connecting/error/disconnected）に応じた色のボーダーをアイコンに表示する
/// - 現在選択中のタブに対応するアイコンは、アクセントカラーの外側リングを重ねて強調する
/// - フォロー外チャンネルの場合は `person.fill` プレースホルダーを表示する
/// - アイコンをクリックすると `selectChannel` を呼び、対応するタブへフォーカスする
struct ConnectedChannelIconStrip: View {

    let channelManager: ChannelManager
    let followedStreamStore: FollowedStreamStore
    let profileImageStore: ProfileImageStore

    /// アイコンサイズ（ポイント）
    private static let iconSize: CGFloat = ProfileImageCache.displaySize
    /// 接続状態ボーダーの幅（ポイント）
    private static let borderWidth: CGFloat = 2
    /// 選択中アイコンの外側リング幅（ポイント）
    private static let selectedRingWidth: CGFloat = 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(channelManager.channelOrder, id: \.self) { channel in
                    iconButton(for: channel)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - サブビュー

    /// チャンネル 1 件分のアイコンボタン
    @ViewBuilder
    private func iconButton(for channel: String) -> some View {
        let vm = channelManager.channels[channel]
        let stream = followedStreamStore.stream(forUserLogin: channel)
        let connectionColor = (vm?.connectionState ?? .disconnected).connectionColor
        let isSelected = channelManager.selectedChannel == channel

        Button {
            channelManager.selectChannel(channel)
        } label: {
            channelIcon(
                userId: stream?.userId,
                imageUrl: stream.flatMap { profileImageStore.profileImageUrl(for: $0.userId) },
                connectionColor: connectionColor,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        // フォロー外チャンネルの場合はチャンネル名をツールチップで表示
        .help(stream?.userName ?? channel)
    }

    /// プロフィールアイコン（接続状態ボーダー + 選択中の外側リング）
    ///
    /// - Note: userId が nil の場合（フォロー外チャンネル）は ProfileImageCache を汚染しないよう、
    ///   `ProfileImageView` を使わず `person.fill` プレースホルダーを直接描画する
    @ViewBuilder
    private func channelIcon(
        userId: String?,
        imageUrl: URL?,
        connectionColor: Color,
        isSelected: Bool
    ) -> some View {
        let size = Self.iconSize

        Group {
            if let userId {
                ProfileImageView(userId: userId, imageUrl: imageUrl, size: size)
            } else {
                // フォロー外チャンネル: プレースホルダー
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: size, height: size)
            }
        }
        // 接続状態ボーダー（内側）
        .overlay {
            Circle()
                .strokeBorder(connectionColor, lineWidth: Self.borderWidth)
        }
        // 選択中の場合、アクセントカラーの外側リングを追加
        .overlay {
            if isSelected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: Self.selectedRingWidth)
                    .padding(-Self.borderWidth - Self.selectedRingWidth)
            }
        }
        // 選択中の外側リング分のパディングを確保
        .padding(isSelected ? Self.borderWidth + Self.selectedRingWidth : 0)
    }
}
