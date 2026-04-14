// TwitchIRCClient.swift
// Twitch IRC 接続を管理するクライアント
// 匿名接続（justinfan 方式）で Twitch チャットを読み取り専用で受信する

import Foundation

/// Twitch IRC クライアントの抽象化プロトコル
///
/// ViewModel がこのプロトコルに依存することで、テスト時にモックへの差し替えが可能になる
protocol TwitchIRCClientProtocol: Actor {
    /// 受信した ChatMessage を配信する AsyncStream
    var messageStream: AsyncStream<ChatMessage> { get }

    /// 指定チャンネルに接続する
    func connect(to channel: String) async throws

    /// IRC 接続を切断する
    func disconnect() async
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
    private static let anonymousPassword = "SCHMOOPIIE"
    private static let anonymousNick = "justinfan12345"

    // MARK: - プロパティ

    private let webSocketClient: any WebSocketClientProtocol
    private var messageContinuation: AsyncStream<ChatMessage>.Continuation?
    /// 受信ループのタスク（disconnect() でキャンセルするために保持）
    private var receiveLoopTask: Task<Void, Never>?

    /// 受信した ChatMessage を配信する AsyncStream
    let messageStream: AsyncStream<ChatMessage>

    // MARK: - 初期化

    /// TwitchIRCClient を初期化する
    ///
    /// - Parameter webSocketClient: WebSocket クライアント実装（テスト時はモックを注入）
    init(webSocketClient: any WebSocketClientProtocol = URLSessionWebSocketClient()) {
        var continuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { continuation = $0 }
        self.messageContinuation = continuation
        self.webSocketClient = webSocketClient
    }

    // MARK: - 接続・切断

    /// 指定チャンネルに接続する
    ///
    /// - Parameter channel: チャンネル名（`#` なし、大文字小文字は自動変換）
    /// - Throws: WebSocket 接続エラー
    func connect(to channel: String) async throws {
        let normalizedChannel = channel.lowercased()
        try await webSocketClient.connect(to: Self.websocketURL)
        try await sendAuthSequence(channel: normalizedChannel)
        // receiveLoop を別タスクで起動し、connect() がブロックされないようにする
        receiveLoopTask = Task { await receiveLoop() }
    }

    /// IRC 接続を切断する
    func disconnect() async {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        await webSocketClient.disconnect()
        // messageContinuation?.finish() を呼ばない → 再接続時に同じストリームを再利用できる
    }

    // MARK: - プライベートメソッド

    /// 匿名認証シーケンスを送信する
    ///
    /// Twitch IRC に接続するために必要な初期コマンドを順番に送信する
    private func sendAuthSequence(channel: String) async throws {
        try await webSocketClient.send("PASS \(Self.anonymousPassword)")
        try await webSocketClient.send("NICK \(Self.anonymousNick)")
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

        default:
            break
        }
    }
}
