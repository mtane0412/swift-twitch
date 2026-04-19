// EmoteDefinitionTests.swift
// HelixEmotesResponse / HelixEmote の JSON デコードテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("EmoteDefinitionTests")
struct EmoteDefinitionTests {

    // MARK: - グローバルエモートレスポンスのデコード

    @Test("グローバルエモートレスポンスを正しくデコードできる")
    func testDecodeGlobalEmotesResponse() throws {
        // Helix GET /helix/chat/emotes/global のサンプルレスポンス
        let json = """
        {
          "data": [
            {
              "id": "425618",
              "name": "LUL",
              "format": ["static", "animated"],
              "emote_type": "globals"
            },
            {
              "id": "112291",
              "name": "KEKHeim",
              "format": ["static"],
              "emote_type": "globals"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 2)

        let lul = response.data[0]
        #expect(lul.id == "425618")
        #expect(lul.name == "LUL")
        #expect(lul.format == ["static", "animated"])
        #expect(lul.emoteType == "globals")

        let kekHeim = response.data[1]
        #expect(kekHeim.id == "112291")
        #expect(kekHeim.name == "KEKHeim")
        #expect(kekHeim.format == ["static"])
    }

    // MARK: - チャンネルエモートレスポンスのデコード

    @Test("チャンネルエモートレスポンスを正しくデコードできる")
    func testDecodeChannelEmotesResponse() throws {
        // Helix GET /helix/chat/emotes?broadcaster_id=... のサンプルレスポンス
        let json = """
        {
          "data": [
            {
              "id": "emotesv2_dc24652ada1e4c84a5e3ceebae4de709",
              "name": "twitchdevHype",
              "format": ["static"],
              "emote_type": "subscriptions"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)

        let emote = response.data[0]
        #expect(emote.id == "emotesv2_dc24652ada1e4c84a5e3ceebae4de709")
        #expect(emote.name == "twitchdevHype")
        #expect(emote.emoteType == "subscriptions")
    }

    // MARK: - emote_type が null の場合のデコード

    @Test("emote_type キーが省略されたエモートでもデコードできる")
    func testDecodeEmoteWithMissingEmoteType() throws {
        // 一部エンドポイントでは emote_type が省略される場合がある
        let json = """
        {
          "data": [
            {
              "id": "1",
              "name": "testerEmote",
              "format": ["static"]
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteType == nil)
    }

    @Test("emote_type が明示的に null のエモートでもデコードできる")
    func testDecodeEmoteWithExplicitNullEmoteType() throws {
        // JSON に "emote_type": null が含まれる場合
        let json = """
        {
          "data": [
            {
              "id": "1",
              "name": "testerEmote",
              "format": ["static"],
              "emote_type": null
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteType == nil)
    }

    // MARK: - Identifiable / Equatable

    @Test("HelixEmote の id フィールドで Identifiable に準拠している")
    func testHelixEmoteIdentifiable() {
        let emote = HelixEmote(id: "425618", name: "LUL", format: ["static"], emoteType: "globals")
        // Identifiable の id は String 型
        #expect(emote.id == "425618")
    }

    @Test("同じ内容の HelixEmote は等しい")
    func testHelixEmoteEquatable() {
        let emote1 = HelixEmote(id: "425618", name: "LUL", format: ["static", "animated"], emoteType: "globals")
        let emote2 = HelixEmote(id: "425618", name: "LUL", format: ["static", "animated"], emoteType: "globals")
        #expect(emote1 == emote2)
    }

    @Test("異なる id の HelixEmote は等しくない")
    func testHelixEmoteNotEqual() {
        let emote1 = HelixEmote(id: "1", name: "エモート1", format: ["static"], emoteType: nil)
        let emote2 = HelixEmote(id: "2", name: "エモート2", format: ["static"], emoteType: nil)
        #expect(emote1 != emote2)
    }

    @Test("id が同じで他のフィールドが異なる HelixEmote は等しくない（すべてのフィールドで等価判定）")
    func testHelixEmoteSameIdDifferentFields() {
        // Equatable 実装は id だけでなくすべてのフィールドを比較する（自動合成 Equatable）
        let emote1 = HelixEmote(id: "425618", name: "LUL", format: ["static"], emoteType: "globals")
        let emote2 = HelixEmote(id: "425618", name: "LUL_CHANGED", format: ["static"], emoteType: "globals")
        #expect(emote1 != emote2)
    }

    // MARK: - emote_set_id のデコード

    @Test("emote_set_id を含むエモートを正しくデコードできる")
    func testDecodeEmoteWithEmoteSetId() throws {
        // 前提: emote_set_id を含むチャンネルエモートのサンプルレスポンス
        let json = """
        {
          "data": [
            {
              "id": "304456832",
              "name": "taborGrin",
              "format": ["static"],
              "emote_type": "subscriptions",
              "emote_set_id": "301590448"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteSetId == "301590448")
    }

    @Test("emote_set_id が明示的に null の場合は emoteSetId が nil になる")
    func testDecodeEmoteWithExplicitNullEmoteSetId() throws {
        // 前提: emote_set_id が明示的に null のエモートレスポンス
        let json = """
        {
          "data": [
            {
              "id": "425618",
              "name": "LUL",
              "format": ["static", "animated"],
              "emote_type": "globals",
              "emote_set_id": null
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteSetId == nil)
    }

    @Test("emote_set_id が省略されている場合は emoteSetId が nil になる")
    func testDecodeEmoteWithMissingEmoteSetId() throws {
        // 前提: emote_set_id を含まないエモートのサンプルレスポンス
        let json = """
        {
          "data": [
            {
              "id": "425618",
              "name": "LUL",
              "format": ["static", "animated"],
              "emote_type": "globals"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteSetId == nil)
    }

    @Test("グローバルエモートの emote_set_id は '0' になる")
    func testDecodeGlobalEmoteSetId() throws {
        // 前提: Twitch のグローバルエモートは emote_set_id が "0"
        let json = """
        {
          "data": [
            {
              "id": "425618",
              "name": "LUL",
              "format": ["static", "animated"],
              "emote_type": "globals",
              "emote_set_id": "0"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].emoteSetId == "0")
    }

    // MARK: - isAnimated computed property

    @Test("format に animated が含まれる場合 isAnimated が true になる")
    func testIsAnimatedTrue() {
        let emote = HelixEmote(id: "425618", name: "LUL", format: ["static", "animated"], emoteType: "globals")
        #expect(emote.isAnimated == true)
    }

    @Test("format に animated が含まれない場合 isAnimated が false になる")
    func testIsAnimatedFalse() {
        let emote = HelixEmote(id: "112291", name: "KEKHeim", format: ["static"], emoteType: "globals")
        #expect(emote.isAnimated == false)
    }

    // MARK: - owner_id のデコード

    @Test("owner_id を含むエモートを正しくデコードできる")
    func testDecodeEmoteWithOwnerId() throws {
        // 前提: /helix/chat/emotes/user レスポンスに含まれる owner_id フィールド
        let json = """
        {
          "data": [
            {
              "id": "emotesv2_hypetrain_test",
              "name": "Hypeトレインエモート",
              "format": ["static"],
              "emote_type": "hypetrain",
              "emote_set_id": "77777",
              "owner_id": "11111111"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].ownerId == "11111111")
    }

    @Test("owner_id が省略されている場合は ownerId が nil になる")
    func testDecodeEmoteWithMissingOwnerId() throws {
        // 前提: グローバル・チャンネルエモート等 owner_id を含まないエンドポイントのレスポンス
        let json = """
        {
          "data": [
            {
              "id": "425618",
              "name": "LUL",
              "format": ["static", "animated"],
              "emote_type": "globals"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].ownerId == nil)
    }

    // MARK: - HelixUserEmotesResponse のデコード

    @Test("HelixUserEmotesResponse を cursor あり で正しくデコードできる")
    func testDecodeUserEmotesResponseWithCursor() throws {
        // 前提: /helix/chat/emotes/user の複数ページある場合のレスポンス
        let json = """
        {
          "data": [
            {
              "id": "emotesv2_sub_other_channel",
              "name": "他チャンネルサブスクエモート",
              "format": ["static"],
              "emote_type": "subscriptions",
              "emote_set_id": "99999",
              "owner_id": "12345678"
            }
          ],
          "pagination": {
            "cursor": "eyJiIjpudWxsLCJhIjp7Ik9mZnNldCI6MX19"
          }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixUserEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].name == "他チャンネルサブスクエモート")
        #expect(response.data[0].ownerId == "12345678")
        #expect(response.cursor == "eyJiIjpudWxsLCJhIjp7Ik9mZnNldCI6MX19")
    }

    @Test("HelixUserEmotesResponse を cursor なし（最終ページ）で正しくデコードできる")
    func testDecodeUserEmotesResponseWithoutCursor() throws {
        // 前提: /helix/chat/emotes/user の最終ページ（cursor フィールドなし）
        let json = """
        {
          "data": [
            {
              "id": "emotesv2_bits_test",
              "name": "ビッツ応援エモート",
              "format": ["static", "animated"],
              "emote_type": "bitstier",
              "emote_set_id": "88888",
              "owner_id": "87654321"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HelixUserEmotesResponse.self, from: data)

        #expect(response.data.count == 1)
        #expect(response.data[0].name == "ビッツ応援エモート")
        #expect(response.data[0].emoteType == "bitstier")
        #expect(response.cursor == nil)
    }
}
