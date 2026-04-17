// RateLimiter.swift
// クライアント側レートリミッター（スライディングウィンドウ方式）
//
// Twitch IRC のレートリミット（30秒あたり30メッセージ）をクライアント側で事前チェックする。
// サーバーから NOTICE msg_ratelimit が返る前に超過を検知し、即座にフィードバックできる。

import Foundation

/// クライアント側レートリミッター
///
/// スライディングウィンドウ方式で直近 `windowDuration` 秒以内の送信タイムスタンプを管理する。
/// `checkAndRecord()` 呼び出し時に送信数が `maxMessages` に達していれば `rateLimited` を throw する。
///
/// - Note: actor 内で値型として保持することで actor isolation を活用できる。
/// - Note: `now` クロージャを差し替えることでテスト時に時刻を制御可能。
struct RateLimiter {

    // MARK: - プロパティ

    /// ウィンドウ内の送信タイムスタンプ一覧（古い順）
    private(set) var timestamps: [Date] = []

    /// スライディングウィンドウの幅（秒）。デフォルト: 30秒
    let windowDuration: TimeInterval

    /// ウィンドウ内の最大送信可能メッセージ数。デフォルト: 30
    let maxMessages: Int

    /// 現在時刻を返すクロージャ（テスト時に差し替え可能）
    var now: () -> Date

    // MARK: - イニシャライザ

    /// レートリミッターを初期化する
    ///
    /// - Parameters:
    ///   - maxMessages: ウィンドウ内の最大送信数（デフォルト: 30）
    ///   - windowDuration: ウィンドウの幅（秒）（デフォルト: 30.0）
    ///   - now: 現在時刻クロージャ（デフォルト: `Date()`）
    init(maxMessages: Int = 30, windowDuration: TimeInterval = 30.0, now: @escaping () -> Date = { Date() }) {
        self.maxMessages = maxMessages
        self.windowDuration = windowDuration
        self.now = now
    }

    // MARK: - メソッド

    /// 送信可能かチェックし、可能であればタイムスタンプを記録する
    ///
    /// ウィンドウ外のタイムスタンプを除去した後、送信数が上限に達していれば `rateLimited` を throw する。
    ///
    /// - Throws: `TwitchIRCClientError.rateLimited(retryAfter:)` — 最古のタイムスタンプが
    ///           ウィンドウ外に出るまでの残り秒数を `retryAfter` に設定して throw する
    mutating func checkAndRecord() throws {
        let current = now()
        // ウィンドウ外の古いタイムスタンプを除去する
        let cutoff = current.addingTimeInterval(-windowDuration)
        timestamps = timestamps.filter { $0 > cutoff }

        if timestamps.count >= maxMessages {
            // 最古のタイムスタンプがウィンドウ外に出るまでの残り秒数を計算する
            let oldestExpiry = timestamps[0].addingTimeInterval(windowDuration)
            let retryAfter = oldestExpiry.timeIntervalSince(current)
            throw TwitchIRCClientError.rateLimited(retryAfter: max(retryAfter, 0))
        }

        timestamps.append(current)
    }

    /// タイムスタンプをすべてリセットする
    ///
    /// 切断時など、送信カウントをゼロに戻す際に呼ぶ。
    mutating func reset() {
        timestamps.removeAll()
    }
}
