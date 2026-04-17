// TwitchIRCClient.swift
// Twitch IRC 接続を管理するクライアント
// 匿名接続（justinfan 方式）と認証接続（OAuth トークン）の両方をサポートする
// 予期せぬ切断時は指数バックオフで自動再接続する

import Foundation

// MARK: - 接続状態

/// IRC クライアントの接続状態
///
/// `TwitchIRCClientProtocol.connectionStateStream` で配信される。
/// ViewModel はこのストリームを購読して UI 上の接続状態インジケータを更新する。
enum ClientConnectionState: Sendable, Equatable {
    /// 接続済み（初回接続・再接続成功の両方）
    case connected
    /// 再接続中（指数バックオフでリトライ中）
    ///
    /// - Parameter attempt: 現在の再接続試行回数（1 始まり）
    case reconnecting(attempt: Int)
    /// 切断済み（意図的な disconnect() 後）
    case disconnected
}

// MARK: - バックオフ設定

/// 指数バックオフの設定
///
/// テスト時は `.fastTest` を注入して待機時間を短縮できる
struct BackoffConfiguration: Sendable {
    /// 初回遅延（秒）
    let initialDelay: TimeInterval
    /// 最大遅延（秒）
    let maxDelay: TimeInterval
    /// 遅延を増加させる倍率
    let multiplier: Double
    /// ジッタ率（0.0 〜 1.0）。計算遅延の ±jitterRatio 分がランダムに加減算される
    let jitterRatio: Double

    /// 本番環境向けデフォルト設定（1s → 2s → 4s → … 最大 60s、±20% ジッタ）
    static let `default` = BackoffConfiguration(
        initialDelay: 1.0, maxDelay: 60.0, multiplier: 2.0, jitterRatio: 0.2
    )

    /// テスト用の極小バックオフ（即時再接続、ジッタなし）
    static let fastTest = BackoffConfiguration(
        initialDelay: 0.01, maxDelay: 0.05, multiplier: 2.0, jitterRatio: 0.0
    )
}

// MARK: - PING keepalive 設定

/// 能動的 PING keepalive の設定
///
/// テスト時は間隔・タイムアウトを短縮した設定を注入して検証を高速化できる
struct PingConfiguration: Sendable {
    /// PING 送信間隔（秒）
    let interval: TimeInterval
    /// PONG 受信猶予（秒）。interval + timeout を過ぎても PONG が来なければタイムアウト扱い
    let timeout: TimeInterval

    /// 本番環境向けデフォルト設定（60 秒ごとに送信、30 秒で PONG タイムアウト）
    static let `default` = PingConfiguration(interval: 60.0, timeout: 30.0)

    /// テスト用の極小設定（即タイムアウト）
    static let fastTest = PingConfiguration(interval: 0.05, timeout: 0.05)
}

// MARK: - プロトコル

/// Twitch IRC クライアントの抽象化プロトコル
///
/// ViewModel がこのプロトコルに依存することで、テスト時にモックへの差し替えが可能になる
protocol TwitchIRCClientProtocol: Actor {
    /// 受信した ChatMessage を配信する AsyncStream
    var messageStream: AsyncStream<ChatMessage> { get }

    /// サーバーから受信した NOTICE を配信する AsyncStream
    ///
    /// レートリミット超過・BAN・スローモードなどのエラー通知が流れる。
    /// `CAP REQ :twitch.tv/commands` が有効な場合のみ `msg-id` タグ付きで届く。
    var noticeStream: AsyncStream<TwitchNotice> { get }

    /// 接続状態の変化を配信する AsyncStream
    ///
    /// `.connected` / `.reconnecting(attempt:)` / `.disconnected` を順に yield する。
    /// ViewModel はこれを購読して UI の接続インジケータを更新する。
    var connectionStateStream: AsyncStream<ClientConnectionState> { get }

    /// 指定チャンネルに接続する
    ///
    /// - Parameters:
    ///   - channel: チャンネル名（`#` なし）
    ///   - accessToken: OAuth アクセストークン（省略時は匿名接続）
    ///   - userLogin: ログインユーザー名（`accessToken` 指定時に必要）
    func connect(to channel: String, accessToken: String?, userLogin: String?) async throws

