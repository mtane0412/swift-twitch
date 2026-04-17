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
    ///
    /// `let` で宣言することで初期化後の意図しない変更を防ぐ
    let now: () -> Date

    // MARK: - イニシャライザ

    /// レートリミッターを初期化する
    ///
    /// - Parameters:
    ///   - maxMessages: ウィンドウ内の最大送信数（デフォルト: 30）。1以上を指定すること
    ///   - windowDuration: ウィンドウの幅（秒）（デフォルト: 30.0）。正の値を指定すること
    ///   - now: 現在時刻クロージャ（デフォルト: `Date()`）
    init(maxMessages: Int = 30, windowDuration: TimeInterval = 30.0, now: @escaping () -> Date = { Date() }) {
        precondition(maxMessages > 0, "maxMessages は 1 以上の値を指定してください（指定値: \(maxMessages)）")
        precondition(windowDuration > 0, "windowDuration は正の値を指定してください（指定値: \(windowDuration)）")
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

    /// 直前の `checkAndRecord()` で追加されたタイムスタンプを1件取り消す
    ///
    /// 送信側で `webSocketClient.send` が失敗した場合に呼ぶことで、
    /// 実際には送信されていないメッセージがレートリミットスロットを消費し続けることを防ぐ。
    mutating func rollbackLast() {
        guard !timestamps.isEmpty else { return }
        timestamps.removeLast()
    }

    /// タイムスタンプをすべてリセットする
    ///
    /// 切断時など、送信カウントをゼロに戻す際に呼ぶ。
    mutating func reset() {
        timestamps.removeAll()
    }
}
