// SlashCommandCompletionView.swift
// スラッシュコマンド補完のドロップダウン候補リスト表示ビュー
// 入力バーの上に重ねて表示し、利用可能なコマンド一覧を表示する

import SwiftUI

/// スラッシュコマンド補完候補のドロップダウンビュー
///
/// `ChatInputBar` の `inputForm` に `.overlay` で重ね、入力バーの上方向に表示する。
/// クリックで候補を選択確定できる。キーボード操作は `EmoteRichTextView` が担当する。
struct SlashCommandCompletionView: View {

    /// 表示する候補一覧
    var candidates: [SlashCommandDefinition]

    /// 現在選択中の候補インデックス
    var selectedIndex: Int

    /// 候補を選択したときのコールバック（インデックスを渡す）
    var onSelect: (Int) -> Void

    /// 1行の高さ（ChatInputBar のオフセット計算と共有するため internal）
    static let rowHeight: CGFloat = 32

    /// Divider の高さ（1pt）
    private static let dividerHeight: CGFloat = 1

    /// 最大表示件数（ChatInputBar のオフセット計算と共有するため internal）
    static let maxVisibleRows: Int = 6

    var body: some View {
        let visibleCount = min(candidates.count, Self.maxVisibleRows)
        // Divider を含めた正確な高さ計算（最後の行には Divider なし）
        let listHeight = CGFloat(visibleCount) * Self.rowHeight
            + CGFloat(max(0, visibleCount - 1)) * Self.dividerHeight

        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    candidateRow(candidate: candidate, index: index)
                }
            }
        }
        .frame(height: listHeight)
        .background(Color(.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: -2)
    }

    // MARK: - サブビュー

    /// 候補1件分の行ビュー
    @ViewBuilder
    private func candidateRow(candidate: SlashCommandDefinition, index: Int) -> some View {
        let isSelected = index == selectedIndex
        Button {
            onSelect(index)
        } label: {
            HStack(spacing: 8) {
                // コマンド名と説明文
                VStack(alignment: .leading, spacing: 1) {
                    // コマンド名: monospace 太字で表示
                    Text("/\(candidate.name)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)

                    // 説明文: secondary カラーで表示
                    Text(candidate.description)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("/\(candidate.name): \(candidate.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if index < candidates.count - 1 {
            Divider()
                .padding(.horizontal, 8)
        }
    }
}
