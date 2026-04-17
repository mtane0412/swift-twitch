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

    /// 受信を待機する継続
    private var pendingReceiveContinuations: [CheckedContinuation<String, Error>] = []

    func connect(to url: URL) async throws {
        isConnected = true
    }

    func send(_ message: String) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> String {
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
        // 待機中の継続をすべてキャンセル
        for continuation in pendingReceiveContinuations {
            continuation.resume(throwing: CancellationError())
        }
        pendingReceiveContinuations.removeAll()
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
}
