// ChannelTabBar.swift
// 接続中チャンネルのタブバービュー
// Chrome スタイル：左揃えの固定幅タブ、下のボーダーとアクティブタブが繋がって見える構造

import SwiftUI

/// 接続中チャンネルを Chrome スタイルのタブで表示するタブバー
///
/// - タブは左から並び、最大幅 `maxTabWidth` の固定幅で表示する
/// - タブが多い場合は `ScrollView(.horizontal)` で横スクロール可能にする
/// - アクティブタブは `ChannelTabCell.activeHeight` の分だけ下の Divider を隠し、
///   コンテンツエリアと繋がっているように見える
struct ChannelTabBar: View {

    let channelManager: ChannelManager
    let followedStreamStore: FollowedStreamStore
    let profileImageStore: ProfileImageStore

    /// 各タブの最大幅
    private static let maxTabWidth: CGFloat = 180
    /// タブバー全体の高さ（アクティブタブは +1pt で Divider を隠す）
    static let height: CGFloat = ChannelTabCell.inactiveHeight + 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(channelManager.channelOrder, id: \.self) { channel in
                    if let vm = channelManager.channels[channel] {
                        let stream = followedStreamStore.stream(forUserLogin: channel)
                        let uid = stream?.userId ?? channel
                        let name = stream?.userName ?? channel
                        ChannelTabCell(
                            viewModel: vm,
                            isSelected: channel == channelManager.selectedChannel,
                            displayName: name,
                            profileImageUrl: profileImageStore.profileImageUrl(for: uid),
                            userId: uid,
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
        .background(Color(.windowBackgroundColor))
    }
}
