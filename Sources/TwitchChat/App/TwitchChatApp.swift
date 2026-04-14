// TwitchChatApp.swift
// アプリケーションのエントリポイント
// SwiftUI の App プロトコルに準拠し、メインウィンドウを定義する

import SwiftUI

/// Twitch IRC チャットビューアーのアプリ定義
///
/// @main は使わず main.swift でエントリポイントを明示的に指定する
/// （SPM executable ターゲットで NSApplication を正しく初期化するため）
struct TwitchChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 400, height: 700)
    }
}
