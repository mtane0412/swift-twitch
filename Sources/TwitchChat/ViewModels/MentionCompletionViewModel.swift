// MentionCompletionViewModel.swift
// @メンション補完の状態管理 ViewModel
// @ トリガーの検出、候補フィルタリング、選択操作を担当する

import Foundation
import Observation

/// @メンション補完の状態管理 ViewModel
///
/// 入力テキストを監視し、`@` トリガーを検出して候補リストを管理する。
/// キーボード操作（上下移動・確定・キャンセル）のロジックも提供する。
///
/// - Note: `EmoteRichTextView` の `textDidChange` / `doCommandBy` から呼び出す
@Observable
@MainActor
final class MentionCompletionViewModel {

    // MARK: - パブリックプロパティ

    /// 補完がアクティブ状態かどうか
    private(set) var isActive: Bool = false

    /// 現在の候補一覧
    private(set) var candidates: [MentionStore.UserCandidate] = []

    /// 選択中の候補インデックス
    private(set) var selectedIndex: Int = 0

    /// テキスト内の @ から現在カーソルまでの NSRange（UTF-16 基準、置換に使用）
    private(set) var mentionRange: NSRange?

    // MARK: - プライベートプロパティ

    private let mentionStore: MentionStore

    // MARK: - 初期化

    init(mentionStore: MentionStore) {
        self.mentionStore = mentionStore
    }

    // MARK: - パブリックメソッド

    /// テキストとカーソル位置から @ トークンを検出し候補を更新する
    ///
    /// カーソル直前の文字列を走査して `@` を探す。
    /// `@` の直前が空白または文頭の場合のみトリガーとして認識する。
    ///
    /// - Parameters:
    ///   - text: 入力テキスト全体（plainText ベースの文字列）
    ///   - cursorPosition: カーソル位置（plainText 上の Character 数）
    func updateFromText(_ text: String, cursorPosition: Int) {
        // String.Index ベースで切り出すことで Character と UTF-16 の不整合を回避する
        let clampedPosition = max(0, min(cursorPosition, text.count))
        let cursorIndex = text.index(text.startIndex, offsetBy: clampedPosition)
        let textUpToCursor = String(text[..<cursorIndex])

        guard let tokenInfo = findMentionToken(in: textUpToCursor) else {
            deactivate()
            return
        }

        mentionRange = NSRange(location: tokenInfo.atNSLocation, length: tokenInfo.tokenNSLength)

        let newCandidates = mentionStore.candidates(matching: tokenInfo.query)
        candidates = newCandidates
        selectedIndex = 0
        isActive = true
    }

    /// 選択インデックスを移動する
    ///
    /// 候補リストの境界でクランプする（ラップしない）。
    ///
    /// - Parameter offset: 移動量（正: 下、負: 上）
    func moveSelection(by offset: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(0, min(candidates.count - 1, selectedIndex + offset))
    }

    /// 選択インデックスを直接指定する
    ///
    /// 範囲外の値はクランプする。
    ///
    /// - Parameter index: 設定するインデックス
    func setSelection(to index: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(0, min(candidates.count - 1, index))
    }

    /// 選択中の候補を確定し、挿入文字列を返す
    ///
    /// - Returns: `@username ` 形式の文字列。候補が空の場合は `nil`
    func confirmSelection() -> String? {
        guard isActive, !candidates.isEmpty, selectedIndex < candidates.count else {
            return nil
        }
        let candidate = candidates[selectedIndex]
        deactivate()
        return "@\(candidate.username) "
    }

    /// 補完をキャンセルしてアクティブ状態を解除する
    func cancel() {
        deactivate()
    }

    // MARK: - プライベートメソッド

    /// アクティブ状態を解除してリセットする
    private func deactivate() {
        isActive = false
        candidates = []
        selectedIndex = 0
        mentionRange = nil
    }

    /// カーソル前のテキストからメンショントークンを検出する
    ///
    /// - Parameter textUpToCursor: カーソルまでのテキスト
    /// - Returns: トークン情報。メンションが見つからない場合は `nil`
    private func findMentionToken(in textUpToCursor: String) -> MentionTokenInfo? {
        // 末尾から @ を逆方向に検索
        guard let atRange = textUpToCursor.range(of: "@", options: .backwards) else {
            return nil
        }

        // 文字数ベースのインデックス（isWhitespace チェック用）
        let atCharIndex = textUpToCursor.distance(from: textUpToCursor.startIndex, to: atRange.lowerBound)

        // @ の直前が空白または文頭であることを確認（メールアドレス等の誤検出防止）
        if atCharIndex > 0 {
            let beforeAt = textUpToCursor[textUpToCursor.index(before: atRange.lowerBound)]
            guard beforeAt.isWhitespace else {
                return nil
            }
        }

        // @ 以降のクエリ文字列を取得
        let afterAt = String(textUpToCursor[atRange.upperBound...])

        // クエリにホワイトスペースが含まれる場合はトークン終了（補完対象外）
        guard !afterAt.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        // UTF-16 オフセットを計算（NSRange / NSTextView との整合性のため）
        let atNSLocation = textUpToCursor.utf16.distance(
            from: textUpToCursor.utf16.startIndex,
            to: atRange.lowerBound.samePosition(in: textUpToCursor.utf16)!
        )
        // "@" は BMP 文字で常に 1 UTF-16 code unit
        let tokenNSLength = 1 + afterAt.utf16.count

        return MentionTokenInfo(
            atNSLocation: atNSLocation,
            query: afterAt,
            tokenNSLength: tokenNSLength
        )
    }
}

// MARK: - 内部型

/// メンショントークンの検出結果
private struct MentionTokenInfo {
    /// テキスト内の @ の UTF-16 オフセット（NSRange 用）
    let atNSLocation: Int
    /// @ 以降のクエリ文字列
    let query: String
    /// トークン全体の UTF-16 長さ（@ + クエリ）
    let tokenNSLength: Int
}
