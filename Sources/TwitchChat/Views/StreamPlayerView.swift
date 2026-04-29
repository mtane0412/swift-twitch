// StreamPlayerView.swift
// Twitch ライブ配信 AVPlayer の表示ビュー
// StreamPlayerViewModel の state に応じてプレイヤーまたはオーバーレイを表示する
//
// macOS 26 では SwiftUI の VideoPlayer（_AVKit_SwiftUI 経由）が
// 'So12AVPlayerViewC' の demangling に失敗してクラッシュするため、
// AVPlayerView を NSViewRepresentable で直接ラップして回避する。

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
        view.controlsStyle = .floating
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
/// `StreamPlayerViewModel` の状態に応じて以下を表示する:
/// - `.idle`: 黒背景（Color.black）
/// - `.resolving`: ProgressView（読み込み中）
/// - `.playing`: AVPlayerView（フローティングコントロール付き）
/// - `.offline`: オフライン表示
/// - `.error(message:)`: エラー表示 + 再試行ボタン
struct StreamPlayerView: View {

    var viewModel: StreamPlayerViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .resolving:
                ProgressView("読み込み中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .playing:
                AVPlayerNSViewRepresentable(player: viewModel.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .offline:
                offlineView
            case .error(let message):
                errorView(message: message)
            }
        }
        .background(Color.black)
    }

    // MARK: - サブビュー

    private var idleView: some View {
        Color.black
    }

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
