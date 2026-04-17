// ContentView.swift
// メインレイアウトビュー
// NavigationSplitView でサイドバー（チャンネルリスト）とチャット詳細ペインを構成する

import SwiftUI

/// アプリのメインコンテンツビュー
///
/// レイアウト:
/// - サイドバー: フォロー中ライブ一覧（接続中は先頭）（SidebarView）
/// - 詳細ペイン:
///   - タブバー（接続中チャンネルをタブで切り替え、Chrome スタイル）
///   - 選択チャンネルのチャット本体（未選択時はプレースホルダーを表示）
///
/// blank tab の状態管理:
/// - `isBlankTabOpen` で blank tab の開閉を管理する
/// - blank tab は IRC 未接続のため ChannelManager の管理対象外で、ContentView レベルで管理する
struct ContentView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore
    var profileImageStore: ProfileImageStore

    /// blank tab（チャンネル名入力フォーム）が開いているかどうか
    @State private var isBlankTabOpen: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                authState: authState,
                channelManager: channelManager,
                followedStreamStore: followedStreamStore,
                profileImageStore: profileImageStore,
                isBlankTabOpen: $isBlankTabOpen
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                // タブバー: 接続中タブが1つ以上あるか、blank tab が開いているときに表示
                if !channelManager.channelOrder.isEmpty || isBlankTabOpen {
                    ChannelTabBar(
                        channelManager: channelManager,
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore,
                        isBlankTabOpen: $isBlankTabOpen
                    )
                }

                // チャット本体: blank tab → 検索フォーム、選択中チャンネル → チャット、それ以外 → 初期フォーム
                if isBlankTabOpen {
                    // blank tab: チャンネル名入力フォーム
                    ChannelSearchView(
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore,
                        onChannelSelected: { channelLogin in
                            isBlankTabOpen = false
                            Task { await channelManager.joinChannel(channelLogin) }
                        },
                        onCancel: {
                            isBlankTabOpen = false
                            channelManager.selectedChannel = channelManager.channelOrder.last
                        }
                    )
                } else if let viewModel = channelManager.selectedViewModel {
                    ChatDetailView(viewModel: viewModel, authState: authState)
                } else {
                    // タブ0個の初期状態: チャンネル名入力フォームを直接表示
                    ChannelSearchView(
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore,
                        onChannelSelected: { channelLogin in
                            Task { await channelManager.joinChannel(channelLogin) }
                        },
                        onCancel: nil
                    )
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
