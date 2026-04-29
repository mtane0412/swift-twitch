// StreamPlayerView.swift
// Twitch ライブ配信 AVPlayer の表示ビュー
// StreamPlayerViewModel の state に応じてオーバーレイを切り替える
//
// macOS 26 では SwiftUI の VideoPlayer（_AVKit_SwiftUI 経由）が
// 'So12AVPlayerViewC' の demangling に失敗してクラッシュするため、
// AVPlayerView を NSViewRepresentable で直接ラップして回避する。
//
// AVPlayerNSViewRepresentable は ZStack 最下層に常時配置する。
// state 遷移ごとに makeNSView が再呼び出しされると view.player 再設定で
// rate がリセットされて再生が止まるため、この構造でその問題を回避する。

import AVKit
import SwiftUI

// MARK: - AVPlayerView NSViewRepresentable ラッパー

/// `intrinsicContentSize` を無効化して SwiftUI のレイアウトに完全に従う `AVPlayerView` サブクラス
///
/// 標準の `AVPlayerView` は動画ネイティブ解像度を `intrinsicContentSize` として返し、
/// SwiftUI の `frame(maxWidth: .infinity)` を上書きしてしまう。
/// `noIntrinsicMetric` を返すことで SwiftUI が親から受け取ったサイズをそのまま使えるようにする。
private final class ExpandingAVPlayerView: AVPlayerView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// `AVPlayerView` を SwiftUI から使用するための `NSViewRepresentable` ラッパー
///
/// macOS 26 の `_AVKit_SwiftUI` バイナリ互換バグを回避するため、
/// SwiftUI の `VideoPlayer` の代わりにこのラッパーを使用する。
private struct AVPlayerNSViewRepresentable: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> ExpandingAVPlayerView {
        let view = ExpandingAVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: ExpandingAVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - StreamPlayerView

/// Twitch ライブ配信を表示するビュー
///
/// `AVPlayerNSViewRepresentable` を ZStack 最下層に常時配置し、
/// `StreamPlayerViewModel` の状態に応じてオーバーレイを切り替える:
/// - `.idle`: 黒オーバーレイ（プレイヤーを隠す）
/// - `.resolving`: ProgressView オーバーレイ（読み込み中）
/// - `.playing`: ホバー時のコントロールオーバーレイ（再生/停止・音量）
/// - `.offline`: オフライン表示オーバーレイ
/// - `.error(message:)`: エラー表示 + 再試行ボタンオーバーレイ
struct StreamPlayerView: View {

    var viewModel: StreamPlayerViewModel

    /// マウスがプレイヤー領域に入っているかどうか（コントロールオーバーレイ表示制御）
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // AVPlayer は state によらず常にビュー階層に保持する
            // state 変化で makeNSView が再呼び出しされると view.player 設定で
            // rate がリセットされるため、このビューを常駐させて回避する
            AVPlayerNSViewRepresentable(player: viewModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // state に応じたオーバーレイ（playing 時は透過）
            stateOverlay

            // ホバー時のコントロールオーバーレイ（playing 時のみ）
            if viewModel.state == .playing && isHovered {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)

                StreamPlayerControlsOverlay(viewModel: viewModel)
                    .padding(.leading, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .background(Color.black)
    }

    // MARK: - オーバーレイ

    @ViewBuilder
    private var stateOverlay: some View {
        switch viewModel.state {
        case .idle:
            Color.black
        case .resolving:
            ProgressView("読み込み中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        case .playing:
            EmptyView()
        case .offline:
            offlineView
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - サブビュー

    private var offlineView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("オフライン")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("再生できません")
                .fontWeight(.medium)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("再試行") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
