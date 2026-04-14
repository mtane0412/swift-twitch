// FlowLayout.swift
// 子ビューを横方向に並べ、はみ出した場合は次の行に折り返すカスタムレイアウト
// チャットメッセージ本文のテキストとエモートを混在させるために使用する

import SwiftUI

/// 横方向に折り返すフローレイアウト
///
/// 各子ビューを左から右に並べ、コンテナ幅を超える場合は次の行に折り返す。
/// テキストセグメントとエモート画像を自然に混在させるために使用する。
///
/// - Note: 各行内の子ビューは垂直方向の中央に揃える（テキストとエモートのベースラインを統一）
struct FlowLayout: Layout {

    /// 子ビュー間の水平スペース
    var horizontalSpacing: CGFloat = 0

    /// 行間の垂直スペース
    var verticalSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let result = computeLayout(subviews: subviews, maxWidth: maxWidth)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = computeLayout(subviews: subviews, maxWidth: bounds.width)
        for (index, (origin, size)) in zip(result.origins, result.sizes).enumerated() {
            // 行高に対して垂直中央揃え
            let rowHeight = result.rowHeights[result.rowIndices[index]]
            let centeredY = origin.y + (rowHeight - size.height) / 2
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + centeredY),
                proposal: ProposedViewSize(size)
            )
        }
    }

    // MARK: - プライベートメソッド

    /// レイアウト計算結果
    private struct LayoutResult {
        /// 各子ビューの配置原点（ローカル座標）
        var origins: [CGPoint]
        /// 各子ビューのサイズ
        var sizes: [CGSize]
        /// 各子ビューが属する行インデックス
        var rowIndices: [Int]
        /// 各行の高さ
        var rowHeights: [CGFloat]
        /// レイアウト全体のサイズ
        var totalSize: CGSize
    }

    /// 全子ビューのレイアウト位置とサイズを計算する
    private func computeLayout(subviews: Subviews, maxWidth: CGFloat) -> LayoutResult {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var rowIndices: [Int] = []

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var currentRow = 0
        var rowHeights: [CGFloat] = []

        for subview in subviews {
            // 子ビューの理想サイズを取得
            let size = subview.sizeThatFits(.unspecified)

            // 現在行にはみ出す場合、かつ行頭でない場合は改行
            if currentX > 0 && currentX + size.width > maxWidth {
                // 現行の行高を確定
                rowHeights.append(lineHeight)
                currentY += lineHeight + verticalSpacing
                currentX = 0
                lineHeight = 0
                currentRow += 1
            }

            origins.append(CGPoint(x: currentX, y: currentY))
            sizes.append(size)
            rowIndices.append(currentRow)

            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        // 最終行の高さを確定
        rowHeights.append(lineHeight)

        let totalHeight = currentY + lineHeight
        let totalSize = CGSize(width: maxWidth, height: max(totalHeight, 0))

        return LayoutResult(
            origins: origins,
            sizes: sizes,
            rowIndices: rowIndices,
            rowHeights: rowHeights,
            totalSize: totalSize
        )
    }
}
