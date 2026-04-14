// TwitchChatApp.swift
// アプリケーションのエントリポイント
// SwiftUI の App プロトコルに準拠し、メインウィンドウを定義する

import SwiftUI

/// Twitch IRC チャットビューアーのエントリポイント
@main
struct TwitchChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 400, height: 700)
    }
}
