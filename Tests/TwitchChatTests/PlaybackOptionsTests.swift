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

    // MARK: - バリデーションテスト

    @Test("supportedCodecs に空文字が含まれる場合は除去される")
    func emptyStringCodecIsFiltered() {
        // 前提: ["avc1", ""] のように空文字を含む配列を渡したとき
        // 検証: supportedCodecs から空文字が除去されること
        let options = PlaybackOptions(lowLatencyEnabled: true, supportedCodecs: ["avc1", ""])
        #expect(options.supportedCodecs == ["avc1"])
    }

    @Test("supportedCodecs がスペースのみのコーデックを含む場合は除去される")
    func whitespaceOnlyCodecIsFiltered() {
        let options = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["  ", "avc1"])
        #expect(options.supportedCodecs == ["avc1"])
    }

    @Test("supportedCodecs が全て無効な場合は avc1 にフォールバックする")
    func emptyCodecsFallbackToAvc1() {
        // 前提: 空配列または空文字のみを渡したとき
        // 検証: supportedCodecs が ["avc1"] にフォールバックすること
        let options = PlaybackOptions(lowLatencyEnabled: true, supportedCodecs: [])
        #expect(options.supportedCodecs == ["avc1"])
    }

    @Test("supportedCodecs の各コーデックは前後のスペースがトリムされる")
    func codecsAreTrimmed() {
        let options = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: [" avc1 ", "hevc"])
        #expect(options.supportedCodecs == ["avc1", "hevc"])
    }
}
