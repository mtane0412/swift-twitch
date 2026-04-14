// ChannelInputView.swift
// チャンネル名入力と接続・切断ボタンを提供するビュー
// ユーザーが Twitch チャンネル名を入力して IRC 接続を開始・終了できる

import SwiftUI

/// チャンネル名入力 UI
///
/// - テキストフィールドでチャンネル名を入力
/// - 接続/切断ボタンで接続状態を切り替え
/// - 接続中はインジケーターを表示
struct ChannelInputView: View {
    @Binding var channelName: String
    let connectionState: ConnectionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("チャンネル名を入力", text: $channelName)
                .textFieldStyle(.roundedBorder)
                .disabled(connectionState == .connected || connectionState == .connecting)
                .onSubmit {
                    if connectionState == .disconnected {
                        onConnect()
                    }
                }

            connectionButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var connectionButton: some View {
        switch connectionState {
        case .disconnected, .error:
            Button("接続") {
                onConnect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(channelName.trimmingCharacters(in: .whitespaces).isEmpty)

        case .connecting:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("接続中...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

        case .connected:
            Button("切断") {
                onDisconnect()
            }
            .buttonStyle(.bordered)
        }
    }
}
