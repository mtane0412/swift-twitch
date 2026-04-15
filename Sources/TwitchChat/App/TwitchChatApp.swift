// TwitchChatApp.swift
// アプリケーションのエントリポイント
// SwiftUI の App プロトコルに準拠し、メインウィンドウを定義する

import SwiftUI

/// Twitch IRC チャットビューアーのアプリ定義
///
/// @main は使わず main.swift でエントリポイントを明示的に指定する
/// （SPM executable ターゲットで NSApplication を正しく初期化するため）
struct TwitchChatApp: App {
    /// アプリ全体で共有する認証状態
    @State private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            ContentView(authState: authState)
                .task {
                    // アプリ起動時に保存済みセッションを復元する
                    await authState.restoreSession()
                }
        }
        .defaultSize(width: 400, height: 700)
    }
}
