// TwitchUserTests.swift
// TwitchUser モデルのデコードテスト
// Twitch Helix API /helix/users レスポンスが正しくデコードされるかを検証する

import Testing
import Foundation
@testable import TwitchChat

@Suite("TwitchUser モデルテスト")
struct TwitchUserTests {

    // MARK: - HelixUsersResponse デコードテスト

    @Test("HelixUsersResponse が正しくデコードされる")
    func testHelixUsersResponseDecoding() throws {
        // Twitch Helix API /helix/users の実際のレスポンス形式
        let jsonData = """
        {
            "data": [
                {
                    "id": "141981764",
                    "login": "twitchdev",
                    "display_name": "TwitchDev",
                    "type": "",
                    "broadcaster_type": "partner",
                    "description": "Twitch公式開発アカウント",
                    "profile_image_url": "https://static-cdn.jtvnw.net/jtv_user_pictures/twitchdev-profile.png",
                    "offline_image_url": "https://static-cdn.jtvnw.net/jtv_user_pictures/twitchdev-offline.png",
                    "view_count": 5980557,
                    "created_at": "2016-12-14T20:32:28Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(HelixUsersResponse.self, from: jsonData)

        #expect(response.data.count == 1)
        let userData = response.data[0]
        #expect(userData.id == "141981764")
        #expect(userData.login == "twitchdev")
        #expect(userData.displayName == "TwitchDev")
        #expect(userData.profileImageUrl == URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/twitchdev-profile.png"))
    }

    @Test("複数ユーザーの HelixUsersResponse が正しくデコードされる")
    func testHelixUsersResponseDecodingMultipleUsers() throws {
        // Twitch の login は ASCII 小文字英数字/アンダースコアのみ（display_name は日本語可）
        let jsonData = """
        {
            "data": [
                {
                    "id": "111111",
                    "login": "streamer_a",
                    "display_name": "配信者あ表示名",
                    "type": "",
                    "broadcaster_type": "",
                    "description": "",
                    "profile_image_url": "https://example.com/ah.png",
                    "offline_image_url": "",
                    "view_count": 1000,
                    "created_at": "2020-01-01T00:00:00Z"
                },
                {
                    "id": "222222",
                    "login": "streamer_b",
                    "display_name": "配信者い表示名",
                    "type": "",
                    "broadcaster_type": "",
                    "description": "",
                    "profile_image_url": "https://example.com/i.png",
                    "offline_image_url": "",
                    "view_count": 2000,
                    "created_at": "2020-02-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(HelixUsersResponse.self, from: jsonData)

        #expect(response.data.count == 2)
        #expect(response.data[0].id == "111111")
        #expect(response.data[0].login == "streamer_a")
        #expect(response.data[0].displayName == "配信者あ表示名")
        #expect(response.data[0].profileImageUrl == URL(string: "https://example.com/ah.png"))
        #expect(response.data[1].id == "222222")
        #expect(response.data[1].login == "streamer_b")
        #expect(response.data[1].profileImageUrl == URL(string: "https://example.com/i.png"))
    }

    // MARK: - デコード失敗テスト

    @Test("必須フィールドが欠けている場合はデコードエラーになる")
    func testHelixUsersResponseDecodingMissingRequiredField() {
        // "id" フィールドが欠けているため DecodingError が発生する
        let jsonData = """
        {
            "data": [
                {
                    "login": "test_streamer",
                    "display_name": "テスト配信者",
                    "type": "",
                    "broadcaster_type": "",
                    "description": "",
                    "profile_image_url": "https://example.com/profile.png",
                    "offline_image_url": "",
                    "view_count": 100,
                    "created_at": "2020-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HelixUsersResponse.self, from: jsonData)
        }
    }

    @Test("不正な JSON は デコードエラーになる")
    func testHelixUsersResponseDecodingMalformedJSON() {
        // JSON として無効な文字列
        let invalidJsonData = "{ invalid json }".data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HelixUsersResponse.self, from: invalidJsonData)
        }
    }

    @Test("data キーが欠けている JSON はデコードエラーになる")
    func testHelixUsersResponseDecodingMissingDataKey() {
        // "data" キーが存在しない
        let jsonData = """
        {
            "total": 1
        }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HelixUsersResponse.self, from: jsonData)
        }
    }

    @Test("フィールドの型が不一致の場合はデコードエラーになる")
    func testHelixUsersResponseDecodingTypeMismatch() {
        // "id" が文字列ではなく数値になっている
        let jsonData = """
        {
            "data": [
                {
                    "id": 12345,
                    "login": "test_streamer",
                    "display_name": "テスト配信者",
                    "type": "",
                    "broadcaster_type": "",
                    "description": "",
                    "profile_image_url": "https://example.com/profile.png",
                    "offline_image_url": "",
                    "view_count": 100,
                    "created_at": "2020-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HelixUsersResponse.self, from: jsonData)
        }
    }

    // MARK: - HelixUserData のプロパティテスト

    @Test("HelixUserData のプロパティが正しく設定される")
    func testHelixUserDataProperties() {
        // TwitchUser と HelixUserData を統合したため、HelixUserData をドメインモデルとして直接利用する
        let userData = HelixUserData(
            id: "987654",
            login: "test_streamer",
            displayName: "テスト配信者の表示名",
            profileImageUrl: URL(string: "https://example.com/profile.png")
        )

        #expect(userData.id == "987654")
        #expect(userData.login == "test_streamer")
        #expect(userData.displayName == "テスト配信者の表示名")
        #expect(userData.profileImageUrl == URL(string: "https://example.com/profile.png"))
    }

    @Test("profile_image_url が空文字列の場合は nil になる")
    func testProfileImageUrlEmptyStringBecomesNil() throws {
        // Twitch API が空文字列を返した場合、URL? は nil になることを検証する
        let jsonData = """
        {
            "data": [
                {
                    "id": "111111",
                    "login": "streamer_a",
                    "display_name": "配信者あ表示名",
                    "type": "",
                    "broadcaster_type": "",
                    "description": "",
                    "profile_image_url": "",
                    "offline_image_url": "",
                    "view_count": 100,
                    "created_at": "2020-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(HelixUsersResponse.self, from: jsonData)
        #expect(response.data[0].profileImageUrl == nil)
    }

    @Test("空のデータ配列の HelixUsersResponse が正しくデコードされる")
    func testHelixUsersResponseDecodingEmptyData() throws {
        let jsonData = """
        {
            "data": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(HelixUsersResponse.self, from: jsonData)

        #expect(response.data.isEmpty)
    }
}
