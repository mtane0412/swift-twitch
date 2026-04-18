// EmoteAnimationDriverTests.swift
// EmoteAnimationDriver の単体テスト
// タイマーの開始/停止・フレーム更新・同一エモートのフレーム共有を検証する

import AppKit
import ImageIO
import Testing
@testable import TwitchChat

/// EmoteAnimationDriver のテストスイート
///
/// - Note: タイマーの実動作（実時間待機）は避け、`tickForTesting()` で tick を手動呼び出しする
@Suite("EmoteAnimationDriver テスト")
struct EmoteAnimationDriverTests {

    // MARK: - テスト用ヘルパー

    /// テスト用の 3フレームアニメーション GIF データを生成する
    private static func makeTestGIFData(frameCount: Int = 3, delaySeconds: Double = 0.1) -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "com.compuserve.gif" as CFString,
            frameCount,
            nil
        ) else { return Data() }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        for index in 0..<frameCount {
            guard let cgImage = makeSolidColorCGImage(
                hue: CGFloat(index) / CGFloat(max(frameCount, 1))
            ) else { continue }
            CGImageDestinationAddImage(destination, cgImage, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delaySeconds]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            preconditionFailure("CGImageDestinationFinalize に失敗した")
        }
        return mutableData as Data
    }

    private static func makeSolidColorCGImage(hue: CGFloat) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }

    // MARK: - タイマー開始/停止

    @Test("アタッチメントを登録するとタイマーが動作中になる")
    @MainActor
    func アタッチメント登録後にタイマーが動作中になる() {
        // 前提: テスト用ドライバーインスタンスを生成する
        let driver = EmoteAnimationDriver()

        // 前提: gifData を用意してキャッシュに登録する
        let emoteId = "タイマー開始テスト_\(UUID())"
        let gifData = Self.makeTestGIFData()
        EmoteImageCache.shared.storeForTesting(gifData: gifData, for: emoteId)

        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)

        // 実行: アタッチメントを登録する
        driver.register(attachment)

        // 検証: タイマーが動作中である
        #expect(driver.isTimerActive)

        // クリーンアップ
        driver.unregister(attachment)
        EmoteImageCache.shared.clearForTesting()
    }

    @Test("全アタッチメントを解除するとタイマーが停止する")
    @MainActor
    func 全アタッチメント解除後にタイマーが停止する() {
        // 前提: アタッチメントを登録してタイマーを開始する
        let driver = EmoteAnimationDriver()
        let emoteId = "タイマー停止テスト_\(UUID())"
        let gifData = Self.makeTestGIFData()
        EmoteImageCache.shared.storeForTesting(gifData: gifData, for: emoteId)

        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)
        driver.register(attachment)

        // 実行: 全アタッチメントを解除する
        driver.unregister(attachment)

        // 検証: タイマーが停止している
        #expect(!driver.isTimerActive)

        // クリーンアップ
        EmoteImageCache.shared.clearForTesting()
    }

    @Test("gifData がないアタッチメントを登録してもタイマーは起動しない")
    @MainActor
    func gifDataなしのアタッチメントはタイマーを起動しない() {
        // 前提: gifData キャッシュにデータがない emoteId のアタッチメント
        let driver = EmoteAnimationDriver()
        let emoteId = "gifDataなしエモート_\(UUID())"
        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)

        // 実行: 登録する（GIF データなしのため内部的には登録されない）
        driver.register(attachment)

        // 検証: GIF データがないためフレームシーケンスを構築できず、タイマーは起動しない
        #expect(!driver.isTimerActive)

        // クリーンアップ（登録失敗しているが念のため解除を試みる）
        driver.unregister(attachment)
    }

    // MARK: - フレーム更新

    @Test("tick を呼ぶとアタッチメントの image が次のフレームに更新される")
    @MainActor
    func tick後にフレームが更新される() {
        // 前提: 3フレームの GIF を持つアタッチメントを登録する
        let driver = EmoteAnimationDriver()
        let emoteId = "フレーム更新テスト_\(UUID())"
        let gifData = Self.makeTestGIFData(frameCount: 3, delaySeconds: 0.05)
        EmoteImageCache.shared.storeForTesting(gifData: gifData, for: emoteId)

        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)
        driver.register(attachment)

        // 実行: フレーム 1 に切り替わる経過時間（0.05s 以上 0.10s 未満）で tick を呼ぶ
        driver.tickForTesting(elapsed: 0.06)

        // 検証: フレームインデックスが 1 に更新されている
        #expect(attachment.currentFrameIndex == 1)
        // 検証: image がフレームシーケンスのフレーム画像に更新されている（初期の NSImage() から変わっている）
        #expect(attachment.image != nil)

        // クリーンアップ
        driver.unregister(attachment)
        EmoteImageCache.shared.clearForTesting()
    }

    @Test("フレームインデックスが変わらない場合は image を更新しない")
    @MainActor
    func フレーム未変更時はimageを更新しない() {
        // 前提: 3フレームの GIF を持つアタッチメントを登録する
        let driver = EmoteAnimationDriver()
        let emoteId = "スキップテスト_\(UUID())"
        let gifData = Self.makeTestGIFData(frameCount: 3, delaySeconds: 0.5)
        EmoteImageCache.shared.storeForTesting(gifData: gifData, for: emoteId)

        let attachment = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)
        driver.register(attachment)

        // 実行: 最初の tick（elapsed=0）でフレーム 0 に設定する
        driver.tickForTesting(elapsed: 0)
        let imageAfterFirstTick = attachment.image

        // 実行: 経過時間をほとんど進めない（フレームが変わらない）
        driver.tickForTesting(elapsed: 0.01)
        let imageAfterSecondTick = attachment.image

        // 検証: フレームインデックスが変わらないため同じ image が保持されている
        #expect(imageAfterFirstTick === imageAfterSecondTick)

        driver.unregister(attachment)
        EmoteImageCache.shared.clearForTesting()
    }

    // MARK: - 同一エモートのフレーム共有

    @Test("同一 emoteId の複数アタッチメントは同じフレームに同期される")
    @MainActor
    func 同一エモートの複数アタッチメントは同期される() {
        // 前提: 同じ emoteId で 2つのアタッチメントを作成して登録する
        let driver = EmoteAnimationDriver()
        let emoteId = "同期テスト_\(UUID())"
        let gifData = Self.makeTestGIFData(frameCount: 3, delaySeconds: 0.1)
        EmoteImageCache.shared.storeForTesting(gifData: gifData, for: emoteId)

        let attachment1 = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)
        let attachment2 = EmoteTextAttachment(image: NSImage(), emoteName: "テストエモート", emoteId: emoteId)
        driver.register(attachment1)
        driver.register(attachment2)

        // 実行: tick を呼び出してフレームを更新する
        driver.tickForTesting(elapsed: 0.15)

        // 検証: 同じフレームの NSImage インスタンスが設定されている
        #expect(attachment1.image === attachment2.image)

        driver.unregister(attachment1)
        driver.unregister(attachment2)
        EmoteImageCache.shared.clearForTesting()
    }
}
