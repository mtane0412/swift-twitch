// TwitchEventSubClient.swift
// Twitch EventSub WebSocket 接続を管理するクライアント
//
// EventSub WebSocket は JSON ベースのプロトコル。IRC クライアントとは異なり、
// Twitch 側からの keepalive メッセージを受信して生存確認する（クライアントから PING しない）。
//
// 主な役割:
// - wss://eventsub.wss.twitch.tv/ws に接続し、Welcome メッセージで session_id を取得する
// - Helix API 経由でサブスクリプションを登録・削除する
// - channel.chat.message イベントを chatMessageEventStream で配信する
// - Reconnect メッセージへの対応および予期せぬ切断時の指数バックオフ再接続
//
// 参考: https://dev.twitch.tv/docs/eventsub/handling-websocket-events/

import Foundation

// MARK: - EventSub 接続状態

/// EventSub クライアントの接続状態
enum EventSubConnectionState: Sendable, Equatable {
    /// 接続済み（session_id 確定済み）
    case connected
    /// 再接続中（指数バックオフでリトライ中）
    case reconnecting(attempt: Int)
    /// 切断済み（意図的な disconnect() 後）
    case disconnected
}

// MARK: - プロトコル

/// Twitch EventSub WebSocket クライアントの抽象化プロトコル
///
/// ChannelManager がこのプロトコルに依存することで、テスト時にモックへの差し替えが可能になる
protocol TwitchEventSubClientProtocol: Actor {
    /// channel.chat.message EventSub イベントを配信する AsyncStream
    var chatMessageEventStream: AsyncStream<EventSubChatEvent> { get }

    /// 接続状態の変化を配信する AsyncStream
    var connectionStateStream: AsyncStream<EventSubConnectionState> { get }

    /// 現在の session_id（テスト検証用）
    var sessionId: String? { get }

    /// EventSub WebSocket に接続する
    func connect() async throws

    /// 接続を切断する
    func disconnect() async

    /// 指定チャンネルの channel.chat.message サブスクリプションを登録する
    ///
    /// - Parameters:
    ///   - broadcasterId: チャンネルオーナーのユーザー ID
    ///   - userId: 認証済みユーザー ID（自分の ID）
    func subscribeChatMessage(broadcasterId: String, userId: String) async throws

    /// 指定チャンネルのサブスクリプションを解除する
    ///
    /// - Parameters:
    ///   - broadcasterId: チャンネルオーナーのユーザー ID（サブスクリプション ID の検索に使用）
    func unsubscribeChatMessage(broadcasterId: String) async throws
}

// MARK: - TwitchEventSubClient

