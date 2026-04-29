// StreamPlayerControlsOverlay.swift
// プレイヤーホバー時に左下に表示するシンプルなコントロールオーバーレイ
// 再生/一時停止トグル・ミュートトグル・音量スライダーを提供する

import SwiftUI

/// ライブ配信プレイヤーのオーバーレイコントロール
///
/// - 左から順に: 再生/一時停止ボタン、ミュートボタン、音量スライダー
/// - `StreamPlayerView` 内の `ZStack` に乗せてホバー時のみ表示する
struct StreamPlayerControlsOverlay: View {

    var viewModel: StreamPlayerViewModel

    var body: some View {
        HStack(spacing: 8) {
            // 再生 / 一時停止トグルボタン
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPaused ? "再生" : "一時停止")

            // ミュートトグルボタン（スピーカーアイコン）
            Button {
                viewModel.toggleMute()
            } label: {
                Image(systemName: muteIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isMuted ? "ミュート解除" : "ミュート")

            // 音量スライダー
            Slider(
                value: Binding(
                    get: { Double(viewModel.isMuted ? 0 : viewModel.volume) },
                    set: { viewModel.setVolume(Float($0)) }
                ),
                in: 0 ... 1
            )
            .controlSize(.mini)
            .tint(.white)
            .frame(width: 80)
            .accessibilityLabel("音量")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    /// 音量とミュート状態に応じたスピーカーアイコン名
    private var muteIconName: String {
        if viewModel.isMuted || viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}
