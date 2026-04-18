// GIFFrameSequence.swift
// GIF データからアニメーションフレーム配列と表示時間を抽出するデータ構造
// ImageIO フレームワークの CGImageSource API を使用してフレームを分解する

import AppKit
import ImageIO

/// GIF アニメーションのフレーム配列と表示時間を保持する不変データ構造
///
/// `CGImageSource` を使って GIF バイナリから全フレームを分解し、
/// `EmoteAnimationDriver` がタイマー駆動でフレームを切り替えるために使用する。
///
/// `NSImage` は `Sendable` 非準拠のため `@MainActor` に隔離する。
/// これによりコンパイル時に MainActor 外からの誤用を防ぐ。
///
/// - Note: 静止画（フレーム数 1 以下）の場合は `init` が nil を返す
@MainActor
struct GIFFrameSequence {

    /// 各フレームの NSImage（`EmoteImageCache.emoteDisplaySize` にリサイズ済み）
    let frames: [NSImage]

    /// 各フレームの表示時間（秒）。`frames` と要素数が一致する
    let durations: [TimeInterval]

    /// 全フレームの合計表示時間（秒）
    let totalDuration: TimeInterval

    /// GIF バイナリデータからフレームを抽出して初期化する
    ///
    /// - Parameter data: GIF フォーマットのバイナリデータ
    /// - Returns: フレーム数が 2 以上の場合はインスタンス、1 以下（静止画）または解析失敗時は nil
    init?(from data: Data) {
        // CGImageSource を生成する
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let frameCount = CGImageSourceGetCount(source)
        // フレーム数が 1 以下は静止画のため対象外
        guard frameCount > 1 else { return nil }

        let displaySize = EmoteImageCache.emoteDisplaySize
        var extractedFrames: [NSImage] = []
        var extractedDurations: [TimeInterval] = []

        for index in 0..<frameCount {
            // 各フレームの CGImage を取得する
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }

            // GIF フレームのデュレーションを取得する
            let duration = Self.frameDuration(source: source, index: index)

            // NSImage として格納し、表示サイズを設定する
            // NSImage.size を emoteDisplaySize に設定してテキスト行高に揃える
            let image = NSImage(size: NSSize(width: displaySize, height: displaySize))
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

            extractedFrames.append(image)
            extractedDurations.append(duration)
        }

        guard !extractedFrames.isEmpty else { return nil }

        self.frames = extractedFrames
        self.durations = extractedDurations
        self.totalDuration = extractedDurations.reduce(0, +)
    }

    // MARK: - プライベートメソッド

    /// CGImageSource から指定フレームのデュレーション（秒）を取得する
    ///
    /// 取得優先順位:
    /// 1. `kCGImagePropertyGIFUnclampedDelayTime`（GIF 仕様準拠の正確な値）
    /// 2. `kCGImagePropertyGIFDelayTime`（後方互換用）
    /// 3. 取得不可の場合は 0.1 秒（GIF デファクトスタンダードのフォールバック）
    ///
    /// - Note: 0.01 秒未満（10ms 未満）は 0.01 秒にクランプする。
    ///   一部の GIF は意図的に 0 を指定しているが、CPU 過負荷を防ぐために下限を設ける。
    ///
    /// - Parameters:
    ///   - source: CGImageSource
    ///   - index: フレームインデックス
    /// - Returns: フレームの表示時間（秒）
    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        let unclampedDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clampedDelay = gifDict[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let rawDelay = unclampedDelay ?? clampedDelay ?? 0.1

        // 10ms 未満は 10ms にクランプして CPU 過負荷を防ぐ
        return max(rawDelay, 0.01)
    }
}
