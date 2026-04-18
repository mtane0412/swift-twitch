// EmoteTextAttachmentTests.swift
// EmoteTextAttachment のテスト
// emoteName・emoteId・bounds の保持と currentFrameIndex の初期値を検証する

import AppKit
import Testing
@testable import TwitchChat

@Suite("EmoteTextAttachment テスト")
struct EmoteTextAttachmentTests {

    // MARK: - emoteName 保持

    @Test("emoteName がアタッチメントに正しく保持される")
    func testEmoteNameIsStored() {
        // 前提: 任意のエモート名でアタッチメントを作成する
        let image = NSImage()
        let attachment = EmoteTextAttachment(image: image, emoteName: "PogChamp")

        // 検証: emoteName が保持されている
        #expect(attachment.emoteName == "PogChamp")
    }

    @Test("image プロパティがアタッチメントに正しく設定される")
    func testImageIsStored() {
        // 前提: NSImage を渡してアタッチメントを作成する
        let image = NSImage()
        let attachment = EmoteTextAttachment(image: image, emoteName: "Kappa")

        // 検証: image プロパティに設定されている（TextKit 2 の静止画インライン描画で使用）
        #expect(attachment.image === image)
    }

    // MARK: - bounds

    @Test("bounds がデフォルトの emoteDisplaySize で設定される")
    func testDefaultBounds() {
        // 前提: サイズ指定なしでアタッチメントを作成する
        let image = NSImage()
        let attachment = EmoteTextAttachment(image: image, emoteName: "Kappa")

        // 検証: bounds の幅・高さが emoteDisplaySize と一致する
        #expect(attachment.bounds.width == EmoteImageCache.emoteDisplaySize)
        #expect(attachment.bounds.height == EmoteImageCache.emoteDisplaySize)
    }

    @Test("カスタムサイズで bounds が設定される")
    func testCustomSizeBounds() {
        // 前提: カスタムサイズを指定してアタッチメントを作成する
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "LUL", size: 32)

        // 検証: 指定したサイズで bounds が設定されている
        #expect(attachment.bounds.width == 32)
        #expect(attachment.bounds.height == 32)
    }

    // MARK: - emoteId 保持

    @Test("emoteId を渡さない場合は nil が保持される")
    func emoteIdなしの場合はnilが保持される() {
        // 前提: emoteId を省略してアタッチメントを作成する
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "Kappa")

        // 検証: emoteId が nil である
        #expect(attachment.emoteId == nil)
    }

    @Test("emoteId を渡した場合は正しく保持される")
    func emoteIdが正しく保持される() {
        // 前提: emoteId "25"（Kappa）を指定してアタッチメントを作成する
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "Kappa", emoteId: "25")

        // 検証: emoteId が "25" である
        #expect(attachment.emoteId == "25")
    }

    // MARK: - currentFrameIndex

    @Test("currentFrameIndex の初期値は 0 である")
    func currentFrameIndexの初期値は0である() {
        // 前提: アタッチメントを作成する
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "Kappa", emoteId: "25")

        // 検証: 初期フレームインデックスが 0 である
        #expect(attachment.currentFrameIndex == 0)
    }

    @Test("currentFrameIndex は書き換え可能である")
    func currentFrameIndexは書き換え可能である() {
        // 前提: アタッチメントを作成する
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "Kappa", emoteId: "25")

        // 実行: currentFrameIndex を 2 に設定する
        attachment.currentFrameIndex = 2

        // 検証: 書き換えた値が保持されている
        #expect(attachment.currentFrameIndex == 2)
    }
}
