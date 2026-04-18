// ChatViewModelTests.swift
// ChatViewModel の単体テスト
// MockTwitchIRCClient を使用してネットワーク通信なしで ViewModel の振る舞いを検証する
// swiftlint:disable file_length

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
    private var connectionStateContinuation: AsyncStream<ClientConnectionState>.Continuation?
    let connectionStateStream: AsyncStream<ClientConnectionState>
    private var userStateContinuation: AsyncStream<TwitchUserState>.Continuation?
    let userStateStream: AsyncStream<TwitchUserState>

    /// sendPrivmsg() で送信されたメッセージのログ（テスト検証用）
    private(set) var sentPrivmsgs: [String] = []

    /// sendPrivmsg() で渡された返信先 ID のログ（テスト検証用）
    private(set) var sentReplyToIds: [String?] = []

    /// sendPrivmsg() が throw するエラー（nil の場合は成功）
    private var sendPrivmsgError: (any Error)?

    /// テスト用に sendPrivmsg のエラーを設定する
    func setSendPrivmsgError(_ error: (any Error)?) {
        sendPrivmsgError = error
    }

    init() {
        var msgContinuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { msgContinuation = $0 }
        self.messageContinuation = msgContinuation

        var ntcContinuation: AsyncStream<TwitchNotice>.Continuation?
        self.noticeStream = AsyncStream { ntcContinuation = $0 }
        self.noticeContinuation = ntcContinuation

        var stateContinuation: AsyncStream<ClientConnectionState>.Continuation?
        self.connectionStateStream = AsyncStream { stateContinuation = $0 }
        self.connectionStateContinuation = stateContinuation

        var usContinuation: AsyncStream<TwitchUserState>.Continuation?
        self.userStateStream = AsyncStream { usContinuation = $0 }
        self.userStateContinuation = usContinuation
    }

    func connect(to channel: String, accessToken: String?, userLogin: String?) async throws {
        connectCallCount += 1
        connectedChannel = channel
        // 接続成功を connectionStateStream に通知する
        connectionStateContinuation?.yield(.connected)
    }

    func disconnect() async {
        disconnectCalled = true
        connectedChannel = nil
        messageContinuation?.finish()
        noticeContinuation?.finish()
        connectionStateContinuation?.finish()
        userStateContinuation?.finish()
    }

    func sendPrivmsg(_ text: String, replyTo parentMsgId: String? = nil) async throws {
        if let error = sendPrivmsgError {
            throw error
        }
        guard connectedChannel != nil else {
            throw TwitchIRCClientError.notConnected
        }
        sentPrivmsgs.append(text)
        sentReplyToIds.append(parentMsgId)
    }

    /// テスト用にメッセージを流し込む
    func sendMessage(_ message: ChatMessage) {
        messageContinuation?.yield(message)
    }

    /// テスト用に NOTICE を流し込む
    func sendNotice(_ notice: TwitchNotice) {
        noticeContinuation?.yield(notice)
    }

    /// テスト用に接続状態を流し込む（再接続シミュレーション用）
    func sendConnectionState(_ state: ClientConnectionState) {
        connectionStateContinuation?.yield(state)
    }

    /// テスト用に USERSTATE を流し込む
    func sendUserState(_ userState: TwitchUserState) {
        userStateContinuation?.yield(userState)
    }
}

// MARK: - テスト

