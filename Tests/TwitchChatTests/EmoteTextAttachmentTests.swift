// EmoteTextAttachmentTests.swift
// EmoteTextAttachment および AnimatedEmoteAttachmentViewProvider のテスト

import AppKit
import Testing
@testable import TwitchChat

@Suite("EmoteTextAttachment テスト")
struct EmoteTextAttachmentTests {

    // MARK: - ビュープロバイダ

    @Test("AnimatedEmoteAttachmentViewProvider は NSTextAttachmentViewProvider のサブクラスである")
    func testProviderInheritsFromViewProvider() {
        // 前提: アニメーション再生に必要な TextKit 2 API を使用するため正しい基底クラスが必要
        // 検証: NSTextAttachmentViewProvider を継承している
        #expect(AnimatedEmoteAttachmentViewProvider.self.isSubclass(of: NSTextAttachmentViewProvider.self))
    }

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
}
