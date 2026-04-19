// ChannelManager.swift
// 複数チャンネルへの同時接続を管理するオーケストレーター
// チャンネルの参加・退出・選択切替を担当し、各チャンネルの ChatViewModel を保持する

import Foundation
import Observation

/// 複数チャンネル接続を管理するオーケストレーター
///
/// - 各チャンネルに独立した `ChatViewModel` を持つ設計
/// - `joinChannel()` で未接続チャンネルに新規接続、既接続なら選択切替のみ
/// - 接続は明示的に `leaveChannel()` または `disconnectAll()` を呼ぶまで維持される
@Observable
@MainActor
final class ChannelManager {

    // MARK: - 公開プロパティ

    /// 接続中チャンネルの ViewModel（キー: 小文字チャンネル名）
    private(set) var channels: [String: ChatViewModel] = [:]

    /// 接続順を保持する配列（サイドバー表示順）
    private(set) var channelOrder: [String] = []

    /// 現在選択中のチャンネル名
    var selectedChannel: String?

    /// 現在選択中の ChatViewModel
    var selectedViewModel: ChatViewModel? {
        guard let name = selectedChannel else { return nil }
        return channels[name]
    }

    // MARK: - プライベートプロパティ

    private let authState: AuthState
    private let apiClient: any HelixAPIClientProtocol

    /// ログイン時にユーザーエモートを事前取得するストア
    ///
    /// 各チャンネルの `ChatViewModel` が持つ個別のエモートストアとは別に、
    /// アプリ起動・ログイン時にユーザーエモートをフェッチしておくために使用する。
    /// `joinChannel` で新しい `ChatViewModel` を作成する際にスナップショットをシードする
    /// ことで、エモートピッカーが即座に使用可能エモートを表示できるようになる。
    private let preloadEmoteStore: EmoteStore

    /// IRC クライアントファクトリ（テスト時にモックを注入するために使用）
    private let makeIRCClient: @MainActor () -> any TwitchIRCClientProtocol

    /// EventSub WebSocket クライアント（チャンネル横断で共有）
    ///
    /// 最初のチャンネル参加時に生成・接続し、全チャンネル退出後も維持する。
    /// `disconnectAll()` 時に切断する。
    private var eventSubClient: (any TwitchEventSubClientProtocol)?

    /// EventSub クライアントファクトリ（テスト時にモックを注入するために使用）
    private let makeEventSubClient: (@MainActor () -> any TwitchEventSubClientProtocol)?

    /// EventSub 初回接続タスク（disconnectAll() でキャンセルできるように保持）
    private var eventSubConnectTask: Task<Void, Never>?

    /// EventSub イベント受信ループタスク
    private var eventSubReceiveTask: Task<Void, Never>?

    // MARK: - 初期化

    /// ChannelManager を初期化する（本番用）
    ///
    /// - Parameter authState: 認証状態（IRC 接続と Helix API 呼び出しに使用）
    init(authState: AuthState) {
        self.authState = authState
        let helixClient = HelixAPIClient(tokenProvider: authState)
        self.apiClient = helixClient
        self.preloadEmoteStore = EmoteStore(apiClient: helixClient)
        self.makeIRCClient = { TwitchIRCClient() }
        self.makeEventSubClient = { [authState] in
            TwitchEventSubClient(apiClient: HelixAPIClient(tokenProvider: authState))
        }
    }

    /// ChannelManager を初期化する（テスト用: IRC クライアントファクトリを注入）
    ///
    /// - Parameters:
    ///   - authState: 認証状態
    ///   - makeIRCClient: IRC クライアントを生成するファクトリクロージャ
    ///   - makeEventSubClient: EventSub クライアントを生成するファクトリクロージャ（nil で EventSub 無効化）
    ///   - preloadEmoteStore: ユーザーエモートプリロード用ストア（nil の場合はデフォルトを生成）
    init(
        authState: AuthState,
        makeIRCClient: @escaping @MainActor () -> any TwitchIRCClientProtocol,
        makeEventSubClient: (@MainActor () -> any TwitchEventSubClientProtocol)? = nil,
        preloadEmoteStore: EmoteStore? = nil
    ) {
        self.authState = authState
        let helixClient = HelixAPIClient(tokenProvider: authState)
        self.apiClient = helixClient
        self.preloadEmoteStore = preloadEmoteStore ?? EmoteStore(apiClient: helixClient)
        self.makeIRCClient = makeIRCClient
        self.makeEventSubClient = makeEventSubClient
    }

