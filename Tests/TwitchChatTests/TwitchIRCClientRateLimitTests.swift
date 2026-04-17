// TwitchIRCClientRateLimitTests.swift
// TwitchIRCClient のクライアント側レートリミット統合テスト

import Foundation
import Testing
@testable import TwitchChat

/// TwitchIRCClient のクライアント側レートリミット統合テスト
@Suite("TwitchIRCClient レートリミットテスト")
struct TwitchIRCClientRateLimitTests {

    @Test("30回連続sendPrivmsgは成功し31回目はrateLimitedをthrowする")
    func 連続三十回sendPrivmsgは成功し三十一回目はrateLimitedをthrowする() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 認証接続
        let connectTask = Task {
            try await client.connect(to: "testchannel", accessToken: "テスト用トークン", userLogin: "視聴者001")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 30回は成功する
        for i in 1...30 {
            try await client.sendPrivmsg("送信テスト \(i)回目")
        }

        // 31回目はレートリミット超過（#expect の closure 形式でエラーを検証する）
        await #expect {
            try await client.sendPrivmsg("レートリミット超過テスト")
        } throws: { error in
            guard case TwitchIRCClientError.rateLimited(let retryAfter) = error else { return false }
            return retryAfter > 0
        }

        await client.disconnect()
        connectTask.cancel()
    }

    @Test("disconnect後は送信カウントがリセットされ再接続後は送信できる")
    func disconnect後は送信カウントがリセットされ再接続後は送信できる() async throws {
        let mockWS = MockWebSocketClient()
        let client = TwitchIRCClient(webSocketClient: mockWS)

        // 前提: 認証接続して上限まで送信する
        let connectTask = Task {
            try await client.connect(to: "testchannel", accessToken: "テスト用トークン", userLogin: "視聴者002")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        for i in 1...30 {
            try await client.sendPrivmsg("送信テスト \(i)回目")
        }
        // 上限に達した状態で切断
        await client.disconnect()
        connectTask.cancel()

        // 再接続
        let reconnectTask = Task {
            try await client.connect(to: "testchannel", accessToken: "テスト用トークン", userLogin: "視聴者002")
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 切断によりカウントがリセットされているので複数回送信できる
        for i in 1...3 {
            try await client.sendPrivmsg("再接続後の送信テスト \(i)回目")
        }

        await client.disconnect()
        reconnectTask.cancel()
    }
}
