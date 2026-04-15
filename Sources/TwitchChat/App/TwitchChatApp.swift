// TwitchChatApp.swift
// アプリケーションのエントリポイント
// SwiftUI の App プロトコルに準拠し、メインウィンドウを定義する

import SwiftUI

/// Twitch IRC チャットビューアーのアプリ定義
///
/// @main は使わず main.swift でエントリポイントを明示的に指定する
/// （SPM executable ターゲットで NSApplication を正しく初期化するため）
struct TwitchChatApp: App {
    /// アプリ全体で共有する認証状態
    @State private var authState = AuthState()
    /// 複数チャンネル接続を管理するマネージャー
    @State private var channelManager: ChannelManager?
    /// フォロー中ストリーム一覧ストア
    @State private var followedStreamStore: FollowedStreamStore?

    var body: some Scene {
        WindowGroup {
            // channelManager と followedStreamStore は authState に依存するため
            // ContentView 内で遅延初期化する
            if let channelManager, let followedStreamStore {
                ContentView(
                    authState: authState,
                    channelManager: channelManager,
                    followedStreamStore: followedStreamStore
                )
                .task {
                    await authState.restoreSession()
                    // ログイン済みならフォロー中ストリーム自動更新を開始
                    if case .loggedIn = authState.status {
                        followedStreamStore.startAutoRefresh()
                    }
                }
                .onChange(of: authState.status) { _, newStatus in
                    switch newStatus {
                    case .loggedIn:
                        followedStreamStore.startAutoRefresh()
                    case .loggedOut:
                        followedStreamStore.stopAutoRefresh()
                        followedStreamStore.clear()
                        Task { await channelManager.disconnectAll() }
                    case .unknown:
                        break
                    }
                }
            } else {
                ProgressView("起動中...")
                    .onAppear {
                        let helixClient = HelixAPIClient(tokenProvider: authState)
                        channelManager = ChannelManager(authState: authState)
                        followedStreamStore = FollowedStreamStore(
                            apiClient: helixClient,
                            authState: authState
                        )
                    }
            }
        }
        .defaultSize(width: 800, height: 700)
    }
}
