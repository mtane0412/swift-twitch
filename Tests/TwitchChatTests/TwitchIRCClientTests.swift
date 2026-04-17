// TwitchIRCClientTests.swift
// TwitchIRCClient の単体テスト
// MockWebSocketClient を使用してネットワーク通信なしで IRC プロトコルを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - モック

/// テスト用の WebSocket クライアントモック
///
/// 実際のネットワーク通信なしに送受信メッセージを制御する
actor MockWebSocketClient: WebSocketClientProtocol {
    /// 送信されたメッセージのログ
    private(set) var sentMessages: [String] = []

    /// 受信待ちのメッセージキュー
    private var receivableMessages: [String] = []

    /// 接続済みフラグ
    private(set) var isConnected = false

    /// connect(to:) の呼び出し回数（再接続検証用）
    private(set) var connectCallCount = 0

    /// 受信を待機する継続
    private var pendingReceiveContinuations: [CheckedContinuation<String, Error>] = []

    /// 次の receive() で throw するエラーのキュー
    private var scheduledErrors: [any Error] = []

    func connect(to url: URL) async throws {
        connectCallCount += 1
        isConnected = true
    }

    func send(_ message: String) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> String {
        // 予約エラーがあれば throw する
        if !scheduledErrors.isEmpty {
            throw scheduledErrors.removeFirst()
        }
        // キューにメッセージがあれば即返す
        if !receivableMessages.isEmpty {
            return receivableMessages.removeFirst()
        }
        // なければ待機
        return try await withCheckedThrowingContinuation { continuation in
            pendingReceiveContinuations.append(continuation)
        }
    }

    func disconnect() async {
        isConnected = false
        if pendingReceiveContinuations.isEmpty {
            // receive() が待機中でない（メッセージ処理中に disconnect が呼ばれた）場合、
            // 次の receive() で切断エラーを返すよう予約する。
            // RECONNECT コマンド処理からの disconnect() で再接続ループを正しく起動するために必要。
            scheduledErrors.insert(CancellationError(), at: 0)
        } else {
            // 待機中の継続をすべてキャンセル
            for continuation in pendingReceiveContinuations {
                continuation.resume(throwing: CancellationError())
            }
            pendingReceiveContinuations.removeAll()
        }
    }

    /// 受信メッセージをモックに追加する（テスト用）
    func enqueueMessage(_ message: String) {
        if let continuation = pendingReceiveContinuations.first {
            pendingReceiveContinuations.removeFirst()
            continuation.resume(returning: message)
        } else {
            receivableMessages.append(message)
        }
    }

    /// 次の receive() でエラーを throw するように予約する（予期せぬ切断のシミュレーション用）
    func throwOnNextReceive(_ error: any Error) {
        if let continuation = pendingReceiveContinuations.first {
            // 既に receive() で待機中なら即時エラー
            pendingReceiveContinuations.removeFirst()
            continuation.resume(throwing: error)
        } else {
            scheduledErrors.append(error)
        }
    }
}

// MARK: - テスト

/// TwitchIRCClient のテストスイート
@Suite("TwitchIRCClient テスト")
struct TwitchIRCClientTests {

    // MARK: - 接続シーケンス

    @Test("接続時に正しい IRC コマンドが送信される（匿名）")
    func 接続時に正しいIRCコマンドが送信される() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // チャンネル接続（接続後すぐ切断して送信メッセージだけ確認）
        let task = Task {
            try await client.connect(to: "testchannel", accessToken: nil, userLogin: nil)
        }
        // 少し待ってから切断
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        await client.disconnect()
        task.cancel()

