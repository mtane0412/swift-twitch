// RateLimiterTests.swift
// クライアント側レートリミッター（スライディングウィンドウ方式）のテスト

import Testing
import Foundation
@testable import TwitchChat

@Suite("RateLimiterTests")
struct RateLimiterTests {

    // MARK: - 基本的な送信カウント

    @Test("上限以内の送信は成功する")
    func 上限以内の送信は成功する() throws {
        var limiter = RateLimiter(maxMessages: 3, windowDuration: 30.0)
        // 3回は成功する
        try limiter.checkAndRecord()
        try limiter.checkAndRecord()
        try limiter.checkAndRecord()
    }

    @Test("上限+1回目でrateLimitedをthrowする")
    func 上限プラス1回目でrateLimitedをthrowする() throws {
        var limiter = RateLimiter(maxMessages: 3, windowDuration: 30.0)
        try limiter.checkAndRecord()
        try limiter.checkAndRecord()
        try limiter.checkAndRecord()

        // 4回目はレートリミット超過
        #expect(throws: TwitchIRCClientError.self) {
            try limiter.checkAndRecord()
        }
    }

    @Test("rateLimitedエラーにretryAfterが含まれる")
    func rateLimitedエラーにretryAfterが含まれる() throws {
        var currentTime = Date(timeIntervalSince1970: 1000.0)
        var limiter = RateLimiter(maxMessages: 2, windowDuration: 30.0, now: { currentTime })

        try limiter.checkAndRecord()  // t=1000
        currentTime = Date(timeIntervalSince1970: 1005.0)
        try limiter.checkAndRecord()  // t=1005

        currentTime = Date(timeIntervalSince1970: 1010.0)
        do {
            try limiter.checkAndRecord()  // t=1010 → 超過
            Issue.record("rateLimited が throw されるべきです")
        } catch TwitchIRCClientError.rateLimited(let retryAfter) {
            // 最古のタイムスタンプ（t=1000）+ windowDuration(30) - 現在時刻(1010) = 20秒
            #expect(retryAfter > 0)
            #expect(retryAfter <= 30.0)
        }
    }

    // MARK: - ウィンドウ経過後のリセット

    @Test("ウィンドウ経過後は再び送信できる")
    func ウィンドウ経過後は再び送信できる() throws {
        var currentTime = Date(timeIntervalSince1970: 1000.0)
        var limiter = RateLimiter(maxMessages: 2, windowDuration: 30.0, now: { currentTime })

        try limiter.checkAndRecord()  // t=1000
        try limiter.checkAndRecord()  // t=1000

        // ウィンドウ内は超過
        do {
            try limiter.checkAndRecord()
            Issue.record("rateLimited が throw されるべきです")
        } catch TwitchIRCClientError.rateLimited {
            // 期待通り
        }

        // 31秒後 → ウィンドウを抜けたので送信できる
        currentTime = Date(timeIntervalSince1970: 1031.0)
        try limiter.checkAndRecord()
    }

    @Test("ウィンドウ内の古いタイムスタンプは除去される")
    func ウィンドウ内の古いタイムスタンプは除去される() throws {
        var currentTime = Date(timeIntervalSince1970: 1000.0)
        var limiter = RateLimiter(maxMessages: 2, windowDuration: 30.0, now: { currentTime })

        try limiter.checkAndRecord()  // t=1000（後でウィンドウ外になる）
        currentTime = Date(timeIntervalSince1970: 1020.0)
        try limiter.checkAndRecord()  // t=1020（ウィンドウ内に残る）

        // t=1031: 最初のタイムスタンプ(t=1000)は30秒を超えてウィンドウ外に
        currentTime = Date(timeIntervalSince1970: 1031.0)
        // t=1020 のみ残っているので上限2に達していない → 送信できる
        try limiter.checkAndRecord()  // t=1031
    }

    // MARK: - reset

    @Test("resetでカウントがリセットされる")
    func resetでカウントがリセットされる() throws {
        var limiter = RateLimiter(maxMessages: 2, windowDuration: 30.0)

        try limiter.checkAndRecord()
        try limiter.checkAndRecord()
        // 超過状態
        #expect(throws: TwitchIRCClientError.self) {
            try limiter.checkAndRecord()
        }

        // reset 後は再び送信できる
        limiter.reset()
        try limiter.checkAndRecord()
        try limiter.checkAndRecord()
    }

    // MARK: - デフォルト値

    @Test("デフォルト設定は30メッセージ30秒ウィンドウ")
    func デフォルト設定は30メッセージ30秒ウィンドウ() throws {
        var limiter = RateLimiter()
        // 30回は成功する
        for _ in 0..<30 {
            try limiter.checkAndRecord()
        }
        // 31回目は超過
        #expect(throws: TwitchIRCClientError.self) {
            try limiter.checkAndRecord()
        }
    }
}
