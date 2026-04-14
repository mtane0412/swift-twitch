// BadgeDefinitionTests.swift
// Twitch GQL バッジ定義レスポンスのデコードテスト

import Testing
import Foundation
@testable import TwitchChat

@Suite("BadgeDefinitionTests")
struct BadgeDefinitionTests {

    // MARK: - グローバルバッジレスポンスのデコード

    @Test("グローバルバッジレスポンスを正常にデコードできる")
    func testDecodeGlobalBadgesResponse() throws {
        let json = """
        {
            "data": {
                "badges": [
                    {
                        "id": "YnJvYWRjYXN0ZXI7MTs=",
                        "title": "Broadcaster",
                        "imageURL": "https://static-cdn.jtvnw.net/badges/v1/abc123/2"
                    },
                    {
                        "id": "bW9kZXJhdG9yOzE7",
                        "title": "Moderator",
                        "imageURL": "https://static-cdn.jtvnw.net/badges/v1/def456/2"
                    }
                ]
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GQLBadgesResponse.self, from: data)

        #expect(response.data.badges.count == 2)
        #expect(response.data.badges[0].title == "Broadcaster")
        #expect(response.data.badges[0].imageURL == "https://static-cdn.jtvnw.net/badges/v1/abc123/2")
        #expect(response.data.badges[1].title == "Moderator")
    }

    @Test("GQLバッジのbase64 IDから名前とバージョンを抽出できる")
    func testDecodeGQLBadgeID() throws {
        // "broadcaster;1;" の base64
        let broadcasterBadge = GQLBadgeItem(
            id: "YnJvYWRjYXN0ZXI7MTs=",
            title: "Broadcaster",
            imageURL: "https://example.com/badge.png"
        )
        let parsed = broadcasterBadge.parsedNameAndVersion
        #expect(parsed?.name == "broadcaster")
        #expect(parsed?.version == "1")
    }

    @Test("チャンネル固有バッジのbase64 IDから名前とバージョンを抽出できる")
    func testDecodeChannelBadgeID() throws {
        // "subscriber;0;37402112" の base64
        let subscriberBadge = GQLBadgeItem(
            id: "c3Vic2NyaWJlcjswOzM3NDAyMTEy",
            title: "Subscriber",
            imageURL: "https://example.com/sub.png"
        )
        let parsed = subscriberBadge.parsedNameAndVersion
        #expect(parsed?.name == "subscriber")
        #expect(parsed?.version == "0")
    }

    @Test("不正なbase64 IDの場合はnilを返す")
    func testInvalidBase64ID() {
        let invalidBadge = GQLBadgeItem(
            id: "not-valid-base64!!",
            title: "Invalid",
            imageURL: "https://example.com/badge.png"
        )
        #expect(invalidBadge.parsedNameAndVersion == nil)
    }

    @Test("バッジIDのデコード結果がセミコロン区切りでない場合はnilを返す")
    func testMalformedDecodedID() {
        // "malformed" の base64
        let malformedBadge = GQLBadgeItem(
            id: "bWFsZm9ybWVk",
            title: "Malformed",
            imageURL: "https://example.com/badge.png"
        )
        #expect(malformedBadge.parsedNameAndVersion == nil)
    }

    // MARK: - チャンネルバッジレスポンスのデコード

    @Test("チャンネルバッジレスポンスを正常にデコードできる")
    func testDecodeChannelBadgesResponse() throws {
        let json = """
        {
            "data": {
                "user": {
                    "broadcastBadges": [
                        {
                            "id": "c3Vic2NyaWJlcjswOzM3NDAyMTEy",
                            "title": "サブスクライバー",
                            "imageURL": "https://static-cdn.jtvnw.net/badges/v1/xyz789/2"
                        }
                    ]
                }
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GQLChannelBadgesResponse.self, from: data)

        #expect(response.data.user.broadcastBadges.count == 1)
        #expect(response.data.user.broadcastBadges[0].imageURL == "https://static-cdn.jtvnw.net/badges/v1/xyz789/2")
    }

    @Test("バッジが0件のレスポンスをデコードできる")
    func testDecodeEmptyBadgesResponse() throws {
        let json = """
        {
            "data": {
                "badges": []
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(GQLBadgesResponse.self, from: data)

        #expect(response.data.badges.isEmpty)
    }
}
