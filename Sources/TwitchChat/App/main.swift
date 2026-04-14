// main.swift
// アプリケーションのエントリポイント
// NSApplication を明示的に初期化して GUI アプリとして起動する
// SPM executable ターゲットで SwiftUI App を正しく動作させるための設定

import AppKit
import SwiftUI

// GUI アプリとして起動するためのアクティベーションポリシーを設定
NSApplication.shared.setActivationPolicy(.regular)

// SwiftUI App を起動
TwitchChatApp.main()
