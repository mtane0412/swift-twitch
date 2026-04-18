// AuthConfig.swift
// Twitch OAuth の設定値を一元管理するモジュール
// Client ID は環境変数または .env ファイルから読み込む

import Foundation

/// Twitch OAuth の設定値
///
/// Client ID は以下の優先順位で取得する:
/// 1. 環境変数 `TWITCH_CLIENT_ID`
/// 2. 実行ディレクトリの `.env` ファイル内 `TWITCH_CLIENT_ID=xxx`
/// 3. 未設定の場合はアプリ起動時にエラー
enum AuthConfig {

    // MARK: - エンドポイント

    /// Twitch Device Authorization エンドポイント
    static let deviceURL = URL(string: "https://id.twitch.tv/oauth2/device")!

    /// Twitch トークンエンドポイント（デバイスコードポーリングにも使用）
    static let tokenURL = URL(string: "https://id.twitch.tv/oauth2/token")!

    /// Twitch トークン検証エンドポイント
    static let validateURL = URL(string: "https://id.twitch.tv/oauth2/validate")!

    /// Twitch トークン失効エンドポイント
    static let revokeURL = URL(string: "https://id.twitch.tv/oauth2/revoke")!

    // MARK: - OAuth 設定

    /// 必要な OAuth スコープ
    ///
    /// - `chat:read`: IRC チャット読み取り（認証接続に使用）
    /// - `chat:edit`: IRC チャット書き込み（コメント投稿に使用）
    /// - `user:read:follows`: フォロー中の配信中ストリーム一覧取得に使用
    /// - `channel:moderate`: バン・タイムアウト等のモデレーション操作
    /// - `moderator:manage:chat_settings`: エモートオンリー・スロー・サブスクライバーモード等
    /// - `moderator:manage:chat_messages`: チャットクリア・メッセージ削除
    static let scopes: [String] = [
        "chat:read",
        "chat:edit",
        "user:read:follows",
        "channel:moderate",
        "moderator:manage:chat_settings",
        "moderator:manage:chat_messages"
    ]

    // MARK: - Client ID

    /// Twitch アプリの Client ID
    ///
    /// 環境変数 `TWITCH_CLIENT_ID` または `.env` ファイルから取得する
    ///
    /// - Throws: `AuthConfigError.missingClientID` Client ID が設定されていない場合
    static func clientID() throws -> String {
        // 1. 環境変数から取得を試みる
        if let value = ProcessInfo.processInfo.environment["TWITCH_CLIENT_ID"], !value.isEmpty {
            return value
        }
        // 2. .env ファイルから取得を試みる
        if let value = loadClientIDFromEnvFile(), !value.isEmpty {
            return value
        }
        throw AuthConfigError.missingClientID
    }

    /// Twitch アプリの Client Secret（省略可能）
    ///
    /// 環境変数 `TWITCH_CLIENT_SECRET` または `.env` ファイルから取得する
    /// Confidential クライアントとして登録されている場合に必要
    ///
    /// - Returns: Client Secret 文字列。未設定の場合は `nil`
    static func clientSecret() -> String? {
        if let value = ProcessInfo.processInfo.environment["TWITCH_CLIENT_SECRET"], !value.isEmpty {
            return value
        }
        return loadValueFromEnvFile(key: "TWITCH_CLIENT_SECRET")
    }

    // MARK: - プライベートメソッド

    /// `.env` ファイルから `TWITCH_CLIENT_ID` を読み込む（後方互換のためのラッパー）
    private static func loadClientIDFromEnvFile() -> String? {
        loadValueFromEnvFile(key: "TWITCH_CLIENT_ID")
    }

    /// `.env` ファイルから指定キーの値を読み込む
    ///
    /// 以下の順にディレクトリを探索する:
    /// 1. カレントディレクトリ（`swift run` や CLI 実行時）
    /// 2. 実行ファイルの 3 階層上（`.build/debug/TwitchChat` → プロジェクトルート）
    ///
    /// - Parameter key: 読み込むキー名（例: `"TWITCH_CLIENT_ID"`）
    /// - Returns: 見つかった場合は値文字列、見つからない場合は `nil`
    private static func loadValueFromEnvFile(key: String) -> String? {
        var searchDirs: [String] = []

        // 1. カレントディレクトリ
        searchDirs.append(FileManager.default.currentDirectoryPath)

        // 2. 実行ファイルの上位ディレクトリ
        // SPM デバッグビルド: <project>/.build/debug/TwitchChat
        // 3段上 → プロジェクトルート
        if let execPath = Bundle.main.executablePath {
            let execURL = URL(fileURLWithPath: execPath)
            let projectRoot = execURL
                .deletingLastPathComponent()  // debug/
                .deletingLastPathComponent()  // .build/
                .deletingLastPathComponent()  // project root
            searchDirs.append(projectRoot.path)
        }

        for dir in searchDirs {
            if let value = parseEnvFile(at: dir + "/.env", key: key) {
                return value
            }
        }
        return nil
    }

    /// 指定パスの `.env` ファイルを解析して指定キーの値を返す
    ///
    /// - Parameters:
    ///   - path: `.env` ファイルのパス
    ///   - key: 読み込むキー名
    private static func parseEnvFile(at path: String, key: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let lineKey = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if lineKey == key {
                return value
            }
        }
        return nil
    }
}

// MARK: - エラー定義

/// AuthConfig エラー
enum AuthConfigError: Error, LocalizedError {
    /// TWITCH_CLIENT_ID が設定されていない
    case missingClientID

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "TWITCH_CLIENT_ID が設定されていません。環境変数または .env ファイルに設定してください。"
        }
    }
}
