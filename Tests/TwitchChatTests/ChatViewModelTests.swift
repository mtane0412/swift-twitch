// ChatViewModelTests.swift
// ChatViewModel の単体テスト
// MockTwitchIRCClient を使用してネットワーク通信なしで ViewModel の振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - モック

/// テスト用の TwitchIRCClient モック
actor MockTwitchIRCClient: TwitchIRCClientProtocol {
    private(set) var connectedChannel: String?
    private(set) var disconnectCalled = false
    /// connect() が呼ばれた回数（selectChannel での再接続がないことを検証するために使用）
    private(set) var connectCallCount = 0
    private var messageContinuation: AsyncStream<ChatMessage>.Continuation?
    let messageStream: AsyncStream<ChatMessage>
    private var noticeContinuation: AsyncStream<TwitchNotice>.Continuation?
    let noticeStream: AsyncStream<TwitchNotice>

    /// sendPrivmsg() で送信されたメッセージのログ（テスト検証用）
    private(set) var sentPrivmsgs: [String] = []

    /// sendPrivmsg() が throw するエラー（nil の場合は成功）
    var sendPrivmsgError: (any Error)?

    init() {
        var msgContinuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { msgContinuation = $0 }
        self.messageContinuation = msgContinuation

        var ntcContinuation: AsyncStream<TwitchNotice>.Continuation?
        self.noticeStream = AsyncStream { ntcContinuation = $0 }
        self.noticeContinuation = ntcContinuation
    }

    func connect(to channel: String, accessToken: String?, userLogin: String?) async throws {
        connectCallCount += 1
        connectedChannel = channel
    }

    func disconnect() async {
        disconnectCalled = true
        connectedChannel = nil
        messageContinuation?.finish()
        noticeContinuation?.finish()
    }

    func sendPrivmsg(_ text: String) async throws {
        if let error = sendPrivmsgError {
            throw error
        }
        guard connectedChannel != nil else {
            throw TwitchIRCClientError.notConnected
        }
        sentPrivmsgs.append(text)
    }

    /// テスト用にメッセージを流し込む
    func sendMessage(_ message: ChatMessage) {
        messageContinuation?.yield(message)
    }

    /// テスト用に NOTICE を流し込む
    func sendNotice(_ notice: TwitchNotice) {
        noticeContinuation?.yield(notice)
    }
}

// MARK: - テスト

/// ChatViewModel のテストスイート
@Suite("ChatViewModel テスト")
@MainActor
struct ChatViewModelTests {

    // MARK: - 接続状態管理

