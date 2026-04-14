# CLAUDE.md - TwitchChat プロジェクト

## プロジェクト概要

Twitch IRC チャットをリアルタイム表示する macOS 15+ ネイティブアプリ。
SwiftUI + URLSessionWebSocketTask を使用し、外部依存なし。

## ビルド・テストコマンド

```bash
# ビルド確認
swift build

# テスト実行
swift test

# テスト（特定のテストのみ）
swift test --filter IRCMessageParserTests
```

## プロジェクト構成

- `Sources/TwitchChat/App/` - @main エントリポイント
- `Sources/TwitchChat/Models/` - データモデル（IRCMessage, ChatMessage）
- `Sources/TwitchChat/Services/` - WebSocket / IRC クライアント、パーサー
- `Sources/TwitchChat/ViewModels/` - @Observable ViewModel
- `Sources/TwitchChat/Views/` - SwiftUI ビュー
- `Tests/TwitchChatTests/` - テストファイル

## 重要な環境設定

Xcode 未インストール（CommandLineTools のみ）のため、`Package.swift` の
testTarget に unsafeFlags で Testing フレームワークのパスと rpath を設定済み。
この設定は変更しないこと。

## テスト方針（TDD）

1. テストファイルを先に作成（RED）
2. 最小限の実装でテストをパス（GREEN）
3. リファクタリング（REFACTOR）

テストフレームワーク: **Swift Testing**（`import Testing`）

## Twitch IRC 接続情報

- WebSocket エンドポイント: `wss://irc-ws.chat.twitch.tv:443`
- 匿名接続: `PASS SCHMOOPIIE` + `NICK justinfan12345`（読み取り専用）
- capabilities: `CAP REQ :twitch.tv/tags twitch.tv/commands`
- PING/PONG keepalive が必要（約5分ごと）
