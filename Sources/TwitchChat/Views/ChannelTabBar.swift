// ChannelTabBar.swift
// 接続中チャンネルのタブバービュー
// Chrome スタイル：左揃えの固定幅タブ、下のボーダーとアクティブタブが繋がって見える構造
//
// ドラッグ並び替えの設計：
//   - ドラッグ中は channelOrder を変更しない（HStack のリレイアウト起因のちらつきを防ぐ）
//   - ドラッグ中のタブ: dragOffset のみで常にカーソルに追従
//   - 他のタブ: ドラッグ中タブが中心を通過した瞬間にアニメーションで退避
//   - channelOrder の更新はドロップ時（onEnded）にのみ行う

import SwiftUI

/// 接続中チャンネルを Chrome スタイルのタブで表示するタブバー
///
/// - タブは左から並び、最大幅 `maxTabWidth` の固定幅で表示する
/// - タブが多い場合は `ScrollView(.horizontal)` で横スクロール可能にする
/// - アクティブタブは非アクティブタブより高く描画され、コンテンツエリアと視覚的に繋がって見える
/// - タブをドラッグすると Chrome 同様にカーソルへ追従し、他タブがリアルタイムに退避する
struct ChannelTabBar: View {

    let channelManager: ChannelManager
    let followedStreamStore: FollowedStreamStore
    let profileImageStore: ProfileImageStore

    /// ドラッグ中のチャンネル名
    @State private var draggingChannel: String?
    /// ドラッグ開始からの累積水平移動量（カーソル追従に使用）
    @State private var dragOffset: CGFloat = 0
    /// ドラッグ開始時の channelOrder 上のインデックス（他タブの退避計算の基準）
    @State private var draggingStartIndex: Int?

    /// 各タブの最大幅
    private static let maxTabWidth: CGFloat = 180
    /// タブバー全体の高さ（アクティブタブは +2pt 分の余白を含む）
    static let height: CGFloat = ChannelTabCell.inactiveHeight + 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // インデックス辞書を ForEach の外で一度だけ構築し tabVisualOffset の O(n^2) を防ぐ
                let indexMap = Dictionary(
                    uniqueKeysWithValues: channelManager.channelOrder.enumerated().map { ($1, $0) }
                )
                ForEach(channelManager.channelOrder, id: \.self) { channel in
                    if channelManager.channels[channel] != nil {
                        let stream = followedStreamStore.stream(forUserLogin: channel)
                        let userId = stream?.userId
                        let name = stream?.userName ?? channel
                        let isDragging = draggingChannel == channel
                        let thisIdx = indexMap[channel] ?? 0
                        let visualOffset = tabVisualOffset(for: channel, at: thisIdx)

                        ChannelTabCell(
                            isSelected: channel == channelManager.selectedChannel,
                            displayName: name,
                            profileImageUrl: userId.flatMap { profileImageStore.profileImageUrl(for: $0) },
                            userId: userId,
                            onSelect: { channelManager.selectChannel(channel) },
                            onClose: { Task { await channelManager.leaveChannel(channel) } }
                        )
                        .frame(width: Self.maxTabWidth)
                        .offset(x: visualOffset)
                        // ドラッグ中のタブを浮き上がらせる
                        .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .bottom)
                        .shadow(radius: isDragging ? 6 : 0, y: isDragging ? -2 : 0)
                        .zIndex(isDragging ? 1 : 0)
                        // ドラッグ中のみ他タブのアニメーションを有効にする
                        // draggingChannel == nil（ドロップ後）は nil を返してドロップ時の余分なアニメーションを防ぐ
                        .animation(
                            (draggingChannel != nil && !isDragging) ? .easeInOut(duration: 0.2) : nil,
                            value: visualOffset
                        )
                        // ChannelTabCell 内の onTapGesture / Button と同時に認識させる
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    if draggingChannel == nil {
                                        draggingChannel = channel
                                        draggingStartIndex = channelManager.channelOrder.firstIndex(of: channel)
                                    }
                                    guard draggingChannel == channel else { return }
                                    // translation はドラッグ開始からの累積値なのでそのまま代入する
                                    dragOffset = value.translation.width
                                }
                                .onEnded { _ in
                                    guard let dragging = draggingChannel,
                                          let startIdx = draggingStartIndex else {
                                        resetDragState()
                                        return
                                    }
                                    // ドロップ位置から最終インデックスを決定して channelOrder を更新する
                                    // withAnimation(nil) で全変化を即座に適用し、ドロップ時のアニメーションを防ぐ
                                    let targetIdx = finalIndex(startIdx: startIdx)
                                    withAnimation(nil) {
                                        channelManager.moveChannel(dragging, toIndex: targetIdx)
                                        resetDragState()
                                    }
                                }
                        )
                    }
                }
            }
            // ScrollView 内でタブを底揃えにする
            .frame(height: Self.height, alignment: .bottom)
        }
        .frame(height: Self.height)
        // タブバー背景: チャット欄（controlBackgroundColor）より明示的に少し暗くする
        .background(Color(.controlBackgroundColor).brightness(-0.05))
    }

    // MARK: - ドラッグ計算

    /// 各タブの視覚的オフセットを返す
    ///
    /// - ドラッグ中のタブ: `dragOffset` でカーソルに完全追従
    /// - 他のタブ: ドラッグ中タブがそのタブの中心を通過した場合にタブ幅分退避する
    /// - `thisIdx` を呼び元で渡すことで、メソッド内での O(n) 探索を排除する
    private func tabVisualOffset(for channel: String, at thisIdx: Int) -> CGFloat {
        guard let draggingCh = draggingChannel,
              let startIdx = draggingStartIndex else { return 0 }

        if channel == draggingCh {
            return dragOffset
        }

        // ドラッグ中タブの現在の視覚的中心 X（タブバー内絶対位置）
        let draggingCenterX = CGFloat(startIdx) * Self.maxTabWidth + Self.maxTabWidth / 2 + dragOffset
        // このタブの元の中心 X
        let thisCenterX = CGFloat(thisIdx) * Self.maxTabWidth + Self.maxTabWidth / 2

        if startIdx < thisIdx && draggingCenterX > thisCenterX {
            // ドラッグ中タブが右方向に通過 → 左にタブ幅分退避
            return -Self.maxTabWidth
        }
        if startIdx > thisIdx && draggingCenterX < thisCenterX {
            // ドラッグ中タブが左方向に通過 → 右にタブ幅分退避
            return Self.maxTabWidth
        }
        return 0
    }

    /// ドロップ時の最終インデックスを計算する
    ///
    /// ドラッグ中タブの最終中心位置をタブ幅で割ってインデックスを決定する
    private func finalIndex(startIdx: Int) -> Int {
        let finalCenterX = CGFloat(startIdx) * Self.maxTabWidth + Self.maxTabWidth / 2 + dragOffset
        // floor を使って負の値でも正しく切り捨てる（Int 変換は 0 方向への truncation のため）
        let raw = Int(floor(finalCenterX / Self.maxTabWidth))
        // channelOrder が空のとき count - 1 が -1 になるため max(..., 0) でガードする
        return min(max(raw, 0), max(channelManager.channelOrder.count - 1, 0))
    }

    /// ドラッグ状態をリセットする
    private func resetDragState() {
        draggingChannel = nil
        dragOffset = 0
        draggingStartIndex = nil
    }
}
