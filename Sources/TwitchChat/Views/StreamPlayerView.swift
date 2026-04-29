// StreamPlayerView.swift
// Twitch ライブ配信 AVPlayer の表示ビュー
// StreamPlayerViewModel の state に応じてプレイヤーまたはオーバーレイを表示する

import AVKit
import SwiftUI

/// Twitch ライブ配信を表示するビュー
///
/// `StreamPlayerViewModel` の状態に応じて以下を表示する:
/// - `.idle` / `.resolving`: ProgressView
/// - `.playing`: AVKit VideoPlayer（標準コントロール付き）
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
                VideoPlayer(player: viewModel.player)
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