    // MARK: - 公開メソッド

    /// ログイン時・アプリ起動時にユーザーエモートを事前取得する
    ///
    /// プリロードストアでユーザーエモートをフェッチしておくことで、`joinChannel` 呼び出し時に
    /// 新しい `ChatViewModel` のエモートストアへ即座にシードできるようにする。
    /// `user:read:emotes` スコープがない場合や未ログイン時はスキップする。
    ///
    /// `TwitchChatApp` のログイン検知（`.loggedIn` 状態遷移・セッション復元）から呼び出す。
    func preloadUserEmotes() async {
        guard let userId = authState.userId, authState.canReadUserEmotes else { return }
        await preloadEmoteStore.fetchUserEmotes(userId: userId)
    }

    /// 指定チャンネルに参加する
    ///
    /// - 未接続の場合: 新しい `ChatViewModel` を作成して接続開始し、選択状態にする
    /// - 既接続の場合: 接続はそのままで選択状態を切り替えるのみ
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    func joinChannel(_ channelLogin: String) async {
        let normalized = channelLogin.lowercased()

        if channels[normalized] != nil {
            // 既接続 → 選択だけ切り替える
            selectedChannel = normalized
            return
        }

        // 新規接続
        let ircClient = makeIRCClient()
        let viewModel = ChatViewModel(ircClient: ircClient, authState: authState, apiClient: apiClient)

        // プリロード済みユーザーエモートをシードして初回ピッカー表示を高速化する
        // connect() より前にシードすることで、USERSTATE 到着前からエモートが利用可能になる
        let userEmotesSnapshot = await preloadEmoteStore.userEmotesSnapshot()
        if !userEmotesSnapshot.isEmpty {
            await viewModel.emoteStore.setUserEmotes(userEmotesSnapshot)
        }

        channels[normalized] = viewModel
        channelOrder.append(normalized)
        selectedChannel = normalized

        // EventSub クライアントを初期化する（最初のチャンネル参加時のみ接続）
        if eventSubClient == nil, let factory = makeEventSubClient {
            let client = factory()
            eventSubClient = client
            // disconnectAll() でキャンセルできるよう Task 参照を保持する
            eventSubConnectTask = Task {
                do {
                    try await client.connect()
                } catch {
                    // 接続失敗時は eventSubClient をリセットして次回 joinChannel で再生成できるようにする
                    #if DEBUG
                    print("[ChannelManager] EventSub connect 失敗: \(error) — eventSubClient をリセット")
                    #endif
                    eventSubClient = nil
                    return
                }
                guard !Task.isCancelled else { return }
                // EventSub イベント受信ループを起動する
                await startEventSubReceiveLoop(client: client)
            }
        }

        // room-id 確定時に EventSub サブスクリプションを登録するコールバックをセットする
        setupRoomIdConfirmedCallback(for: viewModel, channelName: normalized)

        // バックグラウンドで接続開始（joinChannel がブロックされないように）
        Task {
            await viewModel.connect(to: normalized)
        }
    }

    /// EventSub イベント受信ループを起動する
    ///
    /// 受信したイベントを broadcasterUserLogin からチャンネルを特定し、
    /// 該当する ChatViewModel の handleEventSubChatMessage に振り分ける。
    private func startEventSubReceiveLoop(client: any TwitchEventSubClientProtocol) async {
        eventSubReceiveTask?.cancel()
        // @MainActor クラスのメソッドは MainActor 上で実行されるため、
        // ループ内で self へのアクセスは MainActor により直列化される
        eventSubReceiveTask = Task { [weak self] in
            let stream = await client.chatMessageEventStream
            for await event in stream {
                await self?.routeEventSubChatMessage(event)
            }
        }
    }

    /// EventSub チャットメッセージイベントを対象チャンネルの ChatViewModel に振り分ける
    private func routeEventSubChatMessage(_ event: EventSubChatEvent) {
        let channelName = event.broadcasterUserLogin.lowercased()
        channels[channelName]?.handleEventSubChatMessage(event)
    }

