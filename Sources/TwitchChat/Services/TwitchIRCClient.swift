// TwitchIRCClient.swift
// Twitch IRC 接続を管理するクライアント
// 匿名接続（justinfan 方式）と認証接続（OAuth トークン）の両方をサポートする

import Foundation

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

    // MARK: - プロパティ

    private let webSocketClient: any WebSocketClientProtocol
    private var messageContinuation: AsyncStream<ChatMessage>.Continuation?
    private var noticeContinuation: AsyncStream<TwitchNotice>.Continuation?
    /// 受信ループのタスク（disconnect() でキャンセルするために保持）
    private var receiveLoopTask: Task<Void, Never>?

    /// 現在 JOIN しているチャンネル名（小文字正規化済み）
    ///
    /// 未接続の場合は nil。PRIVMSG 送信のターゲットとして使用する
    private var joinedChannel: String?

    /// 認証接続（OAuth トークン）かどうか
    ///
    /// true のときのみ PRIVMSG 送信が許可される（匿名接続では false）
    private var isAuthenticated: Bool = false

    /// 受信した ChatMessage を配信する AsyncStream
    let messageStream: AsyncStream<ChatMessage>

    /// サーバーから受信した NOTICE を配信する AsyncStream
    let noticeStream: AsyncStream<TwitchNotice>

    // MARK: - 初期化

    /// TwitchIRCClient を初期化する
    ///
    /// - Parameter webSocketClient: WebSocket クライアント実装（テスト時はモックを注入）
    init(webSocketClient: any WebSocketClientProtocol = URLSessionWebSocketClient()) {
        var msgContinuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { msgContinuation = $0 }
        self.messageContinuation = msgContinuation

        var ntcContinuation: AsyncStream<TwitchNotice>.Continuation?
        self.noticeStream = AsyncStream { ntcContinuation = $0 }
        self.noticeContinuation = ntcContinuation

        self.webSocketClient = webSocketClient
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
        try await webSocketClient.connect(to: Self.websocketURL)
        // 認証接続かどうかを記録してから認証シーケンスを送信
        isAuthenticated = (accessToken != nil && userLogin != nil)
        try await sendAuthSequence(channel: normalizedChannel, accessToken: accessToken, userLogin: userLogin)
        joinedChannel = normalizedChannel
        // receiveLoop を別タスクで起動し、connect() がブロックされないようにする
        receiveLoopTask = Task { await receiveLoop() }
    }

    /// IRC 接続を切断する
    func disconnect() async {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        await webSocketClient.disconnect()
        joinedChannel = nil
        isAuthenticated = false
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
    /// WebSocket からメッセージを連続受信し、IRC メッセージを解析して配信する
    /// 接続が切断されるまでループを継続する
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
                // 切断またはキャンセル時はループ終了
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

        default:
            break
        }
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
