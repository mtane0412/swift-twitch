// EventSubModelsTests.swift
// EventSub WebSocket メッセージ種別の JSON デコードテスト

import Testing
import Foundation
@testable import TwitchChat

@Suite("EventSubModels")
struct EventSubModelsTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - session_welcome

    @Test("session_welcome メッセージをデコードできる")
    func decodeSessionWelcome() throws {
        let json = """
        {
          "metadata": {
            "message_id": "96a3f3b5-5dec-4eed-908e-e11ee657416c",
            "message_type": "session_welcome",
            "message_timestamp": "2023-07-19T14:56:51.634234626Z"
          },
          "payload": {
            "session": {
              "id": "AQoQILE98gtqShGmLD7AM6yJThAB",
              "status": "connected",
              "connected_at": "2023-07-19T14:56:51.616329898Z",
              "keepalive_timeout_seconds": 10,
              "reconnect_url": null
            }
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageId == "96a3f3b5-5dec-4eed-908e-e11ee657416c")
        #expect(message.metadata.messageType == .sessionWelcome)
        #expect(message.payload.session?.id == "AQoQILE98gtqShGmLD7AM6yJThAB")
        #expect(message.payload.session?.keepaliveTimeoutSeconds == 10)
        #expect(message.payload.session?.reconnectUrl == nil)
        #expect(message.payload.event == nil)
    }

    // MARK: - session_keepalive

    @Test("session_keepalive メッセージをデコードできる")
    func decodeSessionKeepalive() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1407e-1234-5678-abcd-ef0123456789",
            "message_type": "session_keepalive",
            "message_timestamp": "2023-07-19T10:11:12.634234626Z"
          },
          "payload": {}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageType == .sessionKeepalive)
        #expect(message.payload.session == nil)
        #expect(message.payload.event == nil)
    }

    // MARK: - session_reconnect

    @Test("session_reconnect メッセージをデコードできる")
    func decodeSessionReconnect() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1407e-aaaa-bbbb-cccc-dddddddddddd",
            "message_type": "session_reconnect",
            "message_timestamp": "2022-11-18T09:10:11.634234626Z"
          },
          "payload": {
            "session": {
              "id": "AQoQexAWVYKSTIu4ec_2VAryTfrm",
              "status": "reconnecting",
              "keepalive_timeout_seconds": null,
              "reconnect_url": "wss://eventsub.wss.twitch.tv?reconnect_token=abc123",
              "connected_at": "2022-11-16T10:11:12.634234626Z"
            }
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageType == .sessionReconnect)
        #expect(message.payload.session?.id == "AQoQexAWVYKSTIu4ec_2VAryTfrm")
        #expect(message.payload.session?.reconnectUrl == "wss://eventsub.wss.twitch.tv?reconnect_token=abc123")
        #expect(message.payload.session?.keepaliveTimeoutSeconds == nil)
    }

    // MARK: - notification (channel.chat.message)

    @Test("notification (channel.chat.message) メッセージをデコードできる")
    func decodeNotificationChatMessage() throws {
        let json = """
        {
          "metadata": {
            "message_id": "befa7b53-d79d-478f-86b9-120f112b044e",
            "message_type": "notification",
            "message_timestamp": "2022-11-16T10:11:12.464757833Z",
            "subscription_type": "channel.chat.message",
            "subscription_version": "1"
          },
          "payload": {
            "subscription": {
              "id": "sub-id-123",
              "status": "enabled",
              "type": "channel.chat.message",
              "version": "1",
              "cost": 0,
              "condition": {
                "broadcaster_user_id": "12826",
                "user_id": "142672450"
              },
              "transport": {
                "method": "websocket",
                "session_id": "AQoQILE98gtqShGmLD7AM6yJThAB"
              },
              "created_at": "2022-11-16T10:11:12.464757833Z"
            },
            "event": {
              "broadcaster_user_id": "12826",
              "broadcaster_user_login": "twitch",
              "broadcaster_user_name": "Twitch",
              "chatter_user_id": "142672450",
              "chatter_user_login": "testuseraccount",
              "chatter_user_name": "testUserAccount",
              "message_id": "cc106a7e-1a9f-4c07-8c4b-f5f7a0a87c15",
              "message": {
                "text": "こんにちは！テストメッセージ",
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
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageType == .notification)
        #expect(message.metadata.subscriptionType == "channel.chat.message")

        let event = try #require(message.payload.event)
        #expect(event.messageId == "cc106a7e-1a9f-4c07-8c4b-f5f7a0a87c15")
        #expect(event.broadcasterUserLogin == "twitch")
        #expect(event.chatterUserLogin == "testuseraccount")
        #expect(event.message.text == "こんにちは！テストメッセージ")
    }

    // MARK: - revocation

    @Test("revocation メッセージをデコードできる")
    func decodeRevocation() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1407e-rev-sub-revoked-000000",
            "message_type": "revocation",
            "message_timestamp": "2022-11-16T10:11:12.634234626Z",
            "subscription_type": "channel.follow",
            "subscription_version": "1"
          },
          "payload": {
            "subscription": {
              "id": "f1c2a387-161a-49f9-a165-0f21d7a4e1c4",
              "status": "authorization_revoked",
              "type": "channel.follow",
              "version": "1",
              "cost": 0,
              "condition": {
                "broadcaster_user_id": "12826",
                "user_id": "142672450"
              },
              "transport": {
                "method": "websocket",
                "session_id": "AQoQILE98gtqShGmLD7AM6yJThAB"
              },
              "created_at": "2022-11-16T10:11:12.634234626Z"
            }
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageType == .revocation)
        #expect(message.payload.event == nil)
    }

    // MARK: - 不明な message_type

    @Test("不明な message_type は unknown として扱われる")
    func decodeUnknownMessageType() throws {
        let json = """
        {
          "metadata": {
            "message_id": "unknown-type-test-id",
            "message_type": "some_future_type",
            "message_timestamp": "2023-01-01T00:00:00.000000000Z"
          },
          "payload": {}
        }
        """
        let data = try #require(json.data(using: .utf8))
        let message = try decoder.decode(EventSubMessage.self, from: data)

        #expect(message.metadata.messageType == .unknown)
    }
}