/// Twitch EventSub WebSocket クライアント
///
/// EventSub WebSocket に接続し、channel.chat.message イベントを AsyncStream で配信する。
/// 予期せぬ切断時は指数バックオフで自動再接続する。
actor TwitchEventSubClient: TwitchEventSubClientProtocol {

    // MARK: - 定数

    private static let defaultWebSocketURL = URL(string: "wss://eventsub.wss.twitch.tv/ws")!
    private static let subscriptionsURL = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!

    // MARK: - ストリームプロパティ

    /// channel.chat.message EventSub イベントを配信する AsyncStream
    let chatMessageEventStream: AsyncStream<EventSubChatEvent>

    /// 接続状態の変化を配信する AsyncStream
    let connectionStateStream: AsyncStream<EventSubConnectionState>

    // MARK: - プライベートプロパティ

    private let webSocketClient: any WebSocketClientProtocol
    private let apiClient: any HelixAPIClientProtocol

    private var chatMessageContinuation: AsyncStream<EventSubChatEvent>.Continuation?
    private var connectionStateContinuation: AsyncStream<EventSubConnectionState>.Continuation?

    /// 受信ループタスク
    private var receiveLoopTask: Task<Void, Never>?

    /// 現在の EventSub セッション ID（Helix API でサブスクリプション登録に使用する）
    private(set) var sessionId: String?

    /// 接続先 WebSocket URL（Reconnect メッセージで更新される）
    private var currentWebSocketURL: URL

    /// 意図的切断フラグ
    private var isIntentionallyDisconnected: Bool = false

    /// 現在の再接続試行回数
    private var reconnectAttempt: Int = 0

    /// バックオフ設定
    private let backoffConfig: BackoffConfiguration

    /// JSON デコーダー（snake_case → camelCase 変換）
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// 登録済みサブスクリプション（broadcasterId → subscription_id）
    private var subscriptions: [String: String] = [:]

    // MARK: - 初期化

    /// TwitchEventSubClient を初期化する
    ///
    /// - Parameters:
    ///   - webSocketClient: WebSocket クライアント実装（テスト時はモックを注入）
    ///   - apiClient: Helix API クライアント（サブスクリプション登録に使用）
    ///   - backoffConfig: 指数バックオフ設定（テスト時は `.fastTest` を指定）
    init(
        webSocketClient: any WebSocketClientProtocol = URLSessionWebSocketClient(),
        apiClient: any HelixAPIClientProtocol,
        backoffConfig: BackoffConfiguration = .default
    ) {
        var chatContinuation: AsyncStream<EventSubChatEvent>.Continuation?
        self.chatMessageEventStream = AsyncStream { chatContinuation = $0 }
        self.chatMessageContinuation = chatContinuation

        var stateContinuation: AsyncStream<EventSubConnectionState>.Continuation?
        self.connectionStateStream = AsyncStream { stateContinuation = $0 }
        self.connectionStateContinuation = stateContinuation

        self.webSocketClient = webSocketClient
        self.apiClient = apiClient
        self.backoffConfig = backoffConfig
        self.currentWebSocketURL = Self.defaultWebSocketURL
    }

    // MARK: - 接続・切断

    /// EventSub WebSocket に接続する
    func connect() async throws {
        isIntentionallyDisconnected = false
        reconnectAttempt = 0
        currentWebSocketURL = Self.defaultWebSocketURL

        try await webSocketClient.connect(to: currentWebSocketURL)

        // 受信ループを別タスクで起動
        receiveLoopTask = Task { await receiveLoop() }
    }

    /// EventSub 接続を切断する
    func disconnect() async {
        isIntentionallyDisconnected = true

        receiveLoopTask?.cancel()
        receiveLoopTask = nil

        await webSocketClient.disconnect()
        sessionId = nil

        connectionStateContinuation?.yield(.disconnected)
    }

    // MARK: - サブスクリプション管理

    /// 指定チャンネルの channel.chat.message サブスクリプションを Helix API 経由で登録する
    ///
    /// - Parameters:
    ///   - broadcasterId: チャンネルオーナーのユーザー ID
    ///   - userId: 認証済みユーザー ID（自分の ID）
    /// - Throws: session_id 未取得の場合は `EventSubClientError.sessionIdNotAvailable`
    func subscribeChatMessage(broadcasterId: String, userId: String) async throws {
        guard let sid = sessionId else {
            throw EventSubClientError.sessionIdNotAvailable
        }

        let request = EventSubSubscriptionRequest(
            type: "channel.chat.message",
            version: "1",
            condition: EventSubCondition(broadcasterUserId: broadcasterId, userId: userId),
            transport: EventSubTransport(method: "websocket", sessionId: sid)
        )

        let response: EventSubSubscriptionResponse = try await apiClient.post(
            url: Self.subscriptionsURL,
            queryItems: nil,
            body: request
        )

        // 登録されたサブスクリプション ID を broadcasterId と紐付けて保存する
        if let subscriptionId = response.data.first?.id {
            subscriptions[broadcasterId] = subscriptionId
        }
    }

    /// 指定チャンネルのサブスクリプションを Helix API 経由で解除する
    func unsubscribeChatMessage(broadcasterId: String) async throws {
        guard let subscriptionId = subscriptions[broadcasterId] else { return }

        let queryItems = [URLQueryItem(name: "id", value: subscriptionId)]
        try await apiClient.delete(url: Self.subscriptionsURL, queryItems: queryItems)
        subscriptions.removeValue(forKey: broadcasterId)
    }

    // MARK: - 受信ループ

    /// メッセージ受信ループ
    ///
    /// WebSocket からメッセージを連続受信し、JSON をパースしてイベント種別ごとに処理する。
    /// 予期せぬ切断時はバックオフ付き再接続を試みる。
    private func receiveLoop() async {
        while true {
            do {
                let raw = try await webSocketClient.receive()
                await handleRawMessage(raw)
            } catch {
                if isIntentionallyDisconnected || Task.isCancelled {
                    break
                }
                // 予期せぬ切断 → バックオフ付き再接続
                await performReconnect()
                break
            }
        }
    }

    /// JSON テキストメッセージを解析して処理する
    private func handleRawMessage(_ raw: String) async {
        guard let data = raw.data(using: .utf8),
              let message = try? decoder.decode(EventSubMessage.self, from: data) else {
            return
        }

        switch message.metadata.messageType {
        case .sessionWelcome:
            // session_id を保存して接続成功を通知する
            sessionId = message.payload.session?.id
            connectionStateContinuation?.yield(.connected)

        case .sessionKeepalive:
            // keepalive 受信 → タイムアウトカウントをリセット（現在は受信するだけ）
            break

        case .sessionReconnect:
            // 新しい URL への再接続要求
            // 現在の WebSocket を切断して receiveLoop の catch 経由で再接続する
            if let urlString = message.payload.session?.reconnectUrl,
               let url = URL(string: urlString) {
                currentWebSocketURL = url
            }
            await webSocketClient.disconnect()

        case .notification:
            // channel.chat.message イベントを chatMessageEventStream に配信する
            if let event = message.payload.event {
                chatMessageContinuation?.yield(event)
            }

        case .revocation:
            // サブスクリプション失効 → 該当エントリを subscriptions から削除する
            if let subId = message.payload.subscription?.id {
                subscriptions = subscriptions.filter { $0.value != subId }
            }

        case .unknown:
            break
        }
    }

    // MARK: - 自動再接続

    /// 指数バックオフで再接続を繰り返し試行する
    ///
    /// `receiveLoop()` のエラー catch から呼ばれる時点では WebSocket は既に切断済みのため
    /// ここで改めて disconnect() を呼ばない。
    private func performReconnect() async {
        while !isIntentionallyDisconnected {
            reconnectAttempt += 1
            connectionStateContinuation?.yield(.reconnecting(attempt: reconnectAttempt))

            let delay = computeBackoffDelay(attempt: reconnectAttempt)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            if isIntentionallyDisconnected { return }

            do {
                try await webSocketClient.connect(to: currentWebSocketURL)
                if isIntentionallyDisconnected { await webSocketClient.disconnect(); return }

                // 再接続成功 → 受信ループを再起動する
                // .connected は Welcome メッセージ受信時に yield するため、ここでは yield しない
                reconnectAttempt = 0
                receiveLoopTask = Task { await receiveLoop() }
                return
            } catch {
                // 次のイテレーションで再試行
            }
        }
    }

    /// 指数バックオフ遅延を計算する
    private func computeBackoffDelay(attempt: Int) -> TimeInterval {
        let base = backoffConfig.initialDelay * pow(backoffConfig.multiplier, Double(attempt - 1))
        let capped = min(base, backoffConfig.maxDelay)
        let jitter = capped * backoffConfig.jitterRatio
        return max(0, capped + Double.random(in: -jitter...jitter))
    }
}

// MARK: - エラー

/// TwitchEventSubClient が発生させるエラー
enum EventSubClientError: Error, LocalizedError {
    /// session_id が未取得の状態でサブスクリプション登録を試みた
    case sessionIdNotAvailable

    var errorDescription: String? {
        switch self {
        case .sessionIdNotAvailable:
            return "EventSub の session_id がまだ取得できていません。接続後に再試行してください。"
        }
    }
}
