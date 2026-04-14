// MessageSegment.swift
// チャットメッセージのセグメント表現
// テキスト部分とエモート部分を区別して保持し、UI での混合表示を可能にする

import Foundation

/// チャットメッセージの構成要素（テキストまたはエモート）
///
/// IRCメッセージの本文をテキスト部分とエモート部分に分割した結果の1単位を表す。
/// `MessageSegment.segments(from:emotePositions:)` で分割して得られる。
enum MessageSegment: Sendable, Equatable {
    /// 通常のテキスト部分
    case text(String)

    /// エモート部分
    ///
    /// - Parameters:
    ///   - id: Twitch エモートの一意ID（画像URLの生成に使用）
    ///   - name: エモート名（テキスト上の文字列。未取得時のプレースホルダにも使用）
    case emote(id: String, name: String)
}

extension MessageSegment {

    /// メッセージテキストと EmotePosition 配列からセグメント配列を生成する
    ///
    /// Twitch IRC の emotes タグは UTF-16 コードユニットベースのオフセットを使用するため、
    /// Swift の String.Index への変換に `String.Index(utf16Offset:in:)` を使用する。
    ///
    /// - Parameters:
    ///   - text: メッセージ本文（Swift String）
    ///   - emotePositions: `EmoteParser.parse()` の結果（startIndex 昇順であること）
    /// - Returns: テキストとエモートが交互に並ぶセグメント配列
    static func segments(from text: String, emotePositions: [EmotePosition]) -> [MessageSegment] {
        guard !emotePositions.isEmpty else { return [.text(text)] }

        let utf16Count = text.utf16.count
        // startIndex 昇順でソート（念のため）
        let sorted = emotePositions.sorted { $0.startIndex < $1.startIndex }

        var result: [MessageSegment] = []
        // 現在処理済みの末尾 UTF-16 オフセット
        var currentOffset = 0

        for pos in sorted {
            // 範囲チェック: 不正なオフセット・逆転レンジはスキップ
            guard pos.startIndex >= currentOffset,
                  pos.startIndex < utf16Count,
                  pos.endIndex < utf16Count,
                  pos.startIndex <= pos.endIndex else { continue }

            // エモート前のテキスト部分
            if pos.startIndex > currentOffset {
                let start = String.Index(utf16Offset: currentOffset, in: text)
                let end = String.Index(utf16Offset: pos.startIndex, in: text)
                let substr = String(text[start..<end])
                if !substr.isEmpty {
                    result.append(.text(substr))
                }
            }

            // エモート部分（endIndex は inclusive なので +1 して exclusive に変換）
            let emoteStart = String.Index(utf16Offset: pos.startIndex, in: text)
            let emoteEnd = String.Index(utf16Offset: pos.endIndex + 1, in: text)
            let emoteName = String(text[emoteStart..<emoteEnd])
            result.append(.emote(id: pos.emoteId, name: emoteName))

            currentOffset = pos.endIndex + 1
        }

        // 残りのテキスト部分（currentOffset が utf16Count 未満の場合のみ）
        if currentOffset < utf16Count {
            let start = String.Index(utf16Offset: currentOffset, in: text)
            let remaining = String(text[start...])
            if !remaining.isEmpty {
                result.append(.text(remaining))
            }
        }

        // 全エモートがスキップされた場合のフォールバック
        if result.isEmpty { return [.text(text)] }

        return result
    }
}
