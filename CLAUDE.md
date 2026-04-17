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

### CI 環境（GitHub Actions）との違い

`Package.swift` は `ProcessInfo.processInfo.environment["CI"]` で環境を判定する。

| 設定 | ローカル (CommandLineTools) | CI (Xcode 16 / Swift 6.0.3) |
|------|----------------------------|------------------------------|
| swift-testing 外部依存 | 使用 | 使用（Xcode 16 と互換） |
| CommandLineTools unsafeFlags | 適用 | 除外 |

- GitHub Actions は `CI=true` を自動設定するため追加設定不要
- ローカルで CI 挙動をエミュレートする `CI=true swift test` はローカルの Swift 6.3 と
  外部パッケージの API 非互換により動作しない（想定内）

## CI

`.github/workflows/ci.yml` に3つのジョブを定義:

1. **build** - `swift build` でコンパイル確認
2. **test** - `swift test --enable-code-coverage` でテスト実行、カバレッジレポートを Artifacts に保存
3. **lint** - SwiftLint でコードスタイル検査

**実行タイミング**: main ブランチへの push および PR 時

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
