// SettingsView.swift
// アプリケーション設定画面
// Cmd+, から開く macOS 標準の Settings Scene に対応する

import SwiftUI

/// アプリケーション設定画面
///
/// ライブプレイヤー（実験的機能）の Opt-in トグルなどを提供する。
struct SettingsView: View {

    /// ライブ配信プレイヤー機能の有効・無効（永続化）
    ///
    /// Twitch GQL は非公式 API のため、デフォルト OFF の Opt-in とする。
    @AppStorage("livePlayerEnabled") private var livePlayerEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Twitch ライブ配信を再生する（実験的機能）", isOn: $livePlayerEnabled)
                Text("Twitch の非公式 API を使用して配信映像を直接再生します。Twitch 利用規約上グレーな機能のため、デフォルトは無効になっています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("プレイヤー")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400, height: 160)
    }
}
