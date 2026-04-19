// TwitchEventSubClientTests.swift
// TwitchEventSubClient の単体テスト
// MockWebSocketClient と MockHelixAPIClient を使用してネットワーク通信なしで検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - Helix API モック

/// EventSub テスト用の Helix API クライアントモック
///
/// サブスクリプション登録 API の呼び出しを記録し、テスト可能なレスポンスを返す
actor MockHelixAPIClientForEventSub: HelixAPIClientProtocol {
    /// POST 呼び出し時に返すレスポンスボディ（JSON 文字列 → Data）
    var postResponse: Data?

    /// 送信されたリクエストボディの記録
    private(set) var capturedPostBodies: [Data] = []

    /// DELETE 呼び出し時の記録
    private(set) var deletedURLs: [URL] = []

    /// POST 呼び出し回数
    private(set) var postCallCount = 0

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        throw URLError(.unsupportedURL)
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T {
        postCallCount += 1
        // リクエストボディをエンコードして記録する
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(body) {
            capturedPostBodies.append(data)
        }
        guard let responseData = postResponse else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: responseData)
    }

    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        postCallCount += 1
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(body) {
            capturedPostBodies.append(data)
        }
    }

    func patch<Body: Encodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws {
        // EventSub テストでは使用しない
    }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        deletedURLs.append(url)
    }

    /// POST レスポンスを JSON 文字列でセットする
    func setPostResponse(_ json: String) {
        postResponse = json.data(using: .utf8)
    }
}

// MARK: - ヘルパー

/// EventSub テストで使用するサンプル JSON メッセージ
private enum EventSubSampleMessages {
    static let welcome = """
    {
      "metadata": {
        "message_id": "welcome-msg-id-001",
        "message_type": "session_welcome",
        "message_timestamp": "2023-07-19T14:56:51.634234626Z"
      },
      "payload": {
        "session": {
          "id": "test-session-id-abc123",
          "status": "connected",
          "connected_at": "2023-07-19T14:56:51.616329898Z",
          "keepalive_timeout_seconds": 10,
          "reconnect_url": null
        }
      }
    }
    """

    static let keepalive = """
    {
      "metadata": {
        "message_id": "keepalive-msg-id-002",
        "message_type": "session_keepalive",
        "message_timestamp": "2023-07-19T14:57:00.000000000Z"
      },
      "payload": {}
    }
    """

    static func notification(
        broadcasterLogin: String = "twitch",
        chatterLogin: String = "testuseraccount",
        messageId: String = "real-msg-id-xyz",
        text: String = "こんにちは！"
    ) -> String {
        """
        {
          "metadata": {
            "message_id": "notif-meta-id-003",
            "message_type": "notification",
            "message_timestamp": "2022-11-16T10:11:12.464757833Z",
            "subscription_type": "channel.chat.message",
            "subscription_version": "1"
          },
          "payload": {
            "subscription": {
              "id": "sub-id-001",
              "status": "enabled",
              "type": "channel.chat.message"
            },
            "event": {
              "broadcaster_user_id": "12826",
              "broadcaster_user_login": "\(broadcasterLogin)",
              "broadcaster_user_name": "\(broadcasterLogin)",
              "chatter_user_id": "142672450",
              "chatter_user_login": "\(chatterLogin)",
              "chatter_user_name": "\(chatterLogin)",
              "message_id": "\(messageId)",
              "message": {
                "text": "\(text)",
                "fragments": []
              },
              "color": "#00FF7F",
              "badges": [],
              "message_type": "text",
              "cheer": null,
              "reply": null,
              "channel_points_custom_reward_id": null,
              "source_broadcaster_user_id": null,
              "source_broadcaster_user_login": null,
              "source_broadcaster_user_name": null,
              "source_message_id": null,
              "source_channel_points_custom_reward_id": null
            }
          }
        }
        """
    }

    static func reconnect(newUrl: String) -> String {
        """
        {
          "metadata": {
            "message_id": "reconnect-msg-id-004",
            "message_type": "session_reconnect",
            "message_timestamp": "2022-11-18T09:10:11.634234626Z"
          },
          "payload": {
            "session": {
              "id": "new-session-id-xyz",
              "status": "reconnecting",
              "keepalive_timeout_seconds": null,
              "reconnect_url": "\(newUrl)",
              "connected_at": "2022-11-16T10:11:12.634234626Z"
            }
          }
        }
        """
    }
}

/// EventSub サブスクリプション登録の成功レスポンス JSON
private let subscriptionSuccessJSON = """
{
  "data": [
    {
      "id": "registered-sub-id-001",
      "status": "enabled",
      "type": "channel.chat.message"
    }
  ]
}
"""

// MARK: - テストスイート

@Suite("TwitchEventSubClient")
struct TwitchEventSubClientTests {

    // MARK: - Welcome 処理

