// ContentView.swift
// メインレイアウトビュー
// NavigationSplitView でサイドバー（チャンネルリスト）とチャット詳細ペインを構成する

import SwiftUI

/// アプリのメインコンテンツビュー
///
/// レイアウト:
/// - サイドバー: フォロー中ライブ一覧 + 接続中チャンネル一覧（SidebarView）
/// - 詳細ペイン: 選択中チャンネルのチャットメッセージ（ChatDetailView）
/// - 未選択時: プレースホルダーを表示
struct ContentView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore

    var body: some View {
        NavigationSplitView {
            SidebarView(
                authState: authState,
                channelManager: channelManager,
                followedStreamStore: followedStreamStore
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let viewModel = channelManager.selectedViewModel {
                ChatDetailView(viewModel: viewModel)
            } else {
                Text("チャンネルを選択するか、ライブ中のストリーマーをクリックしてチャットを開始してください")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
