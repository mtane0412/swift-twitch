// FlowLayout.swift
// 子ビューを横方向に並べ、はみ出した場合は次の行に折り返すカスタムレイアウト
// チャットメッセージ本文のテキストとエモートを混在させるために使用する

import SwiftUI

/// 横方向に折り返すフローレイアウト
///
/// 各子ビューを左から右に並べ、コンテナ幅を超える場合は次の行に折り返す。
/// テキストセグメントとエモート画像を自然に混在させるために使用する。
///
/// - Note: 各行内の子ビューは垂直方向の中央揃えで配置する（テキストとエモートの高さが揃う）
struct FlowLayout: Layout {

    /// 子ビュー間の水平スペース
    var horizontalSpacing: CGFloat = 0

    /// 行間の垂直スペース
    var verticalSpacing: CGFloat = 2

    // MARK: - Layout キャッシュ

    /// レイアウト計算結果のキャッシュ
    ///
    /// `sizeThatFits` と `placeSubviews` が同じ幅で呼ばれる場合、計算を再利用する。
    struct CacheData {
        var result: LayoutResult
        var maxWidth: CGFloat
    }

    func makeCache(subviews: Subviews) -> CacheData? { nil }

    func updateCache(_ cache: inout CacheData?, subviews: Subviews) {
        // サブビューが変わったらキャッシュを無効化する
        cache = nil
    }

    // MARK: - Layout プロトコル

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let result = computeLayout(subviews: subviews, maxWidth: maxWidth)
        // 次の placeSubviews で再利用できるようキャッシュに保存
        cache = CacheData(result: result, maxWidth: maxWidth)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) {
        // 同じ幅ならキャッシュを再利用し、二重計算を避ける
        let result: LayoutResult
        if let cached = cache, cached.maxWidth == bounds.width {
            result = cached.result
        } else {
            result = computeLayout(subviews: subviews, maxWidth: bounds.width)
        }

        for (index, (origin, size)) in zip(result.origins, result.sizes).enumerated() {
            // 行高に対して垂直中央揃え（テキストとエモートの高さが揃う）
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
    struct LayoutResult {
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
        // 実際に使用した最大幅（maxWidth が .infinity の場合の totalSize 計算に使用）
        var maxUsedWidth: CGFloat = 0

        for subview in subviews {
            // 子ビューのサイズを取得（テキストが折り返せるよう利用可能幅を伝える）
            let proposal = maxWidth.isInfinite
                ? ProposedViewSize.unspecified
                : ProposedViewSize(width: maxWidth, height: nil)
            let size = subview.sizeThatFits(proposal)

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

            // 実際に使用した幅を追跡（trailing spacing は含めない）
            maxUsedWidth = max(maxUsedWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        // 最終行の高さを確定
        rowHeights.append(lineHeight)

        let totalHeight = currentY + lineHeight
        // maxWidth が .infinity の場合は実際の使用幅を返す（.infinity を返すと SwiftUI のレイアウトが壊れる）
        let totalWidth = maxWidth.isInfinite ? maxUsedWidth : maxWidth
        let totalSize = CGSize(width: max(totalWidth, 0), height: max(totalHeight, 0))

        return LayoutResult(
            origins: origins,
            sizes: sizes,
            rowIndices: rowIndices,
            rowHeights: rowHeights,
            totalSize: totalSize
        )
    }
}