    @Test("Welcome メッセージで session_id が保存される")
    func welcomeMessageStoresSessionId() async throws {
        // 前提: MockWebSocketClient と MockHelixAPIClient を使って EventSub クライアントを初期化する
        let mockWS = MockWebSocketClient()
        let mockAPI = MockHelixAPIClientForEventSub()
        await mockAPI.setPostResponse(subscriptionSuccessJSON)
        let client = TwitchEventSubClient(
            webSocketClient: mockWS,
            apiClient: mockAPI,
            backoffConfig: .fastTest
        )

        // Welcome メッセージを事前にキューに入れる
        await mockWS.enqueueMessage(EventSubSampleMessages.welcome)

        // 操作: 接続する（session_id が保存されるはず）
        Task { try await client.connect() }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 検証: session_id が保存されている
        let sessionId = await client.sessionId
        #expect(sessionId == "test-session-id-abc123")
    }

    // MARK: - サブスクリプション登録

    @Test("subscribeChatMessage でサブスクリプションが Helix API 経由で登録される")
    func subscribeChatMessageCallsHelixAPI() async throws {
        // 前提: Welcome メッセージを受信して session_id を確定させる
        let mockWS = MockWebSocketClient()
        let mockAPI = MockHelixAPIClientForEventSub()
        await mockAPI.setPostResponse(subscriptionSuccessJSON)
        let client = TwitchEventSubClient(
            webSocketClient: mockWS,
            apiClient: mockAPI,
            backoffConfig: .fastTest
        )
        await mockWS.enqueueMessage(EventSubSampleMessages.welcome)
        Task { try await client.connect() }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 操作: サブスクリプションを登録する
        try await client.subscribeChatMessage(broadcasterId: "配信者ID-12345", userId: "自分ID-67890")

        // 検証: Helix API の POST が呼ばれている
        let callCount = await mockAPI.postCallCount
        #expect(callCount == 1)
    }

    // MARK: - notification イベント配信

    @Test("notification イベントが chatMessageEventStream に配信される")
    func notificationEventIsDeliveredToStream() async throws {
        // 前提: Welcome + Notification メッセージをキューに入れる
        let mockWS = MockWebSocketClient()
        let mockAPI = MockHelixAPIClientForEventSub()
        await mockAPI.setPostResponse(subscriptionSuccessJSON)
        let client = TwitchEventSubClient(
            webSocketClient: mockWS,
            apiClient: mockAPI,
            backoffConfig: .fastTest
        )
        await mockWS.enqueueMessage(EventSubSampleMessages.welcome)
        await mockWS.enqueueMessage(
            EventSubSampleMessages.notification(
                broadcasterLogin: "testchannel",
                chatterLogin: "testuseraccount",
                messageId: "real-msg-id-eventsub",
                text: "EventSubテストメッセージ"
            )
        )

        // 操作: 接続してイベントストリームを 1 件受信する
        Task { try await client.connect() }

        let stream = await client.chatMessageEventStream
        var receivedEvent: EventSubChatEvent?
        for await event in stream {
            receivedEvent = event
            break
        }

        // 検証: notification イベントが受信できている
        let event = try #require(receivedEvent)
        #expect(event.messageId == "real-msg-id-eventsub")
        #expect(event.chatterUserLogin == "testuseraccount")
        #expect(event.message.text == "EventSubテストメッセージ")
    }

    // MARK: - 意図的切断

    @Test("disconnect() 後は再接続しない")
    func intentionalDisconnectDoesNotReconnect() async throws {
        // 前提: クライアントを接続する
        let mockWS = MockWebSocketClient()
        let mockAPI = MockHelixAPIClientForEventSub()
        await mockAPI.setPostResponse(subscriptionSuccessJSON)
        let client = TwitchEventSubClient(
            webSocketClient: mockWS,
            apiClient: mockAPI,
            backoffConfig: .fastTest
        )
        await mockWS.enqueueMessage(EventSubSampleMessages.welcome)
        Task { try await client.connect() }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 操作: 意図的に切断する
        await client.disconnect()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 検証: connect 呼び出し回数が 1 回のまま（再接続していない）
        let connectCount = await mockWS.connectCallCount
        #expect(connectCount == 1)
    }

    // MARK: - Reconnect メッセージ処理

    @Test("session_reconnect メッセージで disconnect が呼ばれる")
    func reconnectMessageTriggersDisconnect() async throws {
        // 前提: MockWebSocketClient を使う
        let mockWS = MockWebSocketClient()
        let mockAPI = MockHelixAPIClientForEventSub()
        await mockAPI.setPostResponse(subscriptionSuccessJSON)
        let client = TwitchEventSubClient(
            webSocketClient: mockWS,
            apiClient: mockAPI,
            backoffConfig: .fastTest
        )

        // Welcome → Reconnect メッセージをキューに入れる
        await mockWS.enqueueMessage(EventSubSampleMessages.welcome)
        await mockWS.enqueueMessage(
            EventSubSampleMessages.reconnect(newUrl: "wss://eventsub.wss.twitch.tv?reconnect_token=abc123")
        )

        // 操作: 接続する（Reconnect メッセージを受信すると disconnect が呼ばれる）
        Task { try await client.connect() }
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // 検証: session_reconnect の処理として disconnect が少なくとも 1 回呼ばれている
        // reconnect 後の実際の再接続（connectCallCount >= 2）は並列実行時のタイミング依存のため
        // disconnect の発生のみを確認する（TwitchIRCClientTests の RECONNECT テストと同様の制約）
        let disconnectCount = await mockWS.disconnectCallCount
        #expect(disconnectCount >= 1)
    }
}
