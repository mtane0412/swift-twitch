// FollowedStreamStoreTests.swift
// FollowedStreamStore の単体テスト
// MockHelixAPIClient を使ってネットワーク通信なしでストア振る舞いを検証する

import Testing
import Foundation
@testable import TwitchChat

// MARK: - テスト用モック

/// HelixFollowedStreamsResponse を返す Helix API クライアントモック
actor MockFollowedStreamAPIClient: HelixAPIClientProtocol {
    /// 返すストリームデータ
    var streamsToReturn: [HelixFollowedStreamData] = []
    /// true の場合、URLError.userAuthenticationRequired を throw する
    var shouldThrowAuthError: Bool = false
    /// get() が呼ばれた回数（呼び出し検証用）
    private(set) var callCount = 0

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        callCount += 1
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        if T.self == HelixFollowedStreamsResponse.self {
            let response = HelixFollowedStreamsResponse(data: streamsToReturn)
            return response as! T  // swiftlint:disable:this force_cast
        }
        throw URLError(.badServerResponse)
    }
}

// MARK: - テストデータファクトリ

/// テスト用ストリームデータを生成する
private func makeHelixStream(
    userId: String = "111111",
    userLogin: String = "テストストリーマー",
    userName: String = "テストストリーマー表示名",
    gameName: String = "マインクラフト",
    title: String = "毎日配信中！",
    viewerCount: Int = 1000
) -> HelixFollowedStreamData {
    HelixFollowedStreamData(
        id: UUID().uuidString,
        userId: userId,
        userLogin: userLogin,
        userName: userName,
        gameId: "1234",
        gameName: gameName,
        type: "live",
        title: title,
        viewerCount: viewerCount,
        startedAt: "2024-01-01T00:00:00Z",
        language: "ja",
        thumbnailUrl: "https://static-cdn.jtvnw.net/previews-ttv/live_user_\(userLogin)-{width}x{height}.jpg",
        isMature: false
    )
}

// MARK: - テスト

@Suite("FollowedStreamStore テスト")
@MainActor
struct FollowedStreamStoreTests {

    // MARK: - 初期状態

    @Test("初期状態は空のストリームリストでローディング中でない")
    func testInitialState() {
        let mockClient = MockFollowedStreamAPIClient()
        let store = FollowedStreamStore(apiClient: mockClient, authState: AuthState())

        #expect(store.streams.isEmpty)
        #expect(!store.isLoading)
        #expect(store.lastError == nil)
    }

    // MARK: - リフレッシュ

    @Test("ログイン済みでリフレッシュするとストリームが取得される")
    func testRefreshFetchesStreams() async {
        let mockClient = MockFollowedStreamAPIClient()
        // userId が設定された authState をシミュレートするため、FollowedStreamStore に直接 userId を渡す
        let store = FollowedStreamStore(apiClient: mockClient, userId: "123456")

        await mockClient.updateStreams([
            makeHelixStream(userLogin: "配信者A", userName: "配信者A表示名"),
            makeHelixStream(userLogin: "配信者B", userName: "配信者B表示名")
        ])

        await store.refresh()

        #expect(store.streams.count == 2)
        #expect(store.streams[0].userLogin == "配信者A")
        #expect(store.streams[1].userLogin == "配信者B")
        #expect(!store.isLoading)
        #expect(store.lastError == nil)
    }

    @Test("ユーザーIDが未設定の場合はリフレッシュをスキップする")
    func testRefreshSkipsWhenNoUserId() async {
        let mockClient = MockFollowedStreamAPIClient()
        // userId: nil でストアを初期化
        let store = FollowedStreamStore(apiClient: mockClient, userId: nil)

        await store.refresh()

        // API が呼ばれていないこと
        let callCount = await mockClient.callCount
        #expect(callCount == 0)
        #expect(store.streams.isEmpty)
    }

    @Test("未ログインの場合はリフレッシュ時にエラーをセットしない（サイレントスキップ）")
    func testRefreshSilentlySkipsWhenNotAuthenticated() async {
        let mockClient = MockFollowedStreamAPIClient()
        await mockClient.setAuthError(true)
        let store = FollowedStreamStore(apiClient: mockClient, userId: "123456")

        await store.refresh()

        // 認証エラーはエラー表示せずサイレントスキップする
        #expect(store.streams.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test("取得したストリームが FollowedStream モデルに正しく変換される")
    func testStreamDataConvertedCorrectly() async {
        let mockClient = MockFollowedStreamAPIClient()
        let store = FollowedStreamStore(apiClient: mockClient, userId: "123456")

        await mockClient.updateStreams([
            makeHelixStream(
                userId: "777777",
                userLogin: "人気配信者",
                userName: "人気配信者の表示名",
                gameName: "フォートナイト",
                title: "ランク戦！",
                viewerCount: 50000
            )
        ])

        await store.refresh()

        let stream = store.streams[0]
        #expect(stream.userId == "777777")
        #expect(stream.userLogin == "人気配信者")
        #expect(stream.userName == "人気配信者の表示名")
        #expect(stream.gameName == "フォートナイト")
        #expect(stream.title == "ランク戦！")
        #expect(stream.viewerCount == 50000)
    }
}

// MARK: - MockFollowedStreamAPIClient ヘルパー

extension MockFollowedStreamAPIClient {
    func updateStreams(_ streams: [HelixFollowedStreamData]) {
        self.streamsToReturn = streams
    }

    func setAuthError(_ value: Bool) {
        self.shouldThrowAuthError = value
    }
}
