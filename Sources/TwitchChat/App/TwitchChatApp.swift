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
    /// フォロー中ライブストリーム一覧ストア（60秒ごと自動更新）
    @State private var followedStreamStore: FollowedStreamStore?
    /// フォロー中チャンネル一覧ストア（起動時1回取得・キャッシュ）
    @State private var followedChannelStore: FollowedChannelStore?
    /// ユーザープロフィール画像URLストア
    @State private var profileImageStore: ProfileImageStore?

    var body: some Scene {
        WindowGroup {
            // 各ストアは authState に依存するため onAppear で遅延初期化する
            if let channelManager,
               let followedStreamStore,
               let followedChannelStore,
               let profileImageStore {
                ContentView(
                    authState: authState,
                    channelManager: channelManager,
                    followedStreamStore: followedStreamStore,
                    followedChannelStore: followedChannelStore,
                    profileImageStore: profileImageStore
                )
                .task {
                    await authState.restoreSession()
                    if case .loggedIn = authState.status {
                        followedStreamStore.startAutoRefresh()
                        // フォロー中全チャンネルを起動時に一回取得してキャッシュする
                        await followedChannelStore.fetchAll()
                    }
                }
                .onChange(of: authState.status) { _, newStatus in
                    switch newStatus {
                    case .loggedIn:
                        followedStreamStore.startAutoRefresh()
                        Task { await followedChannelStore.fetchAll() }
                    case .loggedOut:
                        followedStreamStore.stopAutoRefresh()
                        followedStreamStore.clear()
                        followedChannelStore.clear()
                        profileImageStore.clear()
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
                        followedChannelStore = FollowedChannelStore(
                            apiClient: helixClient,
                            authState: authState
                        )
                        profileImageStore = ProfileImageStore(apiClient: helixClient)
                    }
            }
        }
        .defaultSize(width: 800, height: 700)
    }
}
