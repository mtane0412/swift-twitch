// ChannelSearchViewTests.swift
// ChannelSearchView のフィルタロジック単体テスト
// チャンネル名入力によるインクリメンタルサーチの振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テストデータファクトリ

/// テスト用 FollowedStream を生成するヘルパー
private func makeStream(
    id: String = "1",
    userId: String = "111",
    userLogin: String = "testchannel",
    userName: String = "テストチャンネル",
    gameName: String = "マインクラフト",
    viewerCount: Int = 100
) -> FollowedStream {
    FollowedStream(
        id: id,
        userId: userId,
        userLogin: userLogin,
        userName: userName,
        gameName: gameName,
        title: "テスト配信",
        viewerCount: viewerCount,
        thumbnailUrl: "https://example.com/thumb.jpg",
        startedAt: Date()
    )
}

// MARK: - ChannelSearchFilter テスト

@Suite("ChannelSearchFilter")
struct ChannelSearchFilterTests {

    // MARK: - 空クエリ

    @Test("空文字列の場合、全ストリームを返す")
    func emptyQueryReturnsAllStreams() {
        // 前提: 3件のストリームがある
        let streams = [
            makeStream(id: "1", userLogin: "ninja", userName: "Ninja"),
            makeStream(id: "2", userLogin: "shroud", userName: "shroud"),
            makeStream(id: "3", userLogin: "pokimane", userName: "Pokimane"),
        ]

        // 操作: 空文字列でフィルタ
        let result = ChannelSearchFilter.filter(streams: streams, query: "")

        // 検証: 全件返る
        #expect(result.count == 3)
    }

    @Test("スペースのみの場合、全ストリームを返す")
    func whitespaceOnlyQueryReturnsAllStreams() {
        let streams = [
            makeStream(id: "1", userLogin: "ninja", userName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(streams: streams, query: "   ")

        #expect(result.count == 1)
    }

    // MARK: - userLogin による前方一致

    @Test("userLogin の前方一致でフィルタできる")
    func filterByUserLoginPrefix() {
        // 前提: "poki" で始まるチャンネルが1件ある
        let streams = [
            makeStream(id: "1", userLogin: "pokimane", userName: "Pokimane"),
            makeStream(id: "2", userLogin: "ninja", userName: "Ninja"),
        ]

        // 操作: "poki" で検索
        let result = ChannelSearchFilter.filter(streams: streams, query: "poki")

        // 検証: pokimane のみが返る
        #expect(result.count == 1)
        #expect(result[0].userLogin == "pokimane")
    }

    // MARK: - userName による前方一致

    @Test("userName（表示名）の前方一致でフィルタできる")
    func filterByUserNamePrefix() {
        // 前提: 日本語表示名 "ゲーム実況者A" のチャンネルがある
        let streams = [
            makeStream(id: "1", userLogin: "gameaaa", userName: "ゲーム実況者A"),
            makeStream(id: "2", userLogin: "ninja", userName: "Ninja"),
        ]

        // 操作: 日本語で "ゲーム" と検索
        let result = ChannelSearchFilter.filter(streams: streams, query: "ゲーム")

        // 検証: "ゲーム実況者A" のチャンネルが返る
        #expect(result.count == 1)
        #expect(result[0].userLogin == "gameaaa")
    }

    // MARK: - 大文字小文字の区別なし

    @Test("検索クエリは大文字小文字を区別しない（userLogin）")
    func caseInsensitiveUserLogin() {
        let streams = [
            makeStream(id: "1", userLogin: "shroud", userName: "shroud"),
        ]

        // 操作: 大文字で "SHR" と入力
        let result = ChannelSearchFilter.filter(streams: streams, query: "SHR")

        // 検証: shroud が見つかる
        #expect(result.count == 1)
    }

    @Test("検索クエリは大文字小文字を区別しない（userName）")
    func caseInsensitiveUserName() {
        let streams = [
            makeStream(id: "1", userLogin: "ninja", userName: "Ninja"),
        ]

        // 操作: 小文字で "ninja" と入力（userName は "Ninja"）
        let result = ChannelSearchFilter.filter(streams: streams, query: "ninja")

        // 検証: Ninja が見つかる
        #expect(result.count == 1)
    }

    // MARK: - マッチしない場合

    @Test("どちらにも前方一致しない場合、空配列を返す")
    func noMatchReturnsEmpty() {
        let streams = [
            makeStream(id: "1", userLogin: "ninja", userName: "Ninja"),
            makeStream(id: "2", userLogin: "shroud", userName: "shroud"),
        ]

        // 操作: 存在しない "zzz" で検索
        let result = ChannelSearchFilter.filter(streams: streams, query: "zzz")

        // 検証: 空配列が返る
        #expect(result.isEmpty)
    }

    // MARK: - 複数マッチ

    @Test("複数チャンネルが前方一致する場合、全て返す")
    func multipleMatchesReturned() {
        // 前提: "shr" で始まる userLogin が2件ある
        let streams = [
            makeStream(id: "1", userLogin: "shroud", userName: "shroud"),
            makeStream(id: "2", userLogin: "shrew", userName: "shrew"),
            makeStream(id: "3", userLogin: "ninja", userName: "Ninja"),
        ]

        let result = ChannelSearchFilter.filter(streams: streams, query: "shr")

        // 検証: shroud と shrew の2件が返る
        #expect(result.count == 2)
    }

    // MARK: - userLogin と userName の OR 一致

    @Test("userLogin と userName のどちらかが前方一致すればヒットする")
    func matchEitherLoginOrName() {
        // 前提: userLogin は "abc123" だが userName は "日本語チャンネル"
        let streams = [
            makeStream(id: "1", userLogin: "abc123", userName: "日本語チャンネル"),
        ]

        // "日本語" で検索 → userLogin は不一致だが userName が一致
        let resultByName = ChannelSearchFilter.filter(streams: streams, query: "日本語")
        #expect(resultByName.count == 1)

        // "abc" で検索 → userLogin が一致
        let resultByLogin = ChannelSearchFilter.filter(streams: streams, query: "abc")
        #expect(resultByLogin.count == 1)
    }
}
