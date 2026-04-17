// ChannelSearchViewTests.swift
// ChannelSearchView のフィルタロジック単体テスト
// チャンネル名入力によるインクリメンタルサーチの振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テストデータファクトリ

/// テスト用 FollowedChannel を生成するヘルパー
private func makeChannel(
    broadcasterId: String = "1",
    broadcasterLogin: String = "testchannel",
    broadcasterName: String = "テストチャンネル"
) -> FollowedChannel {
    FollowedChannel(
        broadcasterId: broadcasterId,
        broadcasterLogin: broadcasterLogin,
        broadcasterName: broadcasterName
    )
}

// MARK: - ChannelSearchFilter テスト

@Suite("ChannelSearchFilter")
struct ChannelSearchFilterTests {

    // MARK: - 空クエリ

    @Test("空文字列の場合、空配列を返す（未入力時は何も表示しない）")
    func emptyQueryReturnsEmpty() {
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
            makeChannel(broadcasterId: "2", broadcasterLogin: "shroud", broadcasterName: "shroud"),
            makeChannel(broadcasterId: "3", broadcasterLogin: "pokimane", broadcasterName: "Pokimane"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "")

        // 検証: 空配列が返る（入力なし = 候補を表示しない）
        #expect(result.isEmpty)
    }

    @Test("スペースのみの場合、空配列を返す（未入力時は何も表示しない）")
    func whitespaceOnlyQueryReturnsEmpty() {
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "   ")

        #expect(result.isEmpty)
    }

    // MARK: - broadcasterLogin による前方一致

    @Test("broadcasterLogin の前方一致でフィルタできる")
    func filterByLoginPrefix() {
        // 前提: "poki" で始まるチャンネルが1件ある
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "pokimane", broadcasterName: "Pokimane"),
            makeChannel(broadcasterId: "2", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "poki")

        // 検証: pokimane のみが返る
        #expect(result.count == 1)
        #expect(result[0].broadcasterLogin == "pokimane")
    }

    // MARK: - broadcasterName による前方一致

    @Test("broadcasterName（表示名）の前方一致でフィルタできる")
    func filterByNamePrefix() {
        // 前提: 日本語表示名 "ゲーム実況者A" のチャンネルがある
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "gameaaa", broadcasterName: "ゲーム実況者A"),
            makeChannel(broadcasterId: "2", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "ゲーム")

        // 検証: "ゲーム実況者A" のチャンネルが返る
        #expect(result.count == 1)
        #expect(result[0].broadcasterLogin == "gameaaa")
    }

    // MARK: - 大文字小文字の区別なし

    @Test("検索クエリは大文字小文字を区別しない（broadcasterLogin）")
    func caseInsensitiveLogin() {
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "shroud", broadcasterName: "shroud"),
        ]

        // 操作: 大文字で "SHR" と入力
        let result = ChannelSearchFilter.filter(channels: channels, query: "SHR")

        // 検証: shroud が見つかる
        #expect(result.count == 1)
    }

    @Test("検索クエリは大文字小文字を区別しない（broadcasterName）")
    func caseInsensitiveName() {
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
        ]

        // 操作: 小文字で "ninja" と入力（broadcasterName は "Ninja"）
        let result = ChannelSearchFilter.filter(channels: channels, query: "ninja")

        // 検証: Ninja が見つかる
        #expect(result.count == 1)
    }

    // MARK: - マッチしない場合

    @Test("どちらにも前方一致しない場合、空配列を返す")
    func noMatchReturnsEmpty() {
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
            makeChannel(broadcasterId: "2", broadcasterLogin: "shroud", broadcasterName: "shroud"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "zzz")

        #expect(result.isEmpty)
    }

    // MARK: - 複数マッチ

    @Test("複数チャンネルが前方一致する場合、全て返す")
    func multipleMatchesReturned() {
        // 前提: "shr" で始まる broadcasterLogin が2件ある
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "shroud", broadcasterName: "shroud"),
            makeChannel(broadcasterId: "2", broadcasterLogin: "shrew", broadcasterName: "shrew"),
            makeChannel(broadcasterId: "3", broadcasterLogin: "ninja", broadcasterName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(channels: channels, query: "shr")

        // 検証: shroud と shrew の2件が返る
        #expect(result.count == 2)
    }

    // MARK: - broadcasterLogin と broadcasterName の OR 一致

    @Test("broadcasterLogin と broadcasterName のどちらかが前方一致すればヒットする")
    func matchEitherLoginOrName() {
        // 前提: broadcasterLogin は "abc123" だが broadcasterName は "日本語チャンネル"
        let channels = [
            makeChannel(broadcasterId: "1", broadcasterLogin: "abc123", broadcasterName: "日本語チャンネル"),
        ]

        // "日本語" で検索 → broadcasterLogin は不一致だが broadcasterName が一致
        let resultByName = ChannelSearchFilter.filter(channels: channels, query: "日本語")
        #expect(resultByName.count == 1)

        // "abc" で検索 → broadcasterLogin が一致
        let resultByLogin = ChannelSearchFilter.filter(channels: channels, query: "abc")
        #expect(resultByLogin.count == 1)
    }
}
