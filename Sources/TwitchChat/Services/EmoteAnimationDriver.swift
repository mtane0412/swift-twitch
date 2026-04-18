// EmoteAnimationDriver.swift
// 入力欄のアニメーションエモートを駆動する共有タイマーシングルトン
// 登録された EmoteTextAttachment の image プロパティを GIF フレームに差し替えて疑似アニメーションを実現する

import AppKit

/// アニメーションエモートのフレーム更新を駆動する共有タイマー
///
/// `EmoteTextAttachment` を登録することで、GIF アニメーションのフレームを `image` プロパティ経由で
/// NSTextView に反映する。`NSTextAttachmentViewProvider` を使わないため、ポップオーバー閉鎖時の
/// TextKit 2 viewport 再計算によるビュー消失問題を回避できる。
///
/// ## 動作原理
/// - 50ms（20fps）間隔の共有 Timer でアクティブな全アタッチメントのフレームを更新する
/// - 同一 emoteId のアタッチメントはフレーム計算を共有して CPU コストを最小化する
/// - フレームインデックスが変わらない場合は `image` 更新をスキップする
/// - 全アタッチメント解除時にタイマーを自動停止する
@MainActor
final class EmoteAnimationDriver {

    /// シングルトンインスタンス
    static let shared = EmoteAnimationDriver()

    /// タイマーの更新間隔（秒）。20fps = 0.05 秒
    private static let timerInterval: TimeInterval = 0.05

    /// 実行中のタイマー（nil の場合はタイマー停止中）
    private var timer: Timer?

    /// 登録中のアタッチメント（emoteId をキーとして、同一エモートの全アタッチメントを管理）
    ///
    /// 値の配列には弱参照は使わず、deinit / unregister で明示的に削除する。
    private var registrations: [String: [Weak<EmoteTextAttachment>]] = [:]

    /// emoteId ごとのフレームシーケンスキャッシュ（GIF データから生成、解放は registrations と連動）
    private var frameSequences: [String: GIFFrameSequence] = [:]

    /// タイマー起動からの累積経過時間（秒）
    private var elapsed: TimeInterval = 0

    // MARK: - 初期化

    init() {}

    // MARK: - 登録/解除

    /// アニメーションエモートのアタッチメントを登録する
    ///
    /// - 同一 emoteId の初回登録時に `GIFFrameSequence` を構築する
    /// - アクティブなアタッチメントが 1 件以上になった時点でタイマーを起動する
    ///
    /// - Parameter attachment: 登録する `EmoteTextAttachment`
    func register(_ attachment: EmoteTextAttachment) {
        guard let emoteId = attachment.emoteId else { return }

        // フレームシーケンスを構築（未構築の場合のみ）
        if frameSequences[emoteId] == nil {
            guard let gifData = EmoteImageCache.shared.gifData(for: emoteId),
                  let sequence = GIFFrameSequence(from: gifData) else {
                // GIF データが存在しない・または静止画のため登録しない
                return
            }
            frameSequences[emoteId] = sequence
        }

        // 弱参照リストに追加
        var list = registrations[emoteId] ?? []
        list.append(Weak(attachment))
        registrations[emoteId] = list

        startTimerIfNeeded()
    }

    /// アタッチメントの登録を解除する
    ///
    /// - 全アタッチメント解除時にタイマーを停止し、フレームシーケンスキャッシュも解放する
    ///
    /// - Parameter attachment: 解除する `EmoteTextAttachment`
    func unregister(_ attachment: EmoteTextAttachment) {
        guard let emoteId = attachment.emoteId else { return }

        guard var list = registrations[emoteId] else { return }
        // 対象の弱参照エントリを削除する
        let id = ObjectIdentifier(attachment)
        list.removeAll { $0.objectIdentifier == id || $0.value == nil }

        if list.isEmpty {
            registrations.removeValue(forKey: emoteId)
            frameSequences.removeValue(forKey: emoteId)
        } else {
            registrations[emoteId] = list
        }

        stopTimerIfEmpty()
    }

    // MARK: - タイマー状態（テスト用公開プロパティ）

