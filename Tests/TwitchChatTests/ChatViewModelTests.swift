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

    init() {
        var continuation: AsyncStream<ChatMessage>.Continuation?
        self.messageStream = AsyncStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    func connect(to channel: String, accessToken: String?, userLogin: String?) async throws {
        connectCallCount += 1
        connectedChannel = channel
    }

    func disconnect() async {
        disconnectCalled = true
        messageContinuation?.finish()
    }

    /// テスト用にメッセージを流し込む
    func sendMessage(_ message: ChatMessage) {
        messageContinuation?.yield(message)
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

    // MARK: - ヘルパー

    /// テスト用の ChatMessage を生成する
    private func makeTestChatMessage(displayName: String, text: String) -> ChatMessage {
        let rawMessage = "@badges=;color=#FF0000;display-name=\(displayName);emotes=;id=\(UUID().uuidString);user-id=12345 :testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #testchannel :\(text)"
        let ircMessage = IRCMessageParser.parse(rawMessage)!
        return ChatMessage(from: ircMessage)!
    }
}
