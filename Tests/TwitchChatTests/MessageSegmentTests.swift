// MessageSegmentTests.swift
// MessageSegment の単体テスト
// テキストとエモートのセグメント分割ロジックを検証する

import Testing
@testable import TwitchChat

/// MessageSegment のテストスイート
@Suite("MessageSegment テスト")
struct MessageSegmentTests {

    // MARK: - エモートなし

    @Test("エモートなしのテキストは単一の text セグメントになる")
    func エモートなしのテキストは単一のtextセグメントになる() {
        // 前提: エモートが一切ないメッセージ
        let result = MessageSegment.segments(from: "こんにちは！", emotePositions: [])
        // 検証: テキスト全体が1つの .text セグメントになる
        #expect(result == [.text("こんにちは！")])
    }

    @Test("空文字列はエモートなしで単一の text セグメントになる")
    func 空文字列はエモートなしで単一のtextセグメントになる() {
        // 前提: 空のメッセージ
        let result = MessageSegment.segments(from: "", emotePositions: [])
        // 検証: 空テキストの1セグメント
        #expect(result == [.text("")])
    }

    // MARK: - エモートの位置パターン

    @Test("先頭にエモートがある場合を分割できる")
    func 先頭にエモートがある場合を分割できる() {
        // 前提: "Kappa テスト" — Kappa(0-4) がテキスト先頭
        let emotes = [EmotePosition(emoteId: "25", startIndex: 0, endIndex: 4)]
        let result = MessageSegment.segments(from: "Kappa テスト", emotePositions: emotes)
        // 検証: エモート → テキストの2セグメント
        #expect(result.count == 2)
        #expect(result[0] == .emote(id: "25", name: "Kappa"))
        #expect(result[1] == .text(" テスト"))
    }

    @Test("末尾にエモートがある場合を分割できる")
    func 末尾にエモートがある場合を分割できる() {
        // 前提: "テスト Kappa" — Kappa(4-8) がテキスト末尾
        // テ(0) ス(1) ト(2) space(3) K(4) a(5) p(6) p(7) a(8)
        let emotes = [EmotePosition(emoteId: "25", startIndex: 4, endIndex: 8)]
        let result = MessageSegment.segments(from: "テスト Kappa", emotePositions: emotes)
        // 検証: テキスト → エモートの2セグメント
        #expect(result.count == 2)
        #expect(result[0] == .text("テスト "))
        #expect(result[1] == .emote(id: "25", name: "Kappa"))
    }

    @Test("中間にエモートがある場合を分割できる")
    func 中間にエモートがある場合を分割できる() {
        // 前提: "テスト Kappa 配信" — Kappa(4-8) が中間
        let emotes = [EmotePosition(emoteId: "25", startIndex: 4, endIndex: 8)]
        let result = MessageSegment.segments(from: "テスト Kappa 配信", emotePositions: emotes)
        // 検証: テキスト → エモート → テキストの3セグメント
        #expect(result.count == 3)
        #expect(result[0] == .text("テスト "))
        #expect(result[1] == .emote(id: "25", name: "Kappa"))
        #expect(result[2] == .text(" 配信"))
    }

    @Test("複数エモートを含むメッセージを分割できる")
    func 複数エモートを含むメッセージを分割できる() {
        // 前提: "Kappa テスト LUL" — Kappa(0-4)=25、LUL(10-12)=1902
        // K(0) a(1) p(2) p(3) a(4) space(5) テ(6) ス(7) ト(8) space(9) L(10) U(11) L(12)
        let emotes = [
            EmotePosition(emoteId: "25", startIndex: 0, endIndex: 4),
            EmotePosition(emoteId: "1902", startIndex: 10, endIndex: 12)
        ]
        let result = MessageSegment.segments(from: "Kappa テスト LUL", emotePositions: emotes)
        // 検証: エモート → テキスト → エモートの3セグメント
        #expect(result.count == 3)
        #expect(result[0] == .emote(id: "25", name: "Kappa"))
        #expect(result[1] == .text(" テスト "))
        #expect(result[2] == .emote(id: "1902", name: "LUL"))
    }

    @Test("日本語テキストとエモートが混在する場合を正しく分割できる")
    func 日本語テキストとエモートが混在する場合を正しく分割できる() {
        // 前提: "配信中 Kappa おつかれ" — Kappa は UTF-16 オフセット 4-8
        // 「配信中 」は4文字（各1 UTF-16 ユニット）→ オフセット 0-3
        // 「Kappa」は5文字 → オフセット 4-8
        // 「 おつかれ」は残り
        let emotes = [EmotePosition(emoteId: "25", startIndex: 4, endIndex: 8)]
        let result = MessageSegment.segments(from: "配信中 Kappa おつかれ", emotePositions: emotes)
        // 検証: 日本語テキストが正しい範囲で分割される
        #expect(result.count == 3)
        #expect(result[0] == .text("配信中 "))
        #expect(result[1] == .emote(id: "25", name: "Kappa"))
        #expect(result[2] == .text(" おつかれ"))
    }

    @Test("連続する2つのエモートを分割できる")
    func 連続する2つのエモートを分割できる() {
        // 前提: "Kappa Kappa" — 同じエモートが2つ（0-4、6-10）、間にスペース
        let emotes = [
            EmotePosition(emoteId: "25", startIndex: 0, endIndex: 4),
            EmotePosition(emoteId: "25", startIndex: 6, endIndex: 10)
        ]
        let result = MessageSegment.segments(from: "Kappa Kappa", emotePositions: emotes)
        // 検証: エモート → テキスト(スペース) → エモートの3セグメント
        #expect(result.count == 3)
        #expect(result[0] == .emote(id: "25", name: "Kappa"))
        #expect(result[1] == .text(" "))
        #expect(result[2] == .emote(id: "25", name: "Kappa"))
    }

    @Test("メッセージ全体がエモートのみの場合を分割できる")
    func メッセージ全体がエモートのみの場合を分割できる() {
        // 前提: "Kappa" — メッセージ全体が1つのエモート
        let emotes = [EmotePosition(emoteId: "25", startIndex: 0, endIndex: 4)]
        let result = MessageSegment.segments(from: "Kappa", emotePositions: emotes)
        // 検証: エモート1つのみ
        #expect(result.count == 1)
        #expect(result[0] == .emote(id: "25", name: "Kappa"))
    }
}
