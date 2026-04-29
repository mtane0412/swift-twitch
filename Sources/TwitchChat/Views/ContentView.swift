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
    var followedChannelStore: FollowedChannelStore
    var profileImageStore: ProfileImageStore
    /// ライブ配信プレイヤー ViewModel（TwitchChatApp から注入）
    var streamPlayer: StreamPlayerViewModel

    /// blank tab（チャンネル名入力フォーム）が開いているかどうか
    @State private var isBlankTabOpen: Bool = false

    /// ライブ配信プレイヤー機能の有効・無効（SettingsView から変更可能）
    @AppStorage("livePlayerEnabled") private var livePlayerEnabled = false

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
                        followedChannelStore: followedChannelStore,
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore,
                        onChannelSelected: { channelLogin in
                            isBlankTabOpen = false
                            Task { await channelManager.joinChannel(channelLogin) }
                        },
                        onCancel: {
                            // isBlankTabOpen を false にするだけで selectedChannel は変更しない
                            // selectedViewModel が既存の選択チャンネルを自然に復元する
                            isBlankTabOpen = false
                        }
                    )
                } else if let viewModel = channelManager.selectedViewModel {
                    ChatDetailView(
                        viewModel: viewModel,
                        authState: authState,
                        profileImageStore: profileImageStore,
                        streamPlayer: streamPlayer
                    )
                } else {
                    // タブ0個の初期状態: チャンネル名入力フォームを直接表示
                    ChannelSearchView(
                        followedChannelStore: followedChannelStore,
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
        .onChange(of: channelManager.selectedChannel) { _, newChannel in
            // livePlayerEnabled かつチャンネルが切り替わった場合にのみ再生を開始する
            guard livePlayerEnabled, let login = newChannel else {
                if newChannel == nil { streamPlayer.stop() }
                return
            }
            Task { await streamPlayer.load(login: login) }
        }
        .onChange(of: livePlayerEnabled) { _, enabled in
            // 機能を OFF にしたら再生を停止する
            if !enabled {
                streamPlayer.stop()
            } else if let login = channelManager.selectedChannel {
                // ON にしたとき、選択中チャンネルがあれば即座に読み込む
                Task { await streamPlayer.load(login: login) }
            }
        }
    }
}