        let sent = await mockWS.sentMessages
        // 接続シーケンスに必要なコマンドが含まれていることを確認
        #expect(sent.contains("PASS SCHMOOPIIE"))
        #expect(sent.contains("NICK justinfan12345"))
        #expect(sent.contains("CAP REQ :twitch.tv/tags twitch.tv/commands"))
        #expect(sent.contains("JOIN #testchannel"))
    }

    @Test("チャンネル名は小文字に変換して JOIN する")
    func チャンネル名は小文字に変換してJOINする() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        let task = Task {
            try await client.connect(to: "TestChannel", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.disconnect()
        task.cancel()

        let sent = await mockWS.sentMessages
        #expect(sent.contains("JOIN #testchannel"))
    }

    @Test("アクセストークン指定時は認証接続コマンドが送信される")
    func アクセストークン指定時は認証接続コマンドが送信される() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 認証接続
        let task = Task {
            try await client.connect(to: "testchannel", accessToken: "テスト用トークン123", userLogin: "テスト配信者")
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.disconnect()
        task.cancel()

        let sent = await mockWS.sentMessages
        // OAuth 認証コマンドが送信されることを確認
        #expect(sent.contains("PASS oauth:テスト用トークン123"))
        #expect(sent.contains("NICK テスト配信者"))
        // 匿名コマンドは送信されないことを確認
        #expect(!sent.contains("PASS SCHMOOPIIE"))
        #expect(!sent.contains("NICK justinfan12345"))
    }

    // MARK: - PING/PONG

    @Test("PING 受信時に PONG を返す")
    func PING受信時にPONGを返す() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 接続後 PING を送り込む
        await mockWS.enqueueMessage("PING :tmi.twitch.tv")

        let task = Task {
            try await client.connect(to: "testchannel")
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        await client.disconnect()
        task.cancel()

        let sent = await mockWS.sentMessages
        #expect(sent.contains("PONG :tmi.twitch.tv"))
    }

    // MARK: - メッセージ受信

    @Test("PRIVMSG 受信時に ChatMessage が AsyncStream に流れる")
    func PRIVMSG受信時にChatMessageがAsyncStreamに流れる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // テストメッセージを事前にキュー
        let rawMessage = "@badges=;color=#FF0000;display-name=テストユーザー;emotes=;id=test-id;user-id=12345 :testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #testchannel :こんにちはテストです"
        await mockWS.enqueueMessage(rawMessage)

        var receivedMessages: [ChatMessage] = []
        let stream = await client.messageStream

        let connectTask = Task {
            try await client.connect(to: "testchannel")
        }

        // 最初のメッセージを受信する
        for await message in stream {
            receivedMessages.append(message)
            break // 1件受信したら終了
        }

        await client.disconnect()
        connectTask.cancel()

        #expect(receivedMessages.count == 1)
        #expect(receivedMessages[0].displayName == "テストユーザー")
        #expect(receivedMessages[0].text == "こんにちはテストです")
        #expect(receivedMessages[0].colorHex == "#FF0000")
    }

    // MARK: - PRIVMSG 送信

    @Test("認証接続後に sendPrivmsg を呼ぶと正しいフォーマットで送信される")
    func 認証接続後にsendPrivmsgを呼ぶと正しいフォーマットで送信される() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 認証接続でチャンネルに参加
        let connectTask = Task {
            try await client.connect(to: "haishinshaA", accessToken: "テスト用トークン", userLogin: "視聴者001")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 検証: sendPrivmsg を呼ぶと PRIVMSG コマンドが送信される（チャンネル名は小文字正規化済み）
        try await client.sendPrivmsg("こんにちは！")

        let sent = await mockWS.sentMessages
        #expect(sent.contains("PRIVMSG #haishinshaa :こんにちは！"))

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("未接続状態での sendPrivmsg は notConnected を throw する")
    func 未接続状態でのsendPrivmsgはnotConnectedをthrowする() async {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 接続していない状態
        await #expect(throws: TwitchIRCClientError.notConnected) {
            try await client.sendPrivmsg("メッセージ送信テスト")
        }
    }

    @Test("匿名接続状態での sendPrivmsg は notAuthenticated を throw する")
    func 匿名接続状態でのsendPrivmsgはnotAuthenticatedをthrowする() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 匿名接続（accessToken/userLogin なし）
        let connectTask = Task {
            try await client.connect(to: "testchannel", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 検証: 匿名接続では notAuthenticated を throw する
        await #expect(throws: TwitchIRCClientError.notAuthenticated) {
            try await client.sendPrivmsg("匿名送信テスト")
        }

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("disconnect 後の sendPrivmsg は notConnected を throw する")
    func disconnect後のsendPrivmsgはnotConnectedをthrowする() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 認証接続後に切断
        let connectTask = Task {
            try await client.connect(to: "testchannel", accessToken: "テスト用トークン", userLogin: "視聴者002")
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.disconnect()
        connectTask.cancel()

        // 検証: 切断後は notConnected を throw する
        await #expect(throws: TwitchIRCClientError.notConnected) {
            try await client.sendPrivmsg("切断後送信テスト")
        }
    }

    @Test("チャンネル名は接続時に正規化された小文字が PRIVMSG ターゲットに使われる")
    func チャンネル名は正規化された小文字がPRIVMSGターゲットに使われる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 大文字を含むチャンネル名で認証接続
        let connectTask = Task {
            try await client.connect(to: "TestChannel", accessToken: "テスト用トークン", userLogin: "視聴者003")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 検証: PRIVMSG は小文字チャンネル名を使う
        try await client.sendPrivmsg("大文字チャンネルテスト")
        let sent = await mockWS.sentMessages
        #expect(sent.contains("PRIVMSG #testchannel :大文字チャンネルテスト"))

        await client.disconnect()
        connectTask.cancel()
    }

    // MARK: - NOTICE 受信

    @Test("msg-id タグ付き NOTICE を受信すると noticeStream に TwitchNotice が流れる")
    func msgidタグ付きNOTICEを受信するとnoticeStreamにTwitchNoticeが流れる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: NOTICE を事前にキュー
        let rawNotice = "@msg-id=msg_ratelimit :tmi.twitch.tv NOTICE #haishinsha :You are sending messages too quickly."
        await mockWS.enqueueMessage(rawNotice)

        var receivedNotices: [TwitchNotice] = []
        let noticeStream = await client.noticeStream

        let connectTask = Task {
            try await client.connect(to: "haishinsha", accessToken: "テスト用トークン", userLogin: "視聴者001")
        }

        // 最初の NOTICE を受信する
        for await notice in noticeStream {
            receivedNotices.append(notice)
            break
        }

        await client.disconnect()
        connectTask.cancel()

        // 検証: TwitchNotice が正しいプロパティで届く（"#haishinsha" → "haishinsha" に正規化）
        #expect(receivedNotices.count == 1)
        #expect(receivedNotices[0].msgId == "msg_ratelimit")
        #expect(receivedNotices[0].channel == "haishinsha")
        #expect(receivedNotices[0].message == "You are sending messages too quickly.")
    }

    @Test("msg-id タグなしの NOTICE も noticeStream に流れ msgId が nil になる")
    func msgidタグなしのNOTICEもnoticeStreamに流れmsgIdがnilになる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: msg-id タグがない NOTICE（匿名接続時など）
        let rawNotice = ":tmi.twitch.tv NOTICE * :Login unsuccessful"
        await mockWS.enqueueMessage(rawNotice)

        var receivedNotices: [TwitchNotice] = []
        let noticeStream = await client.noticeStream

        let connectTask = Task {
            try await client.connect(to: "testchannel")
        }

        for await notice in noticeStream {
            receivedNotices.append(notice)
            break
        }

        await client.disconnect()
        connectTask.cancel()

        // 検証: msgId が nil、channel も nil（"*" はチャンネルではないため）、message は trailing の通り
        #expect(receivedNotices.count == 1)
        #expect(receivedNotices[0].msgId == nil)
        #expect(receivedNotices[0].channel == nil)
        #expect(receivedNotices[0].message == "Login unsuccessful")
    }

    // MARK: - 自動再接続

    @Test("予期せぬ切断後にバックオフ付きで再接続シーケンスが再送される")
    func 予期せぬ切断後にバックオフ付きで再接続シーケンスが再送される() async throws {
        let mockWS = MockWebSocketClient()
        // 前提: テスト用に極小バックオフを注入（0.01s で即再接続）
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            pingConfig: .fastTest
        )

        // チャンネル接続
        let connectTask = Task {
            try await client.connect(to: "haishinshaB", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000) // 接続完了を待つ

        // 1回目の接続で JOIN が送られていることを確認
        let sentBeforeDisconnect = await mockWS.sentMessages
        #expect(sentBeforeDisconnect.contains("JOIN #haishinshab"))

        // 予期せぬ切断をシミュレート（ネットワーク喪失エラー）
        await mockWS.throwOnNextReceive(URLError(.networkConnectionLost))

        // 再接続が走るまで待機（connectCallCount が 2 以上になるまでポーリング）
        let reconnected = await waitFor(timeout: 2.0) { await mockWS.connectCallCount >= 2 }
        #expect(reconnected, "タイムアウト前に再接続が完了しなかった")

        try await Task.sleep(nanoseconds: 100_000_000) // 再接続後の認証シーケンス送信を待つ

        // 検証: 再接続後に JOIN が再送されている
        let sentAfterReconnect = await mockWS.sentMessages
        let joinCount = sentAfterReconnect.filter { $0 == "JOIN #haishinshab" }.count
        #expect(joinCount >= 2)

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("意図的な disconnect() の後は再接続しない")
    func 意図的なdisconnect後は再接続しない() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            pingConfig: .fastTest
        )

        // 前提: チャンネルに接続する
        let connectTask = Task {
            try await client.connect(to: "視聴者ちゃんねる", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 初回接続が1回であることを確認
        let countAfterConnect = await mockWS.connectCallCount
        #expect(countAfterConnect == 1)

        // 意図的に切断する
        await client.disconnect()
        connectTask.cancel()

        // 十分な時間待っても再接続が走らないことを確認（fastTest でも 200ms は十分）
        try await Task.sleep(nanoseconds: 200_000_000)

        // 検証: connectCallCount が 1 のまま（再接続していない）
        let countAfterDisconnect = await mockWS.connectCallCount
        #expect(countAfterDisconnect == 1)
    }

    @Test("RECONNECT コマンド受信時に再接続が走る")
    func RECONNECTコマンド受信時に再接続が走る() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            pingConfig: .fastTest
        )

        // 前提: チャンネルに接続する
        let connectTask = Task {
            try await client.connect(to: "配信者ABC", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let countAfterConnect = await mockWS.connectCallCount
        #expect(countAfterConnect == 1)

        // Twitch からの RECONNECT コマンドを送り込む
        await mockWS.enqueueMessage(":tmi.twitch.tv RECONNECT")

        // 再接続が走るまで待機
        let reconnected = await waitFor(timeout: 2.0) { await mockWS.connectCallCount >= 2 }
        #expect(reconnected, "タイムアウト前に再接続が完了しなかった")

        // 検証: 再接続が走っている
        let countAfterReconnect = await mockWS.connectCallCount
        #expect(countAfterReconnect >= 2)

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("再接続中は connectionStateStream に reconnecting(attempt:) が流れる")
    func 再接続中はconnectionStateStreamにreconnectingが流れる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            pingConfig: .fastTest
        )

        // 前提: connectionStateStream を購読して reconnecting を待機
        let stateStream = await client.connectionStateStream

        // チャンネルに接続する
        let connectTask = Task {
            try await client.connect(to: "配信者XYZ", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 予期せぬ切断をシミュレート
        await mockWS.throwOnNextReceive(URLError(.networkConnectionLost))

        // connectionStateStream から .connected → .reconnecting の遷移を受け取る
        var receivedConnected = false
        var receivedReconnecting = false
        for await state in stateStream {
            if state == .connected { receivedConnected = true }
            if case .reconnecting(1) = state { receivedReconnecting = true; break }
        }

        // 検証: connected の後に reconnecting(attempt: 1) が流れる
        #expect(receivedConnected)
        #expect(receivedReconnecting)

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("再接続成功後は connectionStateStream に connected が流れる")
    func 再接続成功後はconnectionStateStreamにconnectedが流れる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            pingConfig: .fastTest
        )

        // 前提: connectionStateStream を購読
        let stateStream = await client.connectionStateStream

        // チャンネルに接続する
        let connectTask = Task {
            try await client.connect(to: "配信者DDD", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 予期せぬ切断をシミュレート
        await mockWS.throwOnNextReceive(URLError(.networkConnectionLost))

        // .reconnecting の後の .connected を待つ
        var seenReconnecting = false
        var seenConnectedAfterReconnect = false
        for await state in stateStream {
            if case .reconnecting = state { seenReconnecting = true }
            if seenReconnecting && state == .connected {
                seenConnectedAfterReconnect = true
                break
            }
        }

        // 検証: 再接続成功で .connected に戻っている
        #expect(seenConnectedAfterReconnect)

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("PING keepalive の PING が周期的に送信される")
    func PING_keepaliveのPINGが周期的に送信される() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .default,
            // 前提: PING 間隔を短縮（0.05s ごとに送信）
            pingConfig: PingConfiguration(interval: 0.05, timeout: 30.0)
        )

        // チャンネルに接続する
        let connectTask = Task {
            try await client.connect(to: "配信者EEE", accessToken: nil, userLogin: nil)
        }

        // PING が 2 回以上送信されるまで待機（最大 2 秒、並行テスト実行時の遅延を許容）
        let waitSucceeded = await waitFor(timeout: 2.0) {
            let sent = await mockWS.sentMessages
            return sent.filter { $0 == "PING :tmi.twitch.tv" }.count >= 2
        }
        #expect(waitSucceeded, "タイムアウト前に PING が 2 回送信されなかった")

        // 検証: keepalive PING が少なくとも 2 回送信されている
        let sent = await mockWS.sentMessages
        let pingCount = sent.filter { $0 == "PING :tmi.twitch.tv" }.count
        #expect(pingCount >= 2)

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("PONG が届かなければ PING タイムアウトで切断→再接続が走る")
    func PONGが届かなければPINGタイムアウトで切断後再接続が走る() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(
            webSocketClient: mockWS,
            backoffConfig: .fastTest,
            // 前提: interval=0.05s, timeout=0.1s → 0.15s 後にタイムアウト検知
            pingConfig: PingConfiguration(interval: 0.05, timeout: 0.1)
        )

        // チャンネルに接続する（PONG は返さない）
        let connectTask = Task {
            try await client.connect(to: "配信者FFF", accessToken: nil, userLogin: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000) // 接続完了を待つ

        let countAfterConnect = await mockWS.connectCallCount
        #expect(countAfterConnect == 1)

        // PONG を返さずに待機 → interval + timeout 経過でタイムアウト → 再接続
        let reconnected = await waitFor(timeout: 3.0) { await mockWS.connectCallCount >= 2 }
        #expect(reconnected, "タイムアウト前に PING タイムアウト再接続が完了しなかった")

        // 検証: 再接続が走っている
        let countAfterTimeout = await mockWS.connectCallCount
        #expect(countAfterTimeout >= 2)

        await client.disconnect()
        connectTask.cancel()
    }

    // MARK: - テストヘルパー

    /// 条件が満たされるまで最大 `timeout` 秒ポーリングする（10ms 間隔）
    ///
    /// - Parameters:
    ///   - timeout: 最大待機秒数（デフォルト 1.0 秒）
    ///   - condition: 満たされるべき非同期条件
    /// - Returns: 条件が満たされた場合は `true`、タイムアウトした場合は `false`
    @discardableResult
    private func waitFor(timeout: TimeInterval = 1.0, condition: () async -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms ポーリング
        }
        return false
    }
}