    /// IRC 接続を切断する
    func disconnect() async

    /// 接続中チャンネルに PRIVMSG を送信する
    ///
    /// - Parameter text: 送信する本文（呼び出し元でサニタイズ済みである前提）
    /// - Throws: `.notConnected`（未接続）、`.notAuthenticated`（匿名接続中）
    func sendPrivmsg(_ text: String) async throws
}

// MARK: - TwitchIRCClient

/// Twitch IRC クライアント
///
/// Twitch IRC WebSocket サーバーに匿名接続し、チャットメッセージを AsyncStream で配信する
///
/// 使用例:
/// ```swift
/// let client = TwitchIRCClient()
/// for await message in await client.messageStream {
///     print(message.displayName, message.text)
/// }
/// try await client.connect(to: "channelname")
/// ```
actor TwitchIRCClient: TwitchIRCClientProtocol {
    // MARK: - 定数

    private static let websocketURL = URL(string: "wss://irc-ws.chat.twitch.tv:443")!

    /// 匿名接続で使用するパスワード（Twitch IRC 仕様による固定値）
    private static let anonymousPassword = "SCHMOOPIIE"

    /// 匿名接続で使用するニックネーム
    private static let anonymousNick = "justinfan12345"

    // MARK: - ストリームプロパティ

    /// 受信した ChatMessage を配信する AsyncStream
    let messageStream: AsyncStream<ChatMessage>

    /// サーバーから受信した NOTICE を配信する AsyncStream
    let noticeStream: AsyncStream<TwitchNotice>

    /// 接続状態の変化を配信する AsyncStream
    let connectionStateStream: AsyncStream<ClientConnectionState>

    // MARK: - プライベートプロパティ

    private let webSocketClient: any WebSocketClientProtocol
    private var messageContinuation: AsyncStream<ChatMessage>.Continuation?
    private var noticeContinuation: AsyncStream<TwitchNotice>.Continuation?
    private var connectionStateContinuation: AsyncStream<ClientConnectionState>.Continuation?

    /// 受信ループのタスク（disconnect() でキャンセルするために保持）
    private var receiveLoopTask: Task<Void, Never>?

    /// PING keepalive タイマータスク
    private var pingKeepaliveTask: Task<Void, Never>?

    /// 最終 PONG 受信時刻（keepalive タイムアウト検知用）
    private var lastPongAt: Date?

    /// 現在 JOIN しているチャンネル名（小文字正規化済み）
    ///
    /// 未接続の場合は nil。PRIVMSG 送信のターゲットとして使用する
    private var joinedChannel: String?

    /// 認証接続（OAuth トークン）かどうか
    ///
    /// true のときのみ PRIVMSG 送信が許可される（匿名接続では false）
    private var isAuthenticated: Bool = false

    /// 再接続用に保持する接続引数
    private var lastChannel: String?
    private var lastAccessToken: String?
    private var lastUserLogin: String?

    /// 意図的切断フラグ
    ///
    /// `disconnect()` で true にセットし、`connect()` で false にリセットする。
    /// receiveLoop の catch ではこのフラグが false のときのみ再接続を行う。
    private var isIntentionallyDisconnected: Bool = true

    /// 現在の再接続試行回数（初回接続時は 0、再接続のたびに +1）
    private var reconnectAttempt: Int = 0

    /// バックオフ設定
    private let backoffConfig: BackoffConfiguration

    /// PING keepalive 設定
    private let pingConfig: PingConfiguration

    // MARK: - 初期化

    /// TwitchIRCClient を初期化する
    ///
    /// - Parameters:
    ///   - webSocketClient: WebSocket クライアント実装（テスト時はモックを注入）
    ///   - backoffConfig: 指数バックオフ設定（テスト時は `.fastTest` を指定して待機を短縮）
    ///   - pingConfig: PING keepalive 設定（テスト時は `.fastTest` を指定）
    init(
        webSocketClient: any WebSocketClientProtocol = URLSessionWebSocketClient(),
        backoffConfig: BackoffConfiguration = .default,
        pingConfig: PingConfiguration = .default
    ) {
        var msgContinuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { msgContinuation = $0 }
        self.messageContinuation = msgContinuation

        var ntcContinuation: AsyncStream<TwitchNotice>.Continuation?
        self.noticeStream = AsyncStream { ntcContinuation = $0 }
        self.noticeContinuation = ntcContinuation

        var stateContinuation: AsyncStream<ClientConnectionState>.Continuation?
        self.connectionStateStream = AsyncStream { stateContinuation = $0 }
        self.connectionStateContinuation = stateContinuation

        self.webSocketClient = webSocketClient
        self.backoffConfig = backoffConfig
        self.pingConfig = pingConfig
    }

    // MARK: - 接続・切断

    /// 指定チャンネルに接続する
    ///
    /// - Parameters:
    ///   - channel: チャンネル名（`#` なし、大文字小文字は自動変換）
    ///   - accessToken: OAuth アクセストークン（省略時は匿名接続）
    ///   - userLogin: ログインユーザー名（`accessToken` 指定時に必要）
    /// - Throws: WebSocket 接続エラー
    func connect(to channel: String, accessToken: String? = nil, userLogin: String? = nil) async throws {
        let normalizedChannel = channel.lowercased()

        // 再接続用に引数を保持する
        lastChannel = normalizedChannel
        lastAccessToken = accessToken
        lastUserLogin = userLogin

        // 意図的切断フラグをクリアし、試行回数をリセットする
        isIntentionallyDisconnected = false
        reconnectAttempt = 0

        try await webSocketClient.connect(to: Self.websocketURL)
        // 認証接続かどうかを記録してから認証シーケンスを送信
        isAuthenticated = (accessToken != nil && userLogin != nil)
        try await sendAuthSequence(channel: normalizedChannel, accessToken: accessToken, userLogin: userLogin)
        joinedChannel = normalizedChannel

        // 接続成功を通知
        connectionStateContinuation?.yield(.connected)

        // PING keepalive タイマーを開始
        startPingKeepalive()

        // receiveLoop を別タスクで起動し、connect() がブロックされないようにする
        receiveLoopTask = Task { await receiveLoop() }
    }

    /// IRC 接続を切断する
    func disconnect() async {
        // 意図的切断フラグを立てて再接続を抑止する
        isIntentionallyDisconnected = true

        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        stopPingKeepalive()

        await webSocketClient.disconnect()
        joinedChannel = nil
        isAuthenticated = false
        lastChannel = nil
        lastAccessToken = nil
        lastUserLogin = nil

        // 切断状態を通知
        connectionStateContinuation?.yield(.disconnected)
        // messageContinuation?.finish() を呼ばない → 再接続時に同じストリームを再利用できる
    }

    /// 接続中チャンネルに PRIVMSG を送信する
    ///
    /// - Parameter text: 送信する本文（呼び出し元でサニタイズ済みである前提）
    /// - Throws: `.notConnected`（未接続）、`.notAuthenticated`（匿名接続中）
    func sendPrivmsg(_ text: String) async throws {
        guard let channel = joinedChannel else {
            throw TwitchIRCClientError.notConnected
        }
        guard isAuthenticated else {
            throw TwitchIRCClientError.notAuthenticated
        }
        try await webSocketClient.send("PRIVMSG #\(channel) :\(text)")
    }

    // MARK: - プライベートメソッド

    /// 認証シーケンスを送信する
    ///
    /// Twitch IRC に接続するために必要な初期コマンドを順番に送信する
    ///
    /// - Parameters:
    ///   - channel: 接続するチャンネル名（小文字）
    ///   - accessToken: OAuth アクセストークン（`nil` の場合は匿名接続）
    ///   - userLogin: ログインユーザー名（`accessToken` 指定時に使用）
    private func sendAuthSequence(channel: String, accessToken: String?, userLogin: String?) async throws {
        switch (accessToken, userLogin) {
        case let (.some(token), .some(login)):
            // 認証接続: PASS oauth:<token> + NICK <userLogin>
            try await webSocketClient.send("PASS oauth:\(token)")
            try await webSocketClient.send("NICK \(login)")
        case (.none, .none):
            // 匿名接続: justinfan 方式（読み取り専用）
            try await webSocketClient.send("PASS \(Self.anonymousPassword)")
            try await webSocketClient.send("NICK \(Self.anonymousNick)")
        default:
            // 片方だけ指定された不整合状態は早期失敗させる
            throw TwitchIRCClientError.invalidAuthParameters
        }
        try await webSocketClient.send("CAP REQ :twitch.tv/tags twitch.tv/commands")
        try await webSocketClient.send("JOIN #\(channel)")
    }

    /// メッセージ受信ループ
    ///
    /// WebSocket からメッセージを連続受信し、IRC メッセージを解析して配信する。
    /// 予期せぬ切断（意図的切断・タスクキャンセル以外）が発生した場合は
    /// `performReconnect()` を呼んでバックオフ付き再接続を試みる。
    private func receiveLoop() async {
        while true {
            do {
                let raw = try await webSocketClient.receive()
                // 複数メッセージが改行で連結されて届くことがあるため分割して処理
                let lines = raw.components(separatedBy: "\r\n").filter { !$0.isEmpty }
                for line in lines {
                    await handleLine(line)
                }
            } catch {
                // 意図的切断またはタスクキャンセル時はループ終了（再接続しない）
                // Task.isCancelled は receiveLoopTask?.cancel() で立つフラグ。
                // webSocketClient.disconnect() が CancellationError を throw しても
                // Task.isCancelled は立たないため、RECONNECT / PING タイムアウト起因の
                // 切断を正しく再接続パスに誘導できる。
                if isIntentionallyDisconnected || Task.isCancelled {
                    break
                }
                // 予期せぬ切断 → バックオフ付き再接続を試みる
                await performReconnect()
                break
            }
        }
    }

    /// 1 行の IRC メッセージを処理する
    private func handleLine(_ line: String) async {
        guard let ircMessage = IRCMessageParser.parse(line) else { return }

        switch ircMessage.command {
        case "PING":
            // PING に対して PONG を返してコネクションを維持する
            let server = ircMessage.trailing ?? "tmi.twitch.tv"
            try? await webSocketClient.send("PONG :\(server)")

        case "PONG":
            // keepalive の PONG 受信時刻を更新してタイムアウトをリセットする
            lastPongAt = Date()

        case "PRIVMSG":
            // チャットメッセージを ChatMessage に変換して配信
            if let chatMessage = ChatMessage(from: ircMessage) {
                messageContinuation?.yield(chatMessage)
            }

        case "NOTICE":
            // サーバーからの通知（レートリミット・BAN・スローモードなど）を配信
            // params[0] は "#channel" 形式または "*"（サーバー全体通知）。
            // "#" プレフィックスを持つ場合のみ除去する。"*" などは nil にする。
            let channel = ircMessage.params.first.flatMap { raw in
                raw.hasPrefix("#") ? String(raw.dropFirst()) : nil
            }
            let notice = TwitchNotice(
                msgId: ircMessage.tags["msg-id"],
                channel: channel,
                message: ircMessage.trailing ?? ""
            )
            noticeContinuation?.yield(notice)

        case "RECONNECT":
            // Twitch サーバーがメンテナンス等で再接続を要求してきた場合
            // webSocketClient を切断して receiveLoop の catch 経由でバックオフ再接続する
            // （isIntentionallyDisconnected は立てないため再接続が走る）
            await webSocketClient.disconnect()

        default:
            break
        }
    }

    // MARK: - 自動再接続

    /// 指数バックオフで再接続を繰り返し試行する
    ///
    /// `isIntentionallyDisconnected` が false の間、バックオフ遅延を増やしながら
    /// WebSocket 再接続と認証シーケンスの再送を試みる。
    /// 成功したら `receiveLoop` と PING keepalive を再起動する。
    private func performReconnect() async {
        guard !isIntentionallyDisconnected, let channel = lastChannel else { return }

        stopPingKeepalive()
        await webSocketClient.disconnect() // 念のため既存接続を閉じる

        while !isIntentionallyDisconnected {
            reconnectAttempt += 1
            connectionStateContinuation?.yield(.reconnecting(attempt: reconnectAttempt))

            let delay = computeBackoffDelay(attempt: reconnectAttempt)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                // キャンセル時は終了
                return
            }

            if isIntentionallyDisconnected { return }

            do {
                try await webSocketClient.connect(to: Self.websocketURL)
                isAuthenticated = (lastAccessToken != nil && lastUserLogin != nil)
                try await sendAuthSequence(
                    channel: channel,
                    accessToken: lastAccessToken,
                    userLogin: lastUserLogin
                )
                // 再接続成功
                reconnectAttempt = 0
                joinedChannel = channel
                connectionStateContinuation?.yield(.connected)
                receiveLoopTask = Task { await receiveLoop() }
                startPingKeepalive()
                return
            } catch {
                // 次のイテレーションで再試行（バックオフ増加）
            }
        }
    }

    /// 指数バックオフ遅延を計算する
    ///
    /// - Parameter attempt: 試行回数（1 始まり）
    /// - Returns: 遅延秒数（上限 `maxDelay`、±`jitterRatio` のジッタ付き）
    private func computeBackoffDelay(attempt: Int) -> TimeInterval {
        let base = backoffConfig.initialDelay * pow(backoffConfig.multiplier, Double(attempt - 1))
        let capped = min(base, backoffConfig.maxDelay)
        let jitter = capped * backoffConfig.jitterRatio
        return capped + Double.random(in: -jitter...jitter)
    }

    // MARK: - PING keepalive

    /// 能動的 PING keepalive タイマーを開始する
    ///
    /// `pingConfig.interval` ごとに PING を送信し、PONG が来なければ
    /// `interval + timeout` 経過でタイムアウトとして WebSocket を切断する。
    private func startPingKeepalive() {
        stopPingKeepalive()
        lastPongAt = Date() // 接続直後は「今 PONG が来た」と同等に扱う
        // pingConfig.interval を actor コンテキスト内でキャプチャしてから Task に渡す
        let intervalNs = UInt64(pingConfig.interval * 1_000_000_000)
        pingKeepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                if Task.isCancelled { break }
                await self?.performKeepalivePing()
            }
        }
    }

    /// keepalive タイマーを停止する
    private func stopPingKeepalive() {
        pingKeepaliveTask?.cancel()
        pingKeepaliveTask = nil
    }

    /// keepalive 用の PING を送信し、PONG タイムアウトを検知する
    ///
    /// `lastPongAt` から `interval + timeout` 秒以上経過していれば、
    /// ゾンビ接続とみなして webSocketClient を切断する（→ receiveLoop の catch → 再接続）。
    private func performKeepalivePing() async {
        if let last = lastPongAt,
           Date().timeIntervalSince(last) > pingConfig.interval + pingConfig.timeout {
            // PONG タイムアウト → 切断して receiveLoop の catch 経由で再接続をトリガー
            await webSocketClient.disconnect()
            return
        }
        try? await webSocketClient.send("PING :tmi.twitch.tv")
    }
}

// MARK: - エラー定義

/// TwitchIRCClient のエラー
enum TwitchIRCClientError: Error, LocalizedError {
    /// accessToken と userLogin の指定が不整合（片方のみ指定された場合）
    case invalidAuthParameters

    /// 未接続状態で送信しようとした場合（connect() 前、または disconnect() 後）
    case notConnected

    /// 匿名接続中に PRIVMSG 送信しようとした場合（コメント投稿には認証接続が必要）
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidAuthParameters:
            return "accessToken と userLogin はどちらも指定するか、どちらも省略してください"
        case .notConnected:
            return "チャンネルに接続していません"
        case .notAuthenticated:
            return "コメントの投稿にはログインが必要です"
        }
    }
}
