// ChatHistoryPersistenceTests.swift
// チャット履歴の永続化（バッファリング書き込み・seed・videoId 紐付け）の統合テスト
// ChatViewModel + InMemoryPersistenceService + MockHelixAPIClientForVideos を組み合わせる

import Foundation
import Testing
@testable import TwitchChat

// MARK: - Helix /videos モック

/// Helix /helix/videos エンドポイントをスタブするテスト用モック
///
/// - `stubbedVideoId` に値を渡すと VOD video_id を返す（nil なら空配列）
/// - `shouldThrow: true` で全 GET リクエストを throw する（Helix エラーシミュレーション）
struct MockHelixAPIClientForVideos: HelixAPIClientProtocol {
    /// スタブする VOD video_id（nil の場合は archive なしとして空配列を返す）
    let stubbedVideoId: String?
    /// true の場合、`URLError.badServerResponse` を throw する
    let shouldThrow: Bool

    init(stubbedVideoId: String? = nil, shouldThrow: Bool = false) {
        self.stubbedVideoId = stubbedVideoId
        self.shouldThrow = shouldThrow
    }

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if url.absoluteString.contains("/helix/videos") {
            if shouldThrow {
                throw URLError(.badServerResponse)
            }
            let data: [HelixVideoData]
            if let videoId = stubbedVideoId {
                data = [HelixVideoData(
                    id: videoId,
                    userId: "配信者ID",
                    streamId: "stream001",
                    type: "archive",
                    title: "テスト配信"
                )]
            } else {
                data = []
            }
            let response = HelixVideosResponse(data: data)
            // swiftlint:disable:next force_cast
            return response as! T
        }
        // /helix/videos 以外は AuthConfigError でサイレントスキップさせる
        // （BadgeStore / EmoteStore は catch is AuthConfigError で無視する）
        throw AuthConfigError.missingClientID
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T {
        throw AuthConfigError.missingClientID
    }

    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        throw AuthConfigError.missingClientID
    }

    func patch<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        throw AuthConfigError.missingClientID
    }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        throw AuthConfigError.missingClientID
    }
}

// MARK: - テスト

@Suite("ChatHistoryPersistence テスト")
@MainActor
struct ChatHistoryPersistenceTests {

    // MARK: - ヘルパー

