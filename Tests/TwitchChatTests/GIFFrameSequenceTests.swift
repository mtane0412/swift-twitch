// GIFFrameSequenceTests.swift
// GIFFrameSequence の単体テスト
// GIF データからフレーム配列とデュレーションを正しく抽出できることを検証する

import AppKit
import ImageIO
import Testing
@testable import TwitchChat

/// GIFFrameSequence のテストスイート
///
/// `GIFFrameSequence` は `@MainActor` 隔離のため、テストスイートも `@MainActor` で実行する。
@Suite("GIFFrameSequence テスト")
@MainActor
struct GIFFrameSequenceTests {

    // MARK: - テスト用 GIF 生成ヘルパー

    /// テスト用アニメーション GIF データを生成する
    ///
    /// - Parameters:
    ///   - frameCount: 生成するフレーム数
    ///   - delaySeconds: 各フレームの表示時間（秒）。デフォルトは 0.1 秒
    /// - Returns: アニメーション GIF のバイナリデータ
    private static func makeAnimatedGIFData(frameCount: Int, delaySeconds: Double = 0.1) -> Data {
        let mutableData = NSMutableData()
        // "com.compuserve.gif" は GIF UTI の標準識別子
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "com.compuserve.gif" as CFString,
            frameCount,
            nil
        ) else {
            preconditionFailure("CGImageDestinationCreateWithData の作成に失敗した")
        }

        // ループ設定（0 = 無限ループ）
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        for index in 0..<frameCount {
            // フレームごとに色相を変えた 1x1px の単色ビットマップを生成する
            let hue = CGFloat(index) / CGFloat(max(frameCount, 1))
            let cgImage = makeSolidColorCGImage(hue: hue, size: CGSize(width: 1, height: 1))
            CGImageDestinationAddImage(destination, cgImage, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delaySeconds]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            preconditionFailure("CGImageDestinationFinalize に失敗した")
        }
        return mutableData as Data
    }

    /// 指定した色相の 1x1px ビットマップ CGImage を生成するヘルパー
    private static func makeSolidColorCGImage(hue: CGFloat, size: CGSize) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("CGContext の作成に失敗した")
        }
        let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        guard let image = context.makeImage() else {
            preconditionFailure("CGContext.makeImage に失敗した")
        }
        return image
    }

    // MARK: - フレーム数抽出

    @Test("3フレームの GIF から 3 枚のフレームが抽出される")
    func 三フレームGIFからフレームを抽出できる() {
        // 前提: 3フレームのアニメーション GIF データを生成する
        let data = Self.makeAnimatedGIFData(frameCount: 3)

        // 実行: GIFFrameSequence を生成する
        let sequence = GIFFrameSequence(from: data)

        // 検証: フレーム数が 3 である
        #expect(sequence != nil)
        #expect(sequence?.frames.count == 3)
    }

    // MARK: - デュレーション抽出

    @Test("GIF の各フレームのデュレーション配列が抽出される")
    func GIFフレームのデュレーション配列が抽出される() throws {
        // 前提: フレームデュレーション 0.2 秒の 2フレーム GIF を生成する
        let data = Self.makeAnimatedGIFData(frameCount: 2, delaySeconds: 0.2)

        // 実行: GIFFrameSequence を生成する
        let seq = try #require(GIFFrameSequence(from: data), "GIFFrameSequence の生成に失敗した")

        // 検証: デュレーション配列の要素数が 2 で、各要素が 0.2 秒に近い
        #expect(seq.durations.count == 2)
        #expect(seq.durations[0] >= 0.19 && seq.durations[0] <= 0.21)
        #expect(seq.durations[1] >= 0.19 && seq.durations[1] <= 0.21)
    }

    @Test("全フレームのデュレーション合計が totalDuration に格納される")
    func 全フレームの合計表示時間が正しく計算される() throws {
        // 前提: デュレーション 0.1 秒の 4フレーム GIF を生成する（合計 0.4 秒）
        let data = Self.makeAnimatedGIFData(frameCount: 4, delaySeconds: 0.1)

        // 実行: GIFFrameSequence を生成する
        let seq = try #require(GIFFrameSequence(from: data), "GIFFrameSequence の生成に失敗した")

        // 検証: totalDuration が各フレームのデュレーション合計と一致する
        let expectedTotal = seq.durations.reduce(0, +)
        #expect(abs(seq.totalDuration - expectedTotal) < 0.001)
    }

    // MARK: - 静止画（1フレーム）

    @Test("1フレームの GIF は静止画のため nil を返す")
    func 一フレームGIFはnilを返す() {
        // 前提: フレーム数 1 の GIF データを生成する（静止画相当）
        let data = Self.makeAnimatedGIFData(frameCount: 1)

        // 実行: GIFFrameSequence を生成する
        let sequence = GIFFrameSequence(from: data)

        // 検証: アニメーションフレームがないため nil が返る
        #expect(sequence == nil)
    }

    // MARK: - 不正データ

    @Test("空のデータは nil を返す")
    func 空のデータはnilを返す() {
        // 前提: 空の Data
        let data = Data()

        // 実行: GIFFrameSequence を生成する
        let sequence = GIFFrameSequence(from: data)

        // 検証: nil が返る
        #expect(sequence == nil)
    }

    @Test("PNG データ（GIF でない）は nil を返す")
    func PNGデータはnilを返す() {
        // 前提: 1x1px の PNG データを CGContext で生成する（lockFocus は描画コンテキストが必要なため使用しない）
        let cgImage = Self.makeSolidColorCGImage(hue: 0.0, size: CGSize(width: 1, height: 1))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data = rep.representation(using: .png, properties: [:]) ?? Data()

        // 実行: GIFFrameSequence を生成する
        let sequence = GIFFrameSequence(from: data)

        // 検証: PNG は単一フレームのため nil が返る
        #expect(sequence == nil)
    }

    // MARK: - フレーム画像サイズ

    @Test("抽出されたフレーム画像の NSImage.size が emoteDisplaySize に設定される")
    func フレーム画像のサイズがemoteDisplaySizeに設定される() throws {
        // 前提: 3フレームの GIF データを生成する
        let data = Self.makeAnimatedGIFData(frameCount: 3)

        // 実行: GIFFrameSequence を生成する
        let seq = try #require(GIFFrameSequence(from: data), "GIFFrameSequence の生成に失敗した")

        // 検証: 各フレームの NSImage.size が emoteDisplaySize × emoteDisplaySize
        let expectedSize = EmoteImageCache.emoteDisplaySize
        for (index, frame) in seq.frames.enumerated() {
            #expect(frame.size.width == expectedSize, "フレーム \(index) の幅が一致しない")
            #expect(frame.size.height == expectedSize, "フレーム \(index) の高さが一致しない")
        }
    }
}
