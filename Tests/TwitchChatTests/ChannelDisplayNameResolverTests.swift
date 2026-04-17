// ChannelDisplayNameResolverTests.swift
// ChannelDisplayNameResolver の単体テスト
// FollowedStreamStore のデータを使ったチャンネル表示名解決ロジックを検証する

import Foundation
import Testing
@testable import TwitchChat

@Suite("ChannelDisplayNameResolver テスト")
@MainActor
struct ChannelDisplayNameResolverTests {

    // MARK: - テストヘルパー

    /// テスト用の HelixFollowedStreamData を生成する
    private func makeHelixStream(
        userId: String = "111111",
        userLogin: String = "yamada_game",
        userName: String = "山田太郎",
        gameName: String = "マインクラフト",
        title: String = "毎日配信中！",
        viewerCount: Int = 500
    ) -> HelixFollowedStreamData {
        HelixFollowedStreamData(
            id: "test-stream-id-1",
            userId: userId,
            userLogin: userLogin,
            userName: userName,
            gameId: "9999",
            gameName: gameName,
            type: "live",
            title: title,
            viewerCount: viewerCount,
            startedAt: "2024-01-01T00:00:00Z",
            language: "ja",
            thumbnailUrl: "https://example.com/thumb.jpg",
            isMature: false
        )
    }

    /// テスト用の FollowedStreamStore を作成してデータをセットアップする
    private func makeStore(streams: [HelixFollowedStreamData]) async -> FollowedStreamStore {
        let mockClient = MockFollowedStreamAPIClient()
        await mockClient.updateStreams(streams)
        let store = FollowedStreamStore(apiClient: mockClient, userId: "テスト用ユーザーID")
        await store.refresh()
        return store
    }

    // MARK: - テスト

    @Test("フォロー中ストリームがある場合、userName を返す")
    func testDisplayNameReturnsUserNameForFollowedStream() async {
        // 前提: "yamada_game" チャンネルがフォロー中でライブ中
        let store = await makeStore(streams: [
            makeHelixStream(userLogin: "yamada_game", userName: "山田太郎")
        ])
        let resolver = ChannelDisplayNameResolver(store: store)

        // フォロー中の配信者は表示名（userName）が返ること
        #expect(resolver.displayName(for: "yamada_game") == "山田太郎")
    }

    @Test("フォロー外チャンネルの場合、channelLogin をそのまま返す")
    func testDisplayNameReturnsChannelLoginForUnfollowedChannel() async {
        // 前提: ストリームなし（フォロー外または未ライブ）
        let store = await makeStore(streams: [])
        let resolver = ChannelDisplayNameResolver(store: store)

        // フォロー外チャンネルは channelLogin がそのまま返ること
        #expect(resolver.displayName(for: "unknown_channel") == "unknown_channel")
    }

    @Test("大文字混在の channelLogin も正規化して解決される")
    func testDisplayNameNormalizesChannelLogin() async {
        // 前提: "suzuki_live" チャンネルがフォロー中でライブ中（小文字で登録）
        let store = await makeStore(streams: [
            makeHelixStream(userLogin: "suzuki_live", userName: "鈴木次郎")
        ])
        let resolver = ChannelDisplayNameResolver(store: store)

        // 大文字混在で渡しても userName が返ること（FollowedStreamStore が小文字正規化済み）
        #expect(resolver.displayName(for: "Suzuki_Live") == "鈴木次郎")
    }
}
