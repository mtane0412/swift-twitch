// ChannelTabBar.swift
// 接続中チャンネルのタブバービュー
// detail 領域の上端に表示し、HStack で等幅タブを並べてタブ切り替えを提供する

import SwiftUI

/// 接続中チャンネルを横並びタブで表示するタブバー
///
/// - `channelManager.channelOrder` の順にタブを並べる
/// - 各タブは `ChannelTabCell` で描画し、選択・クローズ操作を処理する
/// - タブ数が増えると各タブ幅が縮小し、`ChannelTabCell` が自動的にアイコンのみに縮退する
struct ChannelTabBar: View {

    let channelManager: ChannelManager
    let followedStreamStore: FollowedStreamStore
    let profileImageStore: ProfileImageStore

    var body: some View {
        HStack(spacing: 2) {
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
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .background(.bar)
    }
}