    /// ViewModel の状態変化を条件が満たされるまで待機する
    ///
    /// - Parameters:
    ///   - timeout: 最大待機秒数（デフォルト 2.0 秒）
    ///   - condition: 満たされるべき条件
    private func waitFor(timeout: TimeInterval = 2.0, condition: () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= timeout { break }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms ポーリング
        }
    }

    /// 永続化サービス・Helix モック付き ChatViewModel を生成する
    private func makeViewModelWithPersistence(
        stubbedVideoId: String? = nil,
        shouldThrowHelixError: Bool = false
    ) -> (ChatViewModel, MockTwitchIRCClient, InMemoryPersistenceService) {
        let mockClient = MockTwitchIRCClient()
        let persistence = InMemoryPersistenceService()
        let helixMock = MockHelixAPIClientForVideos(
            stubbedVideoId: stubbedVideoId,
            shouldThrow: shouldThrowHelixError
        )
        let viewModel = ChatViewModel(
            ircClient: mockClient,
            apiClient: helixMock,
            persistenceService: persistence
        )
        return (viewModel, mockClient, persistence)
    }

    /// room-id タグ付きの IRC PRIVMSG 文字列を MockTwitchIRCClient 経由で ViewModel に流し込む
    private func sendIRCMessage(
        text: String,
        displayName: String = "テスト視聴者",
        roomId: String? = nil,
        to mockClient: MockTwitchIRCClient
    ) {
        let roomIdTag = roomId.map { ";room-id=\($0)" } ?? ""
        let raw = "@badges=;color=#FF0000;display-name=\(displayName)"
            + ";emotes=;id=\(UUID().uuidString)\(roomIdTag);user-id=11111"
            + " :テスト視聴者!テスト視聴者@テスト視聴者.tmi.twitch.tv"
            + " PRIVMSG #テストチャンネル :\(text)"
        guard let ircMsg = IRCMessageParser.parse(raw),
              let chatMsg = ChatMessage(from: ircMsg) else { return }
        Task { await mockClient.sendMessage(chatMsg) }
    }

    // MARK: - バッファリング書き込み

    @Test("appendMessage後200ms以内にメッセージが永続化される")
    func appendMessage後200ms以内にメッセージが永続化される() async throws {
        // 前提: 永続化サービス付き ViewModel を接続
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        await viewModel.connect(to: "テストチャンネル")

        // ROOMSTATE を流して roomId を確定させる
        await mockClient.sendRoomState(roomId: "配信者ID_001")
        await waitFor { viewModel.currentRoomId != nil }

        // 実行: チャットメッセージを送信
        sendIRCMessage(text: "こんにちは、配信！", to: mockClient)
        await waitFor { viewModel.messages.count >= 1 }

        // 300ms 待機（200ms flush タイマーが 1 サイクル以上発火するまで）
        try await Task.sleep(for: .milliseconds(300))

        // 検証: 永続化サービスにメッセージが書き込まれている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_001", limit: 10, before: nil)
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "こんにちは、配信！")

        await viewModel.disconnect()
    }

    @Test("disconnect時に残存キューがflushされる")
    func disconnect時に残存キューがflushされる() async throws {
        // 前提: 200ms flush 前に disconnect を呼ぶシナリオ
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        await viewModel.connect(to: "テストチャンネル")

        await mockClient.sendRoomState(roomId: "配信者ID_002")
        await waitFor { viewModel.currentRoomId != nil }

        // 実行: メッセージ送信後 50ms 以内（flush 前）に disconnect
        sendIRCMessage(text: "切断直前のコメント", to: mockClient)
        await waitFor { viewModel.messages.count >= 1 }
        try await Task.sleep(for: .milliseconds(50)) // 200ms より短い
        await viewModel.disconnect()

        // 検証: disconnect 時に残存キューが flush されている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_002", limit: 10, before: nil)
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "切断直前のコメント")
    }

    @Test("roomIdなしメッセージはROOMSTATE受信後に一括書き込まれる")
    func roomIdなしメッセージはROOMSTATE受信後に一括書き込まれる() async throws {
        // 前提: ROOMSTATE 未受信の状態で接続
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        await viewModel.connect(to: "テストチャンネル")

        // ROOMSTATE 前に room-id なし PRIVMSG を 3 件送信
        sendIRCMessage(text: "1通目：roomIdなし", to: mockClient)
        sendIRCMessage(text: "2通目：roomIdなし", to: mockClient)
        sendIRCMessage(text: "3通目：roomIdなし", to: mockClient)
        await waitFor { viewModel.messages.count >= 3 }

        // ROOMSTATE を流して roomId を確定させる
        await mockClient.sendRoomState(roomId: "配信者ID_003")
        await waitFor { viewModel.currentRoomId != nil }

        // flush 完了を待機
        try await Task.sleep(for: .milliseconds(300))

        // 検証: 3件すべてが roomId 付きで永続化されている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_003", limit: 10, before: nil)
        #expect(loaded.count == 3)
        #expect(loaded.allSatisfy { $0.roomId == "配信者ID_003" })

        await viewModel.disconnect()
    }

    @Test("currentVideoIdがメッセージに永続化される")
    func currentVideoIdがメッセージに永続化される() async throws {
        // 前提: Helix が videoId "VOD_テスト12345" を返すモック付き ViewModel
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence(stubbedVideoId: "VOD_テスト12345")
        await viewModel.connect(to: "テストチャンネル")

        // ROOMSTATE を流すと内部で Helix /videos 呼び出しが起動する
        await mockClient.sendRoomState(roomId: "配信者ID_004")
        await waitFor { viewModel.currentRoomId != nil }

        // videoId の取得完了を待機
        await waitFor { viewModel.currentVideoId != nil }
        #expect(viewModel.currentVideoId == "VOD_テスト12345")

        // 実行: videoId 確定後にメッセージを送信
        sendIRCMessage(text: "VOD紐付けテスト", to: mockClient)
        await waitFor { viewModel.messages.count >= 1 }
        try await Task.sleep(for: .milliseconds(300))

        // 検証: videoId が付いて永続化されている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_004", limit: 10, before: nil)
        #expect(loaded.count == 1)
        #expect(loaded.first?.videoId == "VOD_テスト12345")

        await viewModel.disconnect()
    }

    @Test("videoIdが取得できない場合はnilで永続化される")
    func videoIdが取得できない場合はnilで永続化される() async throws {
        // 前提: Helix が空配列を返す（VOD 保存無効など）
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence(stubbedVideoId: nil)
        await viewModel.connect(to: "テストチャンネル")

        await mockClient.sendRoomState(roomId: "配信者ID_005")
        await waitFor { viewModel.currentRoomId != nil }

        // 実行: videoId なしでメッセージを送信
        sendIRCMessage(text: "VODなし配信のコメント", to: mockClient)
        await waitFor { viewModel.messages.count >= 1 }
        try await Task.sleep(for: .milliseconds(300))

        // 検証: videoId が nil で永続化されている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_005", limit: 10, before: nil)
        #expect(loaded.count == 1)
        #expect(loaded.first?.videoId == nil)

        await viewModel.disconnect()
    }

    @Test("Helixエラー時はnilで続行して接続が維持される")
    func Helixエラー時はnilで続行して接続が維持される() async throws {
        // 前提: Helix がエラーを throw するモック
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence(shouldThrowHelixError: true)
        await viewModel.connect(to: "テストチャンネル")

        await mockClient.sendRoomState(roomId: "配信者ID_006")
        await waitFor { viewModel.currentRoomId != nil }

        // Helix 呼び出しが完了するまで少し待機
        try await Task.sleep(for: .milliseconds(100))

        // 検証: エラーでも接続が維持されている
        #expect(viewModel.connectionState == .connected)
        #expect(viewModel.currentVideoId == nil)

        // 実行: エラー後もメッセージを永続化できる
        sendIRCMessage(text: "Helixエラー後も動いてます", to: mockClient)
        await waitFor { viewModel.messages.count >= 1 }
        try await Task.sleep(for: .milliseconds(300))

        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_006", limit: 10, before: nil)
        #expect(loaded.count == 1)
        #expect(loaded.first?.videoId == nil)

        await viewModel.disconnect()
    }

    // MARK: - 起動時 seed

    @Test("connect時にloadRecentMessagesで直近50件がseedされる")
    func connect時にloadRecentMessagesで直近50件がseedされる() async throws {
        // 前提: 永続化サービスに事前に 50 件のメッセージを書き込む
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        let roomId = "配信者ID_007"
        let past = Date().addingTimeInterval(-3600) // 1時間前
        let seedMessages = (1...50).map { i in
            ChatMessage(
                id: "過去メッセージID_\(i)",
                username: "過去視聴者\(i)",
                displayName: "過去視聴者\(i)",
                text: "過去のコメント\(i)番目",
                colorHex: nil,
                badges: [],
                emotePositions: [],
                roomId: roomId,
                isAction: false,
                receivedAt: past.addingTimeInterval(Double(i)),
                replyParentMsgId: nil,
                isOptimistic: false,
                replyParentUserLogin: nil,
                replyParentDisplayName: nil,
                replyParentMsgBody: nil,
                isSystemNotice: false
            )
        }
        try await persistence.appendMessages(seedMessages)

        // 実行: connect → ROOMSTATE 受信で seed が起動する
        await viewModel.connect(to: "テストチャンネル")
        await mockClient.sendRoomState(roomId: roomId)
        await waitFor { viewModel.currentRoomId != nil }

        // seed 完了を待機
        await waitFor(timeout: 2.0) { viewModel.messages.count >= 50 }

        // 検証: 50 件が表示されていること、すべて isOptimistic = false
        #expect(viewModel.messages.count == 50)
        #expect(viewModel.messages.allSatisfy { !$0.isOptimistic })

        await viewModel.disconnect()
    }

    // MARK: - maxMessages 超過

    @Test("maxMessagesを超えるとメモリから落ちるがdiskには残る")
    func maxMessagesを超えるとメモリから落ちるがdiskには残る() async throws {
        // 前提: 接続済み ViewModel
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        await viewModel.connect(to: "テストチャンネル")

        await mockClient.sendRoomState(roomId: "配信者ID_008")
        await waitFor { viewModel.currentRoomId != nil }

        // 実行: 600 件のメッセージを送信（maxMessages = 500 を超える）
        for i in 1...600 {
            sendIRCMessage(text: "メッセージ\(i)通目", to: mockClient)
        }
        await waitFor(timeout: 10.0) { viewModel.messages.count == 500 }

        // flush が完了するまで待機
        try await Task.sleep(for: .milliseconds(500))

        // 検証: in-memory は 500 件（古い分がカット）
        #expect(viewModel.messages.count == 500)

        // 検証: disk には 600 件残っている
        let loaded = await persistence.loadRecentMessages(roomId: "配信者ID_008", limit: 600, before: nil)
        #expect(loaded.count == 600)

        await viewModel.disconnect()
    }

    // MARK: - 全文検索の基盤

    @Test("searchMessagesがChatViewModelの書き込みを返す")
    func searchMessagesがChatViewModelの書き込みを返す() async throws {
        // 前提: 接続済み ViewModel
        let (viewModel, mockClient, persistence) = makeViewModelWithPersistence()
        await viewModel.connect(to: "テストチャンネル")

        await mockClient.sendRoomState(roomId: "配信者ID_009")
        await waitFor { viewModel.currentRoomId != nil }

        // 実行: 特定キーワードを含むメッセージを送信
        sendIRCMessage(text: "今日の天気はどうですか？", to: mockClient)
        sendIRCMessage(text: "ゲームが面白いですね！", to: mockClient)
        await waitFor { viewModel.messages.count >= 2 }
        try await Task.sleep(for: .milliseconds(300))

        // 検証: 「天気」で検索すると 1 件のみヒット
        let results = await persistence.searchMessages(query: "天気", roomId: "配信者ID_009", limit: 10)
        #expect(results.count == 1)
        #expect(results.first?.text == "今日の天気はどうですか？")

        await viewModel.disconnect()
    }
}
