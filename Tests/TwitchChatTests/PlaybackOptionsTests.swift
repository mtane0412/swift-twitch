// PlaybackOptionsTests.swift
// PlaybackOptions の単体テスト
// デフォルト値および各フィールドの初期化・挙動を検証する

import Testing
@testable import TwitchChat

@Suite("PlaybackOptions テスト")
struct PlaybackOptionsTests {

    @Test("PlaybackOptions.default は lowLatencyEnabled が true である")
    func defaultIsLowLatencyEnabled() {
        // PlaybackOptions.default を使うと低遅延モードが有効になること
        let options = PlaybackOptions.default
        #expect(options.lowLatencyEnabled == true)
    }

    @Test("PlaybackOptions.default の supportedCodecs は avc1 のみ")
    func defaultSupportedCodecsIsAvc1Only() {
        // デフォルトのコーデックは avc1 のみであること
        let options = PlaybackOptions.default
        #expect(options.supportedCodecs == ["avc1"])
    }

    @Test("lowLatencyEnabled=false で初期化すると低遅延モードが無効になる")
    func initWithLowLatencyDisabled() {
        let options = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["avc1"])
        #expect(options.lowLatencyEnabled == false)
    }

    @Test("supportedCodecs に複数コーデックを指定して初期化できる")
    func initWithMultipleCodecs() {
        let options = PlaybackOptions(lowLatencyEnabled: true, supportedCodecs: ["avc1", "hevc"])
        #expect(options.supportedCodecs == ["avc1", "hevc"])
    }
}
