// MentionCompletionView.swift
// @メンション補完のドロップダウン候補リスト表示ビュー
// 入力バーの上に重ねて表示し、ユーザー名候補を一覧する

import SwiftUI

/// @メンション補完候補のドロップダウンビュー
///
/// `ChatInputBar` の `inputForm` に `.overlay` で重ね、入力バーの上方向に表示する。
/// クリックで候補を選択確定できる。キーボード操作は `EmoteRichTextView` が担当する。
struct MentionCompletionView: View {

    /// 表示する候補一覧
    var candidates: [MentionStore.UserCandidate]

    /// 現在選択中の候補インデックス
    var selectedIndex: Int

    /// 候補を選択したときのコールバック（インデックスを渡す）
    var onSelect: (Int) -> Void

    /// 1行の高さ
    private static let rowHeight: CGFloat = 32

    /// Divider の高さ（1pt）
    private static let dividerHeight: CGFloat = 1

    /// 最大表示件数
    private static let maxVisibleRows: Int = 6

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
    private func candidateRow(candidate: MentionStore.UserCandidate, index: Int) -> some View {
        let isSelected = index == selectedIndex
        Button {
            onSelect(index)
        } label: {
            HStack(spacing: 8) {
                // ユーザー名（displayName を優先表示）
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)

                    // displayName と username が異なる場合のみ username をサブテキストで表示
                    if candidate.displayName.lowercased() != candidate.username {
                        Text("@\(candidate.username)")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .frame(height: Self.rowHeight)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.displayName)（@\(candidate.username)）")
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if index < candidates.count - 1 {
            Divider()
                .padding(.horizontal, 8)
        }
    }
}