    /// ChatViewModel に room-id 確定コールバックをセットする
    ///
    /// room-id 確定時に EventSub の subscribeChatMessage を呼び出す。
    /// 認証済みユーザーの ID は AuthState から取得する。
    private func setupRoomIdConfirmedCallback(for viewModel: ChatViewModel, channelName: String) {
        viewModel.onRoomIdConfirmed = { [weak self] broadcasterId in
            guard let self else { return }
            Task {
                // subscribeChatMessage には認証済みユーザーの ID が必要
                guard let userId = await self.authState.userId else { return }
                guard let client = await self.eventSubClient else { return }
                do {
                    try await client.subscribeChatMessage(
                        broadcasterId: broadcasterId,
                        userId: userId
                    )
                } catch {
                    // 購読失敗は返信有効化に影響するがアプリは継続できる
                    #if DEBUG
                    print("[ChannelManager] EventSub subscribeChatMessage 失敗 broadcasterId=\(broadcasterId): \(error)")
                    #endif
                }
            }
        }
    }

    /// 指定チャンネルから退出する
    ///
    /// 接続を切断してチャンネルリストから削除する。
    /// 選択中のチャンネルを退出した場合は選択を解除する。
    ///
    /// - Parameter channelLogin: チャンネルのログイン名
    func leaveChannel(_ channelLogin: String) async {
        let normalized = channelLogin.lowercased()

        guard let viewModel = channels[normalized] else { return }

        // room-id が確定済みならサブスクリプションを解除する
        if let broadcasterId = viewModel.currentRoomId {
            do {
                try await eventSubClient?.unsubscribeChatMessage(broadcasterId: broadcasterId)
            } catch {
                // 解除失敗は EventSub の 300 サブスクリプション上限に影響する可能性があるためログに残す
                #if DEBUG
                print("[ChannelManager] EventSub unsubscribeChatMessage 失敗 broadcasterId=\(broadcasterId): \(error)")
                #endif
            }
        }

        await viewModel.disconnect()
        channels.removeValue(forKey: normalized)
        channelOrder.removeAll { $0 == normalized }

        if selectedChannel == normalized {
            selectedChannel = channelOrder.last
        }
    }

    /// 指定チャンネルが既に接続中かどうかを返す
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    /// - Returns: 接続中なら `true`、未接続なら `false`
    func isJoined(_ channelLogin: String) -> Bool {
        channels[channelLogin.lowercased()] != nil
    }

    /// 既接続チャンネルを選択状態にする（同期）
    ///
    /// 未接続チャンネルを指定した場合は何もしない。
    /// `joinChannel(_:)` は未接続時に新規接続を開始するが、このメソッドは選択切替のみ行う。
    /// サイドバーのアイコンクリックやタブバーのタブクリックから呼ぶことを想定している。
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    func selectChannel(_ channelLogin: String) {
        let normalized = channelLogin.lowercased()
        guard channels[normalized] != nil else { return }
        selectedChannel = normalized
    }

    /// 指定チャンネルを目的のインデックス位置に移動する
    ///
    /// - 未知のチャンネル名は no-op（クラッシュしない）
    /// - `destinationIndex` は `0...(channelOrder.count - 1)` の範囲に clamp する
    /// - 元の位置と同じ index への移動は no-op（不要な再描画を防ぐ）
    /// - `selectedChannel` は名前ベース管理のため並び替え後も変更不要
    ///
    /// - Parameters:
    ///   - channelLogin: 移動するチャンネル名（大文字小文字は自動正規化）
    ///   - destinationIndex: 移動先のインデックス
    func moveChannel(_ channelLogin: String, toIndex destinationIndex: Int) {
        let normalized = channelLogin.lowercased()
        guard let currentIndex = channelOrder.firstIndex(of: normalized) else { return }
        let clamped = min(max(destinationIndex, 0), channelOrder.count - 1)
        guard currentIndex != clamped else { return }
        let removed = channelOrder.remove(at: currentIndex)
        channelOrder.insert(removed, at: clamped)
    }

    /// 全チャンネルから切断して管理状態をリセットする
    func disconnectAll() async {
        let allChannels = channelOrder
        for channel in allChannels {
            if let viewModel = channels[channel] {
                await viewModel.disconnect()
            }
        }
        channels = [:]
        channelOrder = []
        selectedChannel = nil

        // EventSub クライアントを切断してリソースを解放する
        eventSubConnectTask?.cancel()
        eventSubConnectTask = nil
        eventSubReceiveTask?.cancel()
        eventSubReceiveTask = nil
        if let client = eventSubClient {
            await client.disconnect()
        }
        eventSubClient = nil

        // プリロードストアをリセットして次回ログイン時に再フェッチできるようにする
        await preloadEmoteStore.cancelUserEmotesFetch()
        await preloadEmoteStore.resetUserEmotes()
    }
}
