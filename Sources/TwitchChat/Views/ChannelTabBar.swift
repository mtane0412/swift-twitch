// ChannelTabBar.swift
// 接続中チャンネルのタブバービュー
// Chrome スタイル：左揃えの固定幅タブ、下のボーダーとアクティブタブが繋がって見える構造

import SwiftUI

/// 接続中チャンネルを Chrome スタイルのタブで表示するタブバー
///
/// - タブは左から並び、最大幅 `maxTabWidth` の固定幅で表示する
/// - タブが多い場合は `ScrollView(.horizontal)` で横スクロール可能にする
/// - アクティブタブは非アクティブタブより高く描画され、コンテンツエリアと視覚的に繋がって見える
struct ChannelTabBar: View {

    let channelManager: ChannelManager
    let followedStreamStore: FollowedStreamStore
    let profileImageStore: ProfileImageStore

    /// 各タブの最大幅
    private static let maxTabWidth: CGFloat = 180
    /// タブバー全体の高さ（アクティブタブは +2pt 分の余白を含む）
    static let height: CGFloat = ChannelTabCell.inactiveHeight + 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(channelManager.channelOrder, id: \.self) { channel in
                    if channelManager.channels[channel] != nil {
                        let stream = followedStreamStore.stream(forUserLogin: channel)
                        let userId = stream?.userId
                        let name = stream?.userName ?? channel
                        ChannelTabCell(
                            isSelected: channel == channelManager.selectedChannel,
                            displayName: name,
                            profileImageUrl: userId.flatMap { profileImageStore.profileImageUrl(for: $0) },
                            userId: userId,
                            onSelect: { channelManager.selectChannel(channel) },
                            onClose: { Task { await channelManager.leaveChannel(channel) } }
                        )
                        .frame(width: Self.maxTabWidth)
                    }
                }
            }
            // ScrollView 内でタブを底揃えにする
            .frame(height: Self.height, alignment: .bottom)
        }
        .frame(height: Self.height)
        // タブバー背景: チャット欄（controlBackgroundColor）より明示的に少し暗くする
        // brightness(-0.05) は絶対値ではなく相対的な暗さのため、ライト/ダーク両対応
        .background(Color(.controlBackgroundColor).brightness(-0.05))
    }
}
