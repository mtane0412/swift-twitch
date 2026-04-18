// SlashCommandCompletionViewModel.swift
// / スラッシュコマンド補完の状態管理 ViewModel
// / トリガーの検出、候補フィルタリング、選択操作を担当する

import Foundation
import Observation

/// スラッシュコマンド補完の状態管理 ViewModel
///
/// 入力テキストを監視し、先頭の `/` トリガーを検出してコマンド候補リストを管理する。
/// キーボード操作（上下移動・確定・キャンセル）のロジックも提供する。
///
/// - Note: `EmoteRichTextView` の `textDidChange` / `doCommandBy` から呼び出す
/// - Note: `@` メンション補完と排他的に動作する（テキスト先頭が `/` の場合のみアクティブ化）
@Observable
@MainActor
final class SlashCommandCompletionViewModel {

    // MARK: - パブリックプロパティ

    /// 補完がアクティブ状態かどうか
    private(set) var isActive: Bool = false

    /// 現在の候補一覧（allCommands をフィルタリングした結果）
    private(set) var candidates: [SlashCommandDefinition] = []

    /// 選択中の候補インデックス
    private(set) var selectedIndex: Int = 0

    /// テキスト内の / から現在クエリ末尾までの NSRange（UTF-16 基準、置換に使用）
    private(set) var commandRange: NSRange?

    // MARK: - パブリックメソッド

    /// テキストとカーソル位置から / トークンを検出し候補を更新する
    ///
    /// テキストの先頭が `/` で始まり、かつ `/` の後にスペースが含まれない場合のみアクティブ化する。
    ///
    /// - Parameters:
    ///   - text: 入力テキスト全体（plainText ベースの文字列）
    ///   - cursorPosition: カーソル位置（plainText 上の Character 数）
    func updateFromText(_ text: String, cursorPosition: Int) {
        let clampedPosition = max(0, min(cursorPosition, text.count))
        let cursorIndex = text.index(text.startIndex, offsetBy: clampedPosition)
        let textUpToCursor = String(text[..<cursorIndex])

        guard let tokenInfo = findSlashToken(in: textUpToCursor) else {
            deactivate()
            return
        }

        commandRange = NSRange(location: 0, length: tokenInfo.tokenNSLength)

        let newCandidates = SlashCommandDefinition.allCommands.filter { command in
            if tokenInfo.query.isEmpty { return true }
            return command.name.lowercased().hasPrefix(tokenInfo.query.lowercased())
        }
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
    /// - Returns: `/command ` 形式の文字列。候補が空の場合は `nil`
    func confirmSelection() -> String? {
        guard isActive, !candidates.isEmpty, selectedIndex < candidates.count else {
            return nil
        }
        let candidate = candidates[selectedIndex]
        deactivate()
        return "/\(candidate.name) "
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
        commandRange = nil
    }

    /// カーソル前のテキストからスラッシュトークンを検出する
    ///
    /// テキストの先頭が `/` で始まり、`/` の後にスペースが含まれない場合のみトークンとして認識する。
    ///
    /// - Parameter textUpToCursor: カーソルまでのテキスト
    /// - Returns: トークン情報。スラッシュコマンドが見つからない場合は `nil`
    private func findSlashToken(in textUpToCursor: String) -> SlashTokenInfo? {
        // テキスト先頭が / で始まる場合のみトリガー
        guard textUpToCursor.hasPrefix("/") else {
            return nil
        }

        // / 以降のクエリ文字列を取得（先頭の / を除く）
        let afterSlash = String(textUpToCursor.dropFirst())

        // クエリにホワイトスペースが含まれる場合はトークン終了（引数入力フェーズ）
        guard !afterSlash.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        // "/" は BMP 文字で常に 1 UTF-16 code unit
        let tokenNSLength = 1 + afterSlash.utf16.count

        return SlashTokenInfo(
            query: afterSlash,
            tokenNSLength: tokenNSLength
        )
    }
}

// MARK: - 内部型

/// スラッシュトークンの検出結果
private struct SlashTokenInfo {
    /// / 以降のクエリ文字列（例: "ban", ""）
    let query: String
    /// トークン全体の UTF-16 長さ（/ + クエリ）
    let tokenNSLength: Int
}