/// ChatViewModel のテストスイート
@Suite("ChatViewModel テスト")
@MainActor
// swiftlint:disable:next type_body_length
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

    @Test("IRC クライアントが reconnecting を通知すると ViewModel も reconnecting 状態になる")
    func IRCクライアントがreconnectingを通知するとViewModelもreconnecting状態になる() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        // 前提: チャンネルに接続する
        await viewModel.connect(to: "テストチャンネル")
        await waitFor { viewModel.connectionState == .connected }
        #expect(viewModel.connectionState == .connected)

        // IRC クライアントが再接続中を通知する
        await mockClient.sendConnectionState(.reconnecting(attempt: 1))
        await waitFor { viewModel.connectionState == .reconnecting(attempt: 1) }

        // 検証: ViewModel が .reconnecting(attempt: 1) 状態になる
        #expect(viewModel.connectionState == .reconnecting(attempt: 1))
    }

    @Test("再接続中にメッセージ履歴がリセットされない")
    func 再接続中にメッセージ履歴がリセットされない() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        // 前提: チャンネルに接続してメッセージを受信する
        await viewModel.connect(to: "テストチャンネル")
        await waitFor { viewModel.connectionState == .connected }
        let message = makeTestChatMessage(displayName: "視聴者001", text: "再接続テスト前のメッセージ")
        await mockClient.sendMessage(message)
        await waitFor { viewModel.messages.count == 1 }
        #expect(viewModel.messages.count == 1)

        // 再接続中を通知する
        await mockClient.sendConnectionState(.reconnecting(attempt: 1))
        await waitFor { viewModel.connectionState == .reconnecting(attempt: 1) }

        // 検証: メッセージ履歴がリセットされていない
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].displayName == "視聴者001")
    }

    @Test("再接続成功（connected 通知）で ViewModel が connected 状態に戻る")
    func 再接続成功でViewModelがconnected状態に戻る() async throws {
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)

        // 前提: 接続 → 再接続中 → 再接続成功の遷移
        await viewModel.connect(to: "テストチャンネル")
        await waitFor { viewModel.connectionState == .connected }

        await mockClient.sendConnectionState(.reconnecting(attempt: 1))
        await waitFor { viewModel.connectionState == .reconnecting(attempt: 1) }
        #expect(viewModel.connectionState == .reconnecting(attempt: 1))

        // 再接続成功を通知する
        await mockClient.sendConnectionState(.connected)
        await waitFor { viewModel.connectionState == .connected }

        // 検証: .connected に戻る
        #expect(viewModel.connectionState == .connected)
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

    // MARK: - /me コマンド（ACTION 形式）

    @Test("/me コマンドのメッセージが ACTION 形式で IRC に送信される")
    func meコマンドのメッセージがACTION形式でIRCに送信される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: /me コマンドでメッセージ送信
        try await viewModel.sendMessage("/me こんにちは")

        // 検証: IRC には ACTION 形式で送信される
        let sent = await mockClient.sentPrivmsgs
        #expect(sent == ["\u{1}ACTION こんにちは\u{1}"])
    }

    @Test("/me 送信の楽観的 UI メッセージで isAction が true になりテキストは本文のみになる")
    func meコマンドの楽観的UIメッセージでisActionがtrueになる() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: /me コマンドでメッセージ送信
        try await viewModel.sendMessage("/me 手を振る")

        // 検証: 楽観的 UI メッセージで isAction が true になり、text は本文のみ
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].isAction == true)
        #expect(viewModel.messages[0].text == "手を振る")
    }

    @Test("/me のみで本文がない場合は empty エラーを throw する")
    func meコマンドのみで本文がない場合はemptyエラーをthrowする() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 検証: 本文なしの /me は empty エラー
        await #expect(throws: ChatSendError.empty) {
            try await viewModel.sendMessage("/me")
        }
        #expect(viewModel.messages.isEmpty)
    }

    @Test("/me の後が空白のみの場合は empty エラーを throw する")
    func meコマンドの後が空白のみの場合はemptyエラーをthrowする() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 検証: 本文が空白のみの /me は empty エラー
        await #expect(throws: ChatSendError.empty) {
            try await viewModel.sendMessage("/me   ")
        }
        #expect(viewModel.messages.isEmpty)
    }

    @Test("通常のメッセージ送信では楽観的 UI メッセージの isAction が false になる")
    func 通常のメッセージ送信ではisActionがfalseになる() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: 通常メッセージ送信
        try await viewModel.sendMessage("普通のコメント")

        // 検証: isAction が false のまま
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].isAction == false)
    }

    @Test("/me メッセージの本文前後に余分な空白がある場合はトリムされて送信される")
    func meコマンドの本文前後の余分な空白がトリムされて送信される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: 本文前後に余分な空白を含む /me コマンド
        try await viewModel.sendMessage("/me   hello world   ")

        // 検証: IRC には余分な空白をトリムした ACTION 形式で送信される
        let sent = await mockClient.sentPrivmsgs
        #expect(sent == ["\u{1}ACTION hello world\u{1}"])
        #expect(viewModel.messages[0].text == "hello world")
        #expect(viewModel.messages[0].isAction == true)
    }

    @Test("/ME や /Me など大文字の /me コマンドも ACTION 形式で送信される")
    func 大文字のmeコマンドもACTION形式で送信される() async throws {
        // 前提: 認証接続済みの状態
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: 大文字の /ME コマンドを送信
        try await viewModel.sendMessage("/ME 手を振る")

        // 検証: 大文字でも ACTION 形式で IRC に送信される
        let sent = await mockClient.sentPrivmsgs
        #expect(sent == ["\u{1}ACTION 手を振る\u{1}"])
        #expect(viewModel.messages[0].isAction == true)
        #expect(viewModel.messages[0].text == "手を振る")
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
        // swiftlint:disable:next line_length
        let rawMessage = "@badges=;color=#FF0000;display-name=\(displayName);emotes=;id=\(UUID().uuidString);user-id=12345 :testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #testchannel :\(text)"
        let ircMessage = IRCMessageParser.parse(rawMessage)!
        return ChatMessage(from: ircMessage)!
    }

    /// 指定スコープ付きでログイン済みの AuthState を生成するヘルパー
    ///
    /// MockTwitchAuthClient を使って Device Code Flow をシミュレートし、
    /// authState.login() でログイン済み状態にする
    ///
    /// - Parameters:
    ///   - userLogin: ログインユーザー名
    ///   - scopes: 付与する OAuth スコープ（デフォルト: chat:read, chat:edit）
    private func makeLoggedInAuthState(
        userLogin: String,
        scopes: [String] = ["chat:read", "chat:edit"]
    ) async throws -> AuthState {
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
                scope: scopes
            ),
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: userLogin,
                userId: "12345",
                scopes: scopes,
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

    // MARK: - クライアント側レートリミット

    @Test("sendPrivmsgがrateLimitedをthrowするとclientRateLimitedに変換されsendErrorが設定される")
    func sendPrivmsgがrateLimitedをthrowするとclientRateLimitedに変換されsendErrorが設定される() async throws {
        // 前提: 認証接続済みの状態で、sendPrivmsg がレートリミットエラーを throw するよう設定
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者001")
        await mockClient.setSendPrivmsgError(TwitchIRCClientError.rateLimited(retryAfter: 15.0))

        // sendMessage を呼ぶとレートリミットエラーが throw される
        do {
            try await viewModel.sendMessage("レートリミットテスト")
            Issue.record("clientRateLimited が throw されるべきです")
        } catch ChatSendError.clientRateLimited(let retryAfter) {
            // 検証: retryAfter が正しく伝播されている
            #expect(retryAfter == 15.0)
        } catch {
            // 予期しない別エラーが throw された場合はテスト失敗にする
            Issue.record("予期しないエラーが throw されました: \(error)")
        }

        // 検証: sendError に残り秒数付きのメッセージが設定されている
        #expect(viewModel.sendError == ChatSendError.clientRateLimited(retryAfter: 15.0).errorDescription)
    }

    @Test("clientRateLimitedのerrorDescriptionには残り秒数が含まれる")
    func clientRateLimitedのerrorDescriptionには残り秒数が含まれる() {
        // 15.5秒の場合は ceil して16秒と表示される
        let error = ChatSendError.clientRateLimited(retryAfter: 15.5)
        #expect(error.errorDescription == "送信頻度が上限に達しました。あと 16 秒後に再試行してください")
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

    // MARK: - USERSTATE 購読と楽観的 UI

    @Test("USERSTATE 未受信の場合は楽観的 UI に login 名・nil・空バッジが使われる")
    func USERSTATE未受信の場合は楽観的UIにlogin名nilと空バッジが使われる() async throws {
        // 前提: USERSTATE を受信していない状態で接続済み
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // 実行: メッセージ送信（USERSTATE 未受信のため messages が増えることをポーリング）
        try await viewModel.sendMessage("こんにちは！")
        await waitFor { viewModel.messages.count >= 1 }

        // 検証: 楽観的 UI メッセージが login 名を displayName に使い、color は nil、badges は空
        let optimisticMessage = viewModel.messages.first
        #expect(optimisticMessage?.username == "yamadataro")
        #expect(optimisticMessage?.displayName == "yamadataro")
        #expect(optimisticMessage?.colorHex == nil)
        #expect(optimisticMessage?.badges.isEmpty == true)
    }

    @Test("USERSTATE 受信後の楽観的 UI に displayName / color / badges が反映される")
    func USERSTATE受信後の楽観的UIにdisplayNameとcolorとbadgesが反映される() async throws {
        // 前提: USERSTATE を受信済みの状態で接続
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "yamadataro")

        // USERSTATE を流し込み、ViewModel に反映されるまでポーリング
        let rawUserState = "@badges=moderator/1;color=#1E90FF;display-name=山田太郎;"
            + "emote-sets=0;mod=1;subscriber=0;user-type=mod :tmi.twitch.tv USERSTATE #testchannel"
        let ircMsg = try #require(IRCMessageParser.parse(rawUserState), "IRCMessage のパースに失敗しました")
        let userState = try #require(TwitchUserState(from: ircMsg), "TwitchUserState の生成に失敗しました")
        await mockClient.sendUserState(userState)
        await waitFor { viewModel.currentUserState != nil }

        // 実行: USERSTATE 反映済み状態でメッセージ送信
        try await viewModel.sendMessage("こんにちは！")
        await waitFor { viewModel.messages.count >= 1 }

        // 検証: 楽観的 UI メッセージに USERSTATE の情報が反映されている
        let optimisticMessage = viewModel.messages.first
        #expect(optimisticMessage?.username == "yamadataro")
        #expect(optimisticMessage?.displayName == "山田太郎")
        #expect(optimisticMessage?.colorHex == "#1E90FF")
        #expect(optimisticMessage?.badges == [Badge(name: "moderator", version: "1")])
    }

    @Test("USERSTATE を複数回受信した場合は最新の情報が楽観的 UI に使われる")
    func USERSTATE複数回受信した場合は最新の情報が楽観的UIに使われる() async throws {
        // 前提: 接続済み
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "testuser")

        // 1回目の USERSTATE（古い情報）を流し込み、ViewModel への反映をポーリング
        let rawFirst = "@badges=;color=#FF0000;display-name=古い表示名;"
            + "emote-sets=0;mod=0;subscriber=0;user-type= :tmi.twitch.tv USERSTATE #testchannel"
        let firstIrcMsg = try #require(IRCMessageParser.parse(rawFirst), "IRCMessage のパースに失敗しました")
        let firstUserState = try #require(
            TwitchUserState(from: firstIrcMsg), "TwitchUserState の生成に失敗しました"
        )
        await mockClient.sendUserState(firstUserState)
        await waitFor { viewModel.currentUserState?.displayName == "古い表示名" }

        // 2回目の USERSTATE（最新の情報）を流し込み、更新をポーリング
        let rawSecond = "@badges=subscriber/6;color=#00FF7F;display-name=新しい表示名;"
            + "emote-sets=0;mod=0;subscriber=1;user-type= :tmi.twitch.tv USERSTATE #testchannel"
        let secondIrcMsg = try #require(IRCMessageParser.parse(rawSecond), "IRCMessage のパースに失敗しました")
        let secondUserState = try #require(
            TwitchUserState(from: secondIrcMsg), "TwitchUserState の生成に失敗しました"
        )
        await mockClient.sendUserState(secondUserState)
        await waitFor { viewModel.currentUserState?.displayName == "新しい表示名" }

        // 実行: 最新 USERSTATE 反映済み状態でメッセージ送信
        try await viewModel.sendMessage("テストメッセージ")
        await waitFor { viewModel.messages.count >= 1 }

        // 検証: 最新の USERSTATE 情報が使われる
        let optimisticMessage = viewModel.messages.first
        #expect(optimisticMessage?.displayName == "新しい表示名")
        #expect(optimisticMessage?.colorHex == "#00FF7F")
        #expect(optimisticMessage?.badges == [Badge(name: "subscriber", version: "6")])
    }

    // MARK: - 返信（Reply）状態管理

    @Test("replyingTo の初期値が nil である")
    func replyingToの初期値がnilである() async throws {
        // 前提: 接続済み ViewModel
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者001")

        // 検証: replyingTo の初期値が nil
        #expect(viewModel.replyingTo == nil)
    }

    @Test("startReply で replyingTo にメッセージがセットされる")
    func startReplyでreplyingToにメッセージがセットされる() async throws {
        // 前提: 接続済み ViewModel と返信先メッセージ
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者001")
        let parentMessage = makeTestChatMessage(displayName: "配信者", text: "元のメッセージ")

        // 実行: startReply を呼ぶ
        viewModel.startReply(to: parentMessage)

        // 検証: replyingTo に返信先メッセージがセットされる
        #expect(viewModel.replyingTo?.id == parentMessage.id)
    }

    @Test("cancelReply で replyingTo が nil にリセットされる")
    func cancelReplyでreplyingToがnilにリセットされる() async throws {
        // 前提: 返信先がセットされた状態
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者001")
        let parentMessage = makeTestChatMessage(displayName: "配信者", text: "元のメッセージ")
        viewModel.startReply(to: parentMessage)

        // 実行: cancelReply を呼ぶ
        viewModel.cancelReply()

        // 検証: replyingTo が nil にリセットされる
        #expect(viewModel.replyingTo == nil)
    }

    @Test("replyingTo セット状態で sendMessage すると replyTo 付きで IRC 送信される")
    func replyingToセット状態でsendMessageするとreplyTo付きでIRC送信される() async throws {
        // 前提: 返信先がセットされた状態で接続・ログイン済み
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者001")
        let parentMessage = makeTestChatMessage(displayName: "配信者", text: "元のメッセージ")
        viewModel.startReply(to: parentMessage)

        // 実行: sendMessage を呼ぶ
        try await viewModel.sendMessage("返信テキスト")

        // 検証: 返信先 ID が sendPrivmsg に渡される
        let replyToIds = await mockClient.sentReplyToIds
        #expect(replyToIds.last == parentMessage.id)
    }

    @Test("sendMessage 成功後に replyingTo が nil にリセットされる")
    func sendMessage成功後にreplyingToがnilにリセットされる() async throws {
        // 前提: 返信先がセットされた状態で接続・ログイン済み
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者001")
        let parentMessage = makeTestChatMessage(displayName: "配信者", text: "元のメッセージ")
        viewModel.startReply(to: parentMessage)

        // 実行: sendMessage を呼ぶ
        try await viewModel.sendMessage("返信テキスト")

        // 検証: 送信成功後に replyingTo が nil にリセットされる
        #expect(viewModel.replyingTo == nil)
    }

    @Test("replyingTo がセットされた状態の楽観的 UI メッセージに replyParentMsgId がセットされる")
    func replyingToがセットされた状態の楽観的UIメッセージにreplyParentMsgIdがセットされる() async throws {
        // 前提: 返信先がセットされた状態で接続・ログイン済み
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者001")
        let parentMessage = makeTestChatMessage(displayName: "配信者", text: "元のメッセージ")
        viewModel.startReply(to: parentMessage)

        // 実行: sendMessage を呼ぶ
        try await viewModel.sendMessage("返信テキスト")
        await waitFor { viewModel.messages.count >= 1 }

        // 検証: 楽観的 UI メッセージの replyParentMsgId が返信先の id と一致する
        #expect(viewModel.messages.first?.replyParentMsgId == parentMessage.id)
    }

    @Test("replyingTo が nil の状態で sendMessage すると replyTo なしで送信される")
    func replyingToがnilの状態でsendMessageするとreplyToなしで送信される() async throws {
        // 前提: 返信先がセットされていない状態で接続・ログイン済み
        let (viewModel, mockClient) = try await makeConnectedViewModel(userLogin: "視聴者001")

        // 実行: sendMessage を呼ぶ
        try await viewModel.sendMessage("通常メッセージ")

        // 検証: 返信先 ID が nil で送信される（通常メッセージ）
        let replyToIds = await mockClient.sentReplyToIds
        #expect(replyToIds.last == .some(nil))
    }

    // MARK: - mentionStore 連携

    @Test("メッセージ受信後に mentionStore の候補にユーザーが追加される")
    func メッセージ受信後にmentionStoreの候補にユーザーが追加される() async throws {
        // 前提: チャンネルに接続する
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)
        await viewModel.connect(to: "テストチャンネル")
        await waitFor { viewModel.connectionState == .connected }

        // 実行: チャットメッセージを受信する
        let message = makeTestChatMessage(displayName: "配信者テスト", text: "こんにちは")
        await mockClient.sendMessage(message)
        await waitFor { viewModel.messages.count >= 1 }

        // 検証: mentionStore に発言者が登録されている
        let candidates = viewModel.mentionStore.candidates(matching: "")
        #expect(candidates.isEmpty == false)
        #expect(candidates.contains { $0.displayName == "配信者テスト" })
    }

    @Test("複数のメッセージを受信すると最新発言者が先頭になる")
    func 複数のメッセージを受信すると最新発言者が先頭になる() async throws {
        // 前提: チャンネルに接続する
        let mockClient = MockTwitchIRCClient()
        let viewModel = ChatViewModel(ircClient: mockClient)
        await viewModel.connect(to: "テストチャンネル")
        await waitFor { viewModel.connectionState == .connected }

        // 実行: 異なるユーザーのメッセージを順番に受信する
        let msg1 = makeTestChatMessage(displayName: "ユーザーA", text: "最初のメッセージ")
        let msg2 = makeTestChatMessage(displayName: "ユーザーB", text: "2番目のメッセージ")
        await mockClient.sendMessage(msg1)
        await waitFor { viewModel.messages.count >= 1 }
        await mockClient.sendMessage(msg2)
        await waitFor { viewModel.messages.count >= 2 }

        // 検証: 最後に発言した ユーザーB が先頭に来る
        let candidates = viewModel.mentionStore.candidates(matching: "")
        #expect(candidates.first?.displayName == "ユーザーB")
    }

    // MARK: - モデレーションコマンド

    @Test("/ban コマンドが IRC に PRIVMSG として送信される")
    func banコマンドがIRCにPRIVMSGとして送信される() async throws {
        // 前提: channel:moderate スコープ付きでログイン済み・接続済み
        let (viewModel, mockClient) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター001")

        // 実行: /ban コマンドを送信する
        try await viewModel.sendMessage("/ban スパムユーザー")

        // 検証: IRC クライアントに "/ban スパムユーザー" が PRIVMSG として送られている
        let sentMessages = await mockClient.sentPrivmsgs
        #expect(sentMessages == ["/ban スパムユーザー"])
    }

    @Test("/ban コマンドは楽観的 UI メッセージを追加しない")
    func banコマンドは楽観的UIメッセージを追加しない() async throws {
        // 前提: channel:moderate スコープ付きでログイン済み・接続済み
        let (viewModel, _) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター002")

        // 実行: /ban コマンドを送信する
        try await viewModel.sendMessage("/ban 荒らしユーザー")

        // 検証: チャットメッセージリストに変化がない（コマンドはチャットに表示されない）
        #expect(viewModel.messages.isEmpty)
    }

    @Test("/timeout コマンドが IRC に PRIVMSG として送信される")
    func timeoutコマンドがIRCにPRIVMSGとして送信される() async throws {
        // 前提: channel:moderate スコープ付きでログイン済み・接続済み
        let (viewModel, mockClient) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター003")

        // 実行: /timeout コマンドを送信する
        try await viewModel.sendMessage("/timeout 荒らしユーザー 600")

        // 検証: IRC クライアントに "/timeout 荒らしユーザー 600" が送られている
        let sentMessages = await mockClient.sentPrivmsgs
        #expect(sentMessages == ["/timeout 荒らしユーザー 600"])
    }

    @Test("/clear コマンドが IRC に PRIVMSG として送信される")
    func clearコマンドがIRCにPRIVMSGとして送信される() async throws {
        // 前提: channel:moderate スコープ付きでログイン済み・接続済み
        let (viewModel, mockClient) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター004")

        // 実行: /clear コマンドを送信する
        try await viewModel.sendMessage("/clear")

        // 検証: IRC クライアントに "/clear" が送られている
        let sentMessages = await mockClient.sentPrivmsgs
        #expect(sentMessages == ["/clear"])
    }

    @Test("モデレーションコマンドは replyTo を付与しない")
    func モデレーションコマンドはreplyToを付与しない() async throws {
        // 前提: 返信モードの状態で channel:moderate スコープ付きの接続済み
        let (viewModel, mockClient) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター005")
        let replyTarget = makeTestChatMessage(displayName: "返信先ユーザー", text: "テストメッセージ")
        viewModel.startReply(to: replyTarget)
        #expect(viewModel.replyingTo?.id == replyTarget.id)

        // 実行: 返信モード中に /ban コマンドを送信する
        try await viewModel.sendMessage("/ban 対象ユーザー")

        // 検証: replyTo なしで送信されている（モデレーションコマンドは返信コンテキスト不要）
        let sentReplyToIds = await mockClient.sentReplyToIds
        #expect(sentReplyToIds == [nil])
    }

    @Test("channel:moderate スコープなしでモデレーションコマンドを送ると missingScope エラーになる")
    func channel_moderateスコープなしでモデレーションコマンドを送るとmissingScopeエラーになる() async throws {
        // 前提: channel:moderate スコープなし（chat:edit のみ）でログイン済み・接続済み
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "一般視聴者001")

        // 実行: /ban コマンドを送信する（スコープ不足のため失敗するはず）
        do {
            try await viewModel.sendMessage("/ban スパムユーザー")
            Issue.record("missingScope が throw されるべきです")
        } catch ChatSendError.missingScope(let scope) {
            // 検証: 不足しているスコープが "channel:moderate" であることを確認する
            #expect(scope == "channel:moderate")
        } catch {
            Issue.record("予期しないエラーが throw されました: \(error)")
        }

        // 検証: sendError にスコープ不足のメッセージが設定されている
        #expect(viewModel.sendError == ChatSendError.missingScope("channel:moderate").errorDescription)
    }

    @Test("未知のコマンドを送ると unknownCommand エラーになる")
    func 未知のコマンドを送るとunknownCommandエラーになる() async throws {
        // 前提: ログイン済み・接続済み
        let (viewModel, _) = try await makeConnectedViewModel(userLogin: "視聴者999")

        // 実行: 未知のコマンドを送信する
        do {
            try await viewModel.sendMessage("/踊れ")
            Issue.record("unknownCommand が throw されるべきです")
        } catch ChatSendError.unknownCommand(let name) {
            // 検証: コマンド名が正しく伝播している
            #expect(name == "踊れ")
        } catch {
            Issue.record("予期しないエラーが throw されました: \(error)")
        }

        // 検証: sendError に未知コマンドのメッセージが設定されている
        #expect(viewModel.sendError == ChatSendError.unknownCommand("踊れ").errorDescription)
    }

    @Test("/ban 引数なしを送ると missingArguments エラーになる")
    func ban引数なしを送るとmissingArgumentsエラーになる() async throws {
        // 前提: channel:moderate スコープ付きでログイン済み・接続済み
        let (viewModel, _) = try await makeConnectedViewModelWithModerationScope(userLogin: "モデレーター006")

        // 実行: 引数なしで /ban を送信する
        do {
            try await viewModel.sendMessage("/ban")
            Issue.record("missingArguments が throw されるべきです")
        } catch ChatSendError.missingArguments(let command, _) {
            // 検証: コマンド名が "ban" であることを確認する
            #expect(command == "ban")
        } catch {
            Issue.record("予期しないエラーが throw されました: \(error)")
        }
    }

    /// channel:moderate スコープ付きでログイン済み・接続済みの ChatViewModel を返すヘルパー
    /// channel:moderate スコープ付きでログイン済み・接続済みの ChatViewModel を返すヘルパー
    ///
    /// makeLoggedInAuthState を channel:moderate スコープ付きで呼び出して AuthState を生成する。
    private func makeConnectedViewModelWithModerationScope(userLogin: String) async throws -> (ChatViewModel, MockTwitchIRCClient) {
        let mockClient = MockTwitchIRCClient()
        let authState = try await makeLoggedInAuthState(
            userLogin: userLogin,
            scopes: ["chat:read", "chat:edit", "channel:moderate"]
        )
        let viewModel = ChatViewModel(ircClient: mockClient, authState: authState)
        await viewModel.connect(to: "テストチャンネル")
        try await Task.sleep(nanoseconds: 50_000_000)
        return (viewModel, mockClient)
    }
}