    /// タイマーが動作中かどうか（テストから参照するための内部プロパティ）
    var isTimerActive: Bool { timer != nil }

    // MARK: - テスト用メソッド

    /// タイマーの実動作を待たずに tick を手動実行する（テスト専用）
    ///
    /// - Parameter elapsed: 現在の累積経過時間（秒）として使用する値
    func tickForTesting(elapsed: TimeInterval) {
        self.elapsed = elapsed
        tick()
    }

    // MARK: - プライベートメソッド

    /// タイマーを開始する（既に動作中の場合は何もしない）
    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: Self.timerInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.elapsed += Self.timerInterval
                self.tick()
            }
        }
    }

    /// 登録アタッチメントが空の場合にタイマーを停止する
    private func stopTimerIfEmpty() {
        let hasActive = registrations.values.contains { list in
            list.contains { $0.value != nil }
        }
        if !hasActive {
            timer?.invalidate()
            timer = nil
            elapsed = 0
        }
    }

    /// 全登録アタッチメントのフレームを現在の経過時間に基づいて更新する
    private func tick() {
        // 解放済みの弱参照を一括クリーンアップする
        var emoteIdsToRemove: [String] = []

        for (emoteId, list) in registrations {
            let alive = list.filter { $0.value != nil }
            if alive.isEmpty {
                emoteIdsToRemove.append(emoteId)
                continue
            }
            registrations[emoteId] = alive

            guard let sequence = frameSequences[emoteId] else { continue }
            guard sequence.totalDuration > 0 else { continue }

            // 経過時間から現在フレームインデックスを計算する
            let loopedElapsed = elapsed.truncatingRemainder(dividingBy: sequence.totalDuration)
            let frameIndex = frameIndex(for: loopedElapsed, in: sequence)

            // 同一 emoteId のアタッチメントは全て同じフレームに更新する
            let frameImage = sequence.frames[frameIndex]
            for weakRef in alive {
                guard let attachment = weakRef.value else { continue }
                // フレームインデックスが変わっていない場合は更新をスキップする
                if attachment.currentFrameIndex == frameIndex { continue }
                attachment.currentFrameIndex = frameIndex
                attachment.image = frameImage
            }
        }

        // 空になった emoteId のエントリを削除する
        for emoteId in emoteIdsToRemove {
            registrations.removeValue(forKey: emoteId)
            frameSequences.removeValue(forKey: emoteId)
        }

        stopTimerIfEmpty()

        // NSTextView に再描画を要求する
        if !registrations.isEmpty {
            NotificationCenter.default.post(name: .emoteFrameDidUpdate, object: nil)
        }
    }

    /// 経過時間からフレームインデックスを計算する
    ///
    /// - Parameters:
    ///   - elapsed: ループ内での経過時間（0 以上 totalDuration 未満）
    ///   - sequence: フレームシーケンス
    /// - Returns: 対応するフレームインデックス
    private func frameIndex(for elapsed: TimeInterval, in sequence: GIFFrameSequence) -> Int {
        var accumulated: TimeInterval = 0
        for (index, duration) in sequence.durations.enumerated() {
            accumulated += duration
            if elapsed < accumulated {
                return index
            }
        }
        // 浮動小数点誤差で最終フレームを超えた場合は末尾フレームを返す
        return sequence.frames.count - 1
    }
}

// MARK: - Notification 名

extension Notification.Name {
    /// EmoteAnimationDriver がフレームを更新した際に post する通知
    ///
    /// `EmoteRichTextView.Coordinator` が受信し `textView.needsDisplay = true` を呼ぶ。
    static let emoteFrameDidUpdate = Notification.Name("emoteFrameDidUpdate")
}

// MARK: - 弱参照ラッパー

/// 弱参照ラッパー（`AnyObject` 準拠の型を弱参照で保持する）
private struct Weak<T: AnyObject> {
    /// 保持対象の ObjectIdentifier（解放後も比較に使用できる）
    let objectIdentifier: ObjectIdentifier

    /// 弱参照（解放済みの場合は nil）
    weak var value: T?

    init(_ value: T) {
        self.objectIdentifier = ObjectIdentifier(value)
        self.value = value
    }
}
