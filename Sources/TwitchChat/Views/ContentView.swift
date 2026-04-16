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
struct ContentView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore
    var profileImageStore: ProfileImageStore

    var body: some View {
        NavigationSplitView {
            SidebarView(
                authState: authState,
                channelManager: channelManager,
                followedStreamStore: followedStreamStore,
                profileImageStore: profileImageStore
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if !channelManager.channelOrder.isEmpty {
                    ChannelTabBar(
                        channelManager: channelManager,
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore
                    )
                }

                // チャット本体: 選択中チャンネルのチャット、未選択時はプレースホルダー
                if let viewModel = channelManager.selectedViewModel {
                    ChatDetailView(viewModel: viewModel)
                } else {
                    Text("チャンネルを選択するか、ライブ中のストリーマーをクリックしてチャットを開始してください")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
