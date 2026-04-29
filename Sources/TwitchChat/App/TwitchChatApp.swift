// TwitchChatApp.swift
// アプリケーションのエントリポイント
// SwiftUI の App プロトコルに準拠し、メインウィンドウを定義する

import os.log
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
    /// プレイヤーの音量（次回起動時に復元するため UserDefaults に永続化）
    @AppStorage(AppStorageKeys.playerVolume) private var storedVolume: Double = 1.0
    /// プレイヤーのミュート状態（次回起動時に復元するため UserDefaults に永続化）
    @AppStorage(AppStorageKeys.playerMuted) private var storedMuted: Bool = false
    /// ライブ配信プレイヤー ViewModel（アプリ起動時に生成、チャンネル全体で共有）
    @State private var streamPlayer = StreamPlayerViewModel()

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
                    profileImageStore: profileImageStore,
                    streamPlayer: streamPlayer
                )
                .onAppear {
                    // 初回表示時のみ永続化済み音量・ミュートを適用する（2 回目以降は無視）
                    streamPlayer.restoreSettingsIfNeeded(
                        volume: Float(storedVolume),
                        muted: storedMuted
                    )
                }
                .task {
                    await authState.restoreSession()
                    if case .loggedIn = authState.status {
                        followedStreamStore.startAutoRefresh()
                        // ユーザーエモートをプリロードし、完了後に ownerId の表示名を事前キャッシュする
                        Task {
                            await channelManager.preloadUserEmotes()
                            await channelManager.preloadEmoteOwnerDisplayNames(using: profileImageStore)
                        }
                        await followedChannelStore.fetchAll()
                    }
                }
                .onChange(of: authState.status) { _, newStatus in
                    switch newStatus {
                    case .loggedIn:
                        followedStreamStore.startAutoRefresh()
                        Task {
                            await channelManager.preloadUserEmotes()
                            await channelManager.preloadEmoteOwnerDisplayNames(using: profileImageStore)
                        }
                        Task { await followedChannelStore.fetchAll() }
                    case .loggedOut:
                        followedStreamStore.stopAutoRefresh()
                        followedStreamStore.clear()
                        followedChannelStore.clear()
                        profileImageStore.clear()
                        Task {
                            await channelManager.disconnectAll()
                            await channelManager.clearPersistedUserData()
                        }
                    case .unknown:
                        break
                    }
                }
            } else {
                ProgressView("起動中...")
                    .onAppear {
                        let helixClient = HelixAPIClient(tokenProvider: authState)
                        let persistenceContainer: PersistenceContainer
                        do {
                            persistenceContainer = try PersistenceContainer.makeOnDisk()
                        } catch {
                            Logger(subsystem: "dev.mtane.TwitchChat", category: "Persistence")
                                .error("makeOnDisk 失敗、InMemory にフォールバック: \(error.localizedDescription)")
                            persistenceContainer = .makeInMemory()
                        }
                        channelManager = ChannelManager(
                            authState: authState,
                            persistenceService: persistenceContainer.service
                        )
                        followedStreamStore = FollowedStreamStore(
                            apiClient: helixClient,
                            authState: authState
                        )
                        followedChannelStore = FollowedChannelStore(
                            apiClient: helixClient,
                            authState: authState
                        )
                        profileImageStore = ProfileImageStore(
                            apiClient: helixClient,
                            persistenceService: persistenceContainer.service
                        )
                        // 3 ImageCache に L2 ディスクキャッシュを注入する
                        EmoteImageCache.shared.attachPersistence(persistenceContainer.service)
                        BadgeImageCache.shared.attachPersistence(persistenceContainer.service)
                        ProfileImageCache.shared.attachPersistence(persistenceContainer.service)
                    }
            }
        }
        .defaultSize(width: 800, height: 700)
        // streamPlayer の音量・ミュート変更を UserDefaults に書き戻す（永続化）
        .onChange(of: streamPlayer.volume) { _, newValue in
            storedVolume = Double(newValue)
        }
        .onChange(of: streamPlayer.isMuted) { _, newValue in
            storedMuted = newValue
        }

        Settings {
            SettingsView()
        }
    }
}
