// BadgeDefinitionTests.swift
// Twitch Helix API バッジ定義レスポンスのデコードテスト

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
            "data": [
                {
                    "set_id": "broadcaster",
                    "versions": [
                        {
                            "id": "1",
                            "image_url_1x": "https://static-cdn.jtvnw.net/badges/v1/abc123/1",
                            "image_url_2x": "https://static-cdn.jtvnw.net/badges/v1/abc123/2",
                            "image_url_4x": "https://static-cdn.jtvnw.net/badges/v1/abc123/3",
                            "title": "Broadcaster",
                            "description": "放送者"
                        }
                    ]
                },
                {
                    "set_id": "moderator",
                    "versions": [
                        {
                            "id": "1",
                            "image_url_1x": "https://static-cdn.jtvnw.net/badges/v1/def456/1",
                            "image_url_2x": "https://static-cdn.jtvnw.net/badges/v1/def456/2",
                            "image_url_4x": "https://static-cdn.jtvnw.net/badges/v1/def456/3",
                            "title": "Moderator",
                            "description": "モデレーター"
                        }
                    ]
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixBadgesResponse.self, from: data)

        #expect(response.data.count == 2)
        // set_id が正しくデコードされていること
        #expect(response.data[0].setId == "broadcaster")
        #expect(response.data[1].setId == "moderator")
        // versions が正しくデコードされていること
        #expect(response.data[0].versions.count == 1)
        #expect(response.data[0].versions[0].id == "1")
        #expect(response.data[0].versions[0].title == "Broadcaster")
        #expect(response.data[0].versions[0].imageUrl2x == "https://static-cdn.jtvnw.net/badges/v1/abc123/2")
    }

    @Test("チャンネルバッジレスポンスを正常にデコードできる")
    func testDecodeChannelBadgesResponse() throws {
        let json = """
        {
            "data": [
                {
                    "set_id": "subscriber",
                    "versions": [
                        {
                            "id": "0",
                            "image_url_1x": "https://static-cdn.jtvnw.net/badges/v1/xyz789/1",
                            "image_url_2x": "https://static-cdn.jtvnw.net/badges/v1/xyz789/2",
                            "image_url_4x": "https://static-cdn.jtvnw.net/badges/v1/xyz789/3",
                            "title": "サブスクライバー",
                            "description": "チャンネルサブスクライバー"
                        },
                        {
                            "id": "3",
                            "image_url_1x": "https://static-cdn.jtvnw.net/badges/v1/xyz999/1",
                            "image_url_2x": "https://static-cdn.jtvnw.net/badges/v1/xyz999/2",
                            "image_url_4x": "https://static-cdn.jtvnw.net/badges/v1/xyz999/3",
                            "title": "3ヶ月サブスクライバー",
                            "description": "3ヶ月間サブスクライブ"
                        }
                    ]
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixBadgesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].setId == "subscriber")
        // 複数バージョンが正しくデコードされていること
        #expect(response.data[0].versions.count == 2)
        #expect(response.data[0].versions[0].id == "0")
        #expect(response.data[0].versions[1].id == "3")
        #expect(response.data[0].versions[0].imageUrl2x == "https://static-cdn.jtvnw.net/badges/v1/xyz789/2")
    }

    @Test("data が空配列のレスポンスをデコードできる")
    func testDecodeEmptyBadgesResponse() throws {
        let json = """
        {
            "data": []
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixBadgesResponse.self, from: data)

        #expect(response.data.isEmpty)
    }

    @Test("バージョンが複数のバッジセットをデコードできる")
    func testDecodeMultipleVersions() throws {
        let json = """
        {
            "data": [
                {
                    "set_id": "subscriber",
                    "versions": [
                        {
                            "id": "0",
                            "image_url_1x": "https://example.com/sub0/1",
                            "image_url_2x": "https://example.com/sub0/2",
                            "image_url_4x": "https://example.com/sub0/3",
                            "title": "初月サブスクライバー",
                            "description": "1ヶ月サブスクライブ"
                        },
                        {
                            "id": "6",
                            "image_url_1x": "https://example.com/sub6/1",
                            "image_url_2x": "https://example.com/sub6/2",
                            "image_url_4x": "https://example.com/sub6/3",
                            "title": "6ヶ月サブスクライバー",
                            "description": "6ヶ月間サブスクライブ"
                        }
                    ]
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixBadgesResponse.self, from: data)

        let subscriberSet = response.data[0]
        #expect(subscriberSet.setId == "subscriber")
        #expect(subscriberSet.versions[0].id == "0")
        #expect(subscriberSet.versions[0].imageUrl1x == "https://example.com/sub0/1")
        #expect(subscriberSet.versions[0].imageUrl4x == "https://example.com/sub0/3")
        #expect(subscriberSet.versions[1].id == "6")
        #expect(subscriberSet.versions[1].imageUrl2x == "https://example.com/sub6/2")
    }

    @Test("スネークケースの JSON キーが正しくデコードされる")
    func testSnakeCaseCodingKeys() throws {
        let json = """
        {
            "data": [
                {
                    "set_id": "vip",
                    "versions": [
                        {
                            "id": "1",
                            "image_url_1x": "https://example.com/vip/1",
                            "image_url_2x": "https://example.com/vip/2",
                            "image_url_4x": "https://example.com/vip/3",
                            "title": "VIP",
                            "description": "VIPメンバー"
                        }
                    ]
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixBadgesResponse.self, from: data)

        // set_id → setId のスネークケース変換が正しく機能すること
        #expect(response.data[0].setId == "vip")
        // image_url_1x → imageUrl1x のスネークケース変換が正しく機能すること
        #expect(response.data[0].versions[0].imageUrl1x == "https://example.com/vip/1")
        // image_url_2x → imageUrl2x のスネークケース変換が正しく機能すること
        #expect(response.data[0].versions[0].imageUrl2x == "https://example.com/vip/2")
        // image_url_4x → imageUrl4x のスネークケース変換が正しく機能すること
        #expect(response.data[0].versions[0].imageUrl4x == "https://example.com/vip/3")
    }
}
