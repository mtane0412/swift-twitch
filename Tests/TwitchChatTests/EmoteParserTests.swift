// EmoteParserTests.swift
// EmoteParser の単体テスト
// Twitch IRC の emotes タグ文字列のパースを検証する

import Testing
@testable import TwitchChat

/// EmoteParser のテストスイート
@Suite("EmoteParser テスト")
struct EmoteParserTests {

    // MARK: - 基本パース

    @Test("空文字列は空配列を返す")
    func 空文字列は空配列を返す() {
        // 前提: emotes タグが空（エモートなし）
        let result = EmoteParser.parse("")
        // 検証: 空配列が返る
        #expect(result.isEmpty)
    }

    @Test("単一エモート・単一位置をパースできる")
    func 単一エモート単一位置をパースできる() {
        // 前提: エモートID 25 がテキスト 0-4 の位置に存在
        // 例: "Kappa" (5文字) が位置 0〜4
        let result = EmoteParser.parse("25:0-4")
        // 検証: 1件のエモート位置情報が返る
        #expect(result.count == 1)
        #expect(result[0].emoteId == "25")
        #expect(result[0].startIndex == 0)
        #expect(result[0].endIndex == 4)
    }

    @Test("単一エモート・複数位置をパースできる")
    func 単一エモート複数位置をパースできる() {
        // 前提: エモートID 25 が 2 箇所に存在
        // 例: "Kappa test Kappa" → 位置 0-4 と 11-15
        let result = EmoteParser.parse("25:0-4,11-15")
        // 検証: 2件のエモート位置情報が返る
        #expect(result.count == 2)
        #expect(result[0].emoteId == "25")
        #expect(result[0].startIndex == 0)
        #expect(result[0].endIndex == 4)
        #expect(result[1].emoteId == "25")
        #expect(result[1].startIndex == 11)
        #expect(result[1].endIndex == 15)
    }

    @Test("複数エモートをパースできる")
    func 複数エモートをパースできる() {
        // 前提: エモートID 25 が位置 0-4、エモートID 1902 が位置 6-10
        // 例: "Kappa LUL" → Kappa=25 は 0-4、LUL=1902 は 6-10
        let result = EmoteParser.parse("25:0-4/1902:6-10")
        // 検証: 2件のエモート位置情報が startIndex 昇順で返る
        #expect(result.count == 2)
        #expect(result[0].emoteId == "25")
        #expect(result[0].startIndex == 0)
        #expect(result[1].emoteId == "1902")
        #expect(result[1].startIndex == 6)
    }

    @Test("startIndex 昇順でソートされる")
    func startIndex昇順でソートされる() {
        // 前提: タグ内でエモートの順序が位置順でない場合がある
        // 後に登場するエモートが先にタグに書かれているケース
        let result = EmoteParser.parse("1902:6-10/25:0-4")
        // 検証: startIndex 昇順（位置順）でソートされる
        #expect(result.count == 2)
        #expect(result[0].emoteId == "25")
        #expect(result[0].startIndex == 0)
        #expect(result[1].emoteId == "1902")
        #expect(result[1].startIndex == 6)
    }

    @Test("単一エモートが 3 箇所に登場する場合をパースできる")
    func 単一エモートが3箇所に登場する場合をパースできる() {
        // 前提: 同じエモートがメッセージ内に 3 回登場する
        let result = EmoteParser.parse("25:0-4,6-10,12-16")
        // 検証: 3件の EmotePosition が startIndex 昇順で返る
        #expect(result.count == 3)
        #expect(result[0].startIndex == 0)
        #expect(result[1].startIndex == 6)
        #expect(result[2].startIndex == 12)
    }

    // MARK: - 不正入力の耐性

    @Test("コロンがない不正形式はスキップされる")
    func コロンがない不正形式はスキップされる() {
        // 前提: エモートIDのみでコロンがない不正なタグ
        let result = EmoteParser.parse("25")
        // 検証: スキップされて空配列が返る
        #expect(result.isEmpty)
    }

    @Test("ハイフンがない不正な位置形式はスキップされる")
    func ハイフンがない不正な位置形式はスキップされる() {
        // 前提: 位置にハイフンがない不正なタグ
        let result = EmoteParser.parse("25:04")
        // 検証: スキップされて空配列が返る
        #expect(result.isEmpty)
    }

    @Test("数値以外の位置はスキップされる")
    func 数値以外の位置はスキップされる() {
        // 前提: 位置に数値以外が含まれる不正なタグ
        let result = EmoteParser.parse("25:a-b")
        // 検証: スキップされて空配列が返る
        #expect(result.isEmpty)
    }

    @Test("正常なエモートと不正なエモートが混在する場合は正常なものだけ返す")
    func 正常なエモートと不正なエモートが混在する場合は正常なものだけ返す() {
        // 前提: 1件目は正常、2件目は不正（コロンなし）
        let result = EmoteParser.parse("25:0-4/invalid")
        // 検証: 正常な1件のみ返る
        #expect(result.count == 1)
        #expect(result[0].emoteId == "25")
    }
}
