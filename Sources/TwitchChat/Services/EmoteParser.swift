// EmoteParser.swift
// Twitch IRC の emotes タグをパースするユーティリティ
// `emotes` タグ値からエモートIDとテキスト内の位置情報を抽出する

import Foundation

/// エモートのテキスト内位置情報
///
/// Twitch IRC の `emotes` タグ値（例: `25:0-4,12-16`）をパースした1エントリを表す。
/// 位置は UTF-16 コードユニットベースのオフセット（0-based）。
struct EmotePosition: Sendable, Equatable {
    /// Twitch エモートの一意ID（例: "25", "1902"）
    let emoteId: String

    /// テキスト内の開始位置（UTF-16 オフセット、0-based）
    let startIndex: Int

    /// テキスト内の終了位置（UTF-16 オフセット、inclusive）
    let endIndex: Int
}

/// Twitch IRC の emotes タグパーサー
///
/// emotes タグ形式: `emoteId:start-end,start-end/emoteId:start-end`
/// - スラッシュ区切りで各エモートIDグループ
/// - コロン後にカンマ区切りで位置範囲リスト
/// - 位置は UTF-16 コードユニットベースのインデックス
///
/// - Note: 副作用なしの純粋関数で実装し、テスト容易性を確保する
enum EmoteParser {

    /// emotes タグ文字列をパースして EmotePosition の配列を返す
    ///
    /// - Parameter emotesTag: Twitch IRC の emotes タグ値（例: `"25:0-4,12-16/1902:6-10"`）
    /// - Returns: startIndex 昇順にソートされた EmotePosition の配列。
    ///   空文字列または不正形式の場合は空配列を返す。
    static func parse(_ emotesTag: String) -> [EmotePosition] {
        guard !emotesTag.isEmpty else { return [] }

        var result: [EmotePosition] = []

        // スラッシュ区切りで各エモートIDグループに分割
        let emoteGroups = emotesTag.split(separator: "/", omittingEmptySubsequences: true)
        for group in emoteGroups {
            // コロンでエモートIDと位置リストに分割
            let parts = group.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let emoteId = String(parts[0])
            let positionsString = String(parts[1])

            // カンマ区切りで各位置範囲に分割
            let positions = positionsString.split(separator: ",", omittingEmptySubsequences: true)
            for position in positions {
                // ハイフンで開始位置と終了位置に分割
                let range = position.split(separator: "-", maxSplits: 1)
                guard range.count == 2,
                      let start = Int(range[0]),
                      let end = Int(range[1]),
                      start >= 0, end >= 0,
                      start <= end else { continue }

                result.append(EmotePosition(emoteId: emoteId, startIndex: start, endIndex: end))
            }
        }

        // startIndex 昇順でソート
        return result.sorted { $0.startIndex < $1.startIndex }
    }
}