    @Test("初期状態は disconnected")
    func 初期状態はdisconnected() {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        #expect(viewModel.connectionState == .disconnected)
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.channelName.isEmpty)
    }

    @Test("チャンネル接続後は connected 状態になる")
    func チャンネル接続後はconnected状態になる() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.connectionState == .connected)
        #expect(viewModel.channelName == "テストチャンネル")
    }

    @Test("切断後は disconnected 状態になる")
    func 切断後はdisconnected状態になる() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)
        await viewModel.disconnect()

        #expect(viewModel.connectionState == .disconnected)
    }

    // MARK: - メッセージ受信

    @Test("受信メッセージがリストに追加される")
    func 受信メッセージがリストに追加される() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)

        // メッセージを流し込む
        let message = makeTestChatMessage(displayName: "山田太郎", text: "こんにちは")
        await mockClient.sendMessage(message)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].displayName == "山田太郎")
        #expect(viewModel.messages[0].text == "こんにちは")
    }

    // MARK: - メッセージ上限

    @Test("メッセージが 500 件を超えると古いものから削除される")
    func メッセージが500件を超えると古いものから削除される() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)

        // 501 件のメッセージを流し込む
        for i in 0..<501 {
            let message = makeTestChatMessage(displayName: "ユーザー\(i)", text: "メッセージ \(i)")
            await mockClient.sendMessage(message)
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms 待機

        // 最大 500 件に制限される
        #expect(viewModel.messages.count <= 500)
        // 最新のメッセージが残っている
        #expect(viewModel.messages.last?.text == "メッセージ 500")
    }

    // MARK: - sendMessage 送信機能

    @Test("sendMessage で IRC クライアントへサニタイズ済み文字列が渡る")
    func sendMessageでIRCクライアントへサニタイズ済み文字列が渡る() async throws {
        // 前提: 認証接続済みの状態を作る
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "送信者001")

        try await viewModel.sendMessage("こんにちは！")

        let sent = await mockClient.sentPrivmsgs
        #expect(sent == ["こんにちは！"])
    }

    @Test("sendMessage 成功時に messages に楽観的メッセージが追加される")
    func sendMessage成功時にmessagesに楽観的メッセージが追加される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "送信者002")

        try await viewModel.sendMessage("配信見てます！")

        // 検証: messages に自分のメッセージが追加される
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].username == "送信者002")
        #expect(viewModel.messages[0].text == "配信見てます！")
    }

    @Test("空文字列の sendMessage は empty エラーを throw し messages は変化しない")
    func 空文字列のsendMessageはemptyエラーをthrowしmessagesは変化しない() async throws {
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "送信者003")

        await #expect(throws: ChatSendError.empty) {
            try await viewModel.sendMessage("")
        }
        #expect(viewModel.messages.isEmpty)
    }

    @Test("空白のみの sendMessage は empty エラーを throw する")
    func 空白のみのsendMessageはemptyエラーをthrowする() async throws {
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "送信者004")

        await #expect(throws: ChatSendError.empty) {
            try await viewModel.sendMessage("   　\t")
        }
        #expect(viewModel.messages.isEmpty)
    }

    @Test("501 文字の sendMessage は tooLong エラーを throw し IRC 送信は呼ばれない")
    func 文字数制限超えのsendMessageはtooLongエラーをthrowしIRC送信は呼ばれない() async throws {
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "送信者005")

        // 501 文字のテキスト
        let longText = String(repeating: "あ", count: 501)
        await #expect(throws: ChatSendError.tooLong) {
            try await viewModel.sendMessage(longText)
        }
        // 検証: IRC には何も送信されていない
        let sent = await mockClient.sentPrivmsgs
        #expect(sent.isEmpty)
    }

    @Test("改行文字を含むテキストはサニタイズされてスペースに変換される")
    func 改行文字を含むテキストはサニタイズされてスペースに変換される() async throws {
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "送信者006")

        try await viewModel.sendMessage("前半\r\n後半")

        let sent = await mockClient.sentPrivmsgs
        // \r\n は \r 除去 → \n をスペースに変換 の順で処理される
        #expect(sent == ["前半 後半"])
    }

    @Test("未接続状態での sendMessage は notReady エラーを throw する")
    func 未接続状態でのsendMessageはnotReadyエラーをthrowする() async throws {
        let mockClient = MockTwitchIRCClient()
        let authState = try await makeLoggedInAuthState(userLogin: "送信者007")
        let viewModel = ChatViewModel(ircClient: mockClient, authState: authState)
        // 接続しない（disconnected 状態）

        await #expect(throws: ChatSendError.notReady) {
            try await viewModel.sendMessage("テストメッセージ")
        }
    }

    @Test("ログアウト状態では canSendMessage が false になる")
    func ログアウト状態ではcanSendMessageがfalseになる() async throws {
        let mockClient = MockTwitchIRCClient()
        let authState = AuthState(
            authClient: MockTwitchAuthClient(),
            keychainStore: KeychainStore(service: "test.\(UUID().uuidString)"),
            openURL: { _ in }
        )
        // 前提: ログアウト状態（Keychain にトークンなし）
        await authState.restoreSession()
        let viewModel = ChatViewModel(ircClient: mockClient, authState: authState)

        // 接続（匿名接続になる）
        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)

        // 検証: ログアウト中は canSendMessage = false
        #expect(viewModel.canSendMessage == false)
    }

    // MARK: - NOTICE によるエラー反映

    @Test("msg_ratelimit NOTICE を受信すると sendError にレートリミット文言が設定される")
    func msgRatelimitNOTICEを受信するとsendErrorにレートリミット文言が設定される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者001")

        // sendMessage で楽観 UI を追加してから NOTICE を流し込む
        try await viewModel.sendMessage("速攻コメント")
        await mockClient.sendNotice(TwitchNotice(
            msgId: "msg_ratelimit",
            channel: "テストチャンネル",
            message: "You are sending messages too quickly."
        ))

        // 検証: sendError が日本語のレートリミット文言になっている
        await waitFor { viewModel.sendError != nil }
        #expect(viewModel.sendError == ChatSendError.rateLimited.errorDescription)
    }

    @Test("msg_duplicate NOTICE を受信すると楽観 UI メッセージが messages から取り消される")
    func msgDuplicateNOTICEを受信すると楽観UIメッセージがmessagesから取り消される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者002")

        // sendMessage で楽観 UI を追加してから NOTICE を流し込む
        try await viewModel.sendMessage("同じ文言")
        #expect(viewModel.messages.count == 1)

        await mockClient.sendNotice(TwitchNotice(
            msgId: "msg_duplicate",
            channel: "テストチャンネル",
            message: "Your message was not sent because it is identical to the previous one."
        ))

        // 検証: 楽観 UI メッセージが取り消されて messages が空になる
        await waitFor { viewModel.messages.isEmpty }
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.sendError == ChatSendError.duplicate.errorDescription)
    }

    @Test("msg_banned NOTICE を受信すると sendError に BAN 文言が設定される")
    func msgBannedNOTICEを受信するとsendErrorにBAN文言が設定される() async throws {
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者003")

        try await viewModel.sendMessage("書き込みテスト")
        await mockClient.sendNotice(TwitchNotice(
            msgId: "msg_banned",
            channel: "テストチャンネル",
            message: "You are permanently banned from talking in this channel."
        ))

        await waitFor { viewModel.sendError != nil }
        #expect(viewModel.sendError == ChatSendError.banned.errorDescription)
        // 楽観 UI メッセージも取り消される
        #expect(viewModel.messages.isEmpty)
    }

    @Test("未対応の msg-id の NOTICE は sendError を変化させない")
    func 未対応のmsgidのNOTICEはsendErrorを変化させない() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者004")

        // sendError が nil の状態から
        #expect(viewModel.sendError == nil)

        // 情報系 NOTICE（host_on など）を流し込む
        await mockClient.sendNotice(TwitchNotice(
            msgId: "host_on",
            channel: "テストチャンネル",
            message: "Now hosting another channel."
        ))
        // 十分に待ってから確認（状態変化がないことを確認するため最低限の待機）
        try await Task.sleep(nanoseconds: 100_000_000)

        // 検証: sendError は変化しない
        #expect(viewModel.sendError == nil)
    }

    @Test("msg-id なしの NOTICE は sendError を変化させない")
    func msgidなしのNOTICEはsendErrorを変化させない() async throws {
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者005")

        await mockClient.sendNotice(TwitchNotice(
            msgId: nil,
            channel: nil,
            message: "Login unsuccessful"
        ))
        // 状態変化がないことを確認するため最低限の待機
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.sendError == nil)
    }

    @Test("isSending は sendMessage の実行中だけ true になる")
    func isSendingはsendMessageの実行中だけtrueになる() async throws {
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "送信者008")

        // 送信前は false
        #expect(viewModel.isSending == false)
        try await viewModel.sendMessage("送信テスト")
        // 送信完了後は false に戻る
        #expect(viewModel.isSending == false)
    }

    // MARK: - ヘルパー

    /// ViewModel の状態変化を条件が満たされるまで待機する
    ///
    /// `Task.sleep` による固定待機より確実に状態更新を待てる。
    /// `timeout` 秒以内に条件が満たされなければタイムアウトとして抜ける。
    ///
    /// - Parameters:
    ///   - timeout: 最大待機秒数（デフォルト 1.0 秒）
    ///   - condition: 満たされるべき条件
    private func waitFor(timeout: TimeInterval = 1.0, condition: () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= timeout { break }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms ポーリング
        }
    }

    /// テスト用の ChatMessage を生成する
    private func makeTestChatMessage(displayName: String, text: String) -> ChatMessage {
        let rawMessage = "@badges=;color=#FF0000;display-name=\(displayName);emotes=;id=\(UUID().uuidString);user-id=12345 :testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #testchannel :\(text)"
        let ircMessage = IRCMessageParser.parse(rawMessage)!
        return ChatMessage(from: ircMessage)!
    }

    /// chat:edit スコープ付きでログイン済みの AuthState を生成するヘルパー
    ///
    /// MockTwitchAuthClient を使って Device Code Flow をシミュレートし、
    /// authState.login() でログイン済み状態（grantedScopes に chat:edit あり）にする
    private func makeLoggedInAuthState(userLogin: String) async throws -> AuthState {
        let store = KeychainStore(service: "test.\(UUID().uuidString)")
        let mockAuthClient = MockTwitchAuthClient(
            deviceCodeResponse: TwitchDeviceCodeResponse(
                deviceCode: "テスト用デバイスコード",
                userCode: "TEST-1234",
                verificationUri: "https://www.twitch.tv/activate",
                expiresIn: 1800,
                interval: 0
            ),
            tokenResponse: TwitchTokenResponse(
                accessToken: "テスト用アクセストークン",
                refreshToken: "テスト用リフレッシュトークン",
                expiresIn: 14400,
                tokenType: "bearer",
                scope: ["chat:read", "chat:edit"]
            ),
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: userLogin,
                userId: "12345",
                scopes: ["chat:read", "chat:edit"],
                expiresIn: 14400
            )
        )
        let authState = AuthState(
            authClient: mockAuthClient,
            keychainStore: store,
            openURL: { _ in }
        )
        await authState.login()
        return authState
    }

    /// 認証接続済み（connected）の ChatViewModel と MockTwitchIRCClient のペアを返す
    ///
    /// - Parameter userLogin: ログインユーザー名（楽観的 UI の username に使用）
    private func makeConnectedViewModel(userLogin: String) async throws -> (ChatViewModel, MockTwitchIRCClient) {
        let mockClient = MockTwitchIRCClient()
        let authState = try await makeLoggedInAuthState(userLogin: userLogin)
        let viewModel = ChatViewModel(ircClient: mockClient, authState: authState)

        // チャンネルに接続して connected 状態にする
        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)

        return (viewModel, mockClient)
    }
}
