// EmoteDefinition.swift
// Twitch Helix API エモート定義レスポンスモデル
// api.twitch.tv/helix/chat/emotes からエモート一覧を取得するためのDecodable構造体

import Foundation

// MARK: - Helix エモートレスポンス

/// Helix `GET /helix/chat/emotes/global` および
/// `GET /helix/chat/emotes?broadcaster_id={id}` 共通レスポンス
struct HelixEmotesResponse: Decodable, Sendable {
    let data: [HelixEmote]
}

/// Helix エモート定義
///
/// - エモートピッカーでのグリッド表示・テキスト挿入に使用する
/// - `id` は CDN URL 生成（EmoteImageCache）および EmoteImageCache.isAnimated の判定に使用する
/// - `format` に `"animated"` が含まれる場合は GIF アニメーション対応エモート
/// - `emoteSetId` は USERSTATE の `emote-sets` タグと照合してユーザーの使用可否を判定する
struct HelixEmote: Decodable, Sendable, Identifiable, Equatable {
    /// エモート ID（CDN URL 生成に使用）
    let id: String

    /// エモート名（テキスト挿入・検索フィルタに使用）
    let name: String

    /// 対応フォーマット一覧（例: ["static"], ["static", "animated"]）
    let format: [String]

    /// エモート種別（例: "globals", "subscriptions"。省略される場合は nil）
    let emoteType: String?

    /// エモートセット ID（USERSTATE の emote-sets タグと照合して使用可否を判定する。省略される場合は nil）
    ///
    /// グローバルエモートは "0"。チャンネルサブスクエモートはチャンネル固有のID。
    let emoteSetId: String?

    /// アニメーション GIF に対応しているかどうか
    ///
    /// `format` 配列に `"animated"` が含まれる場合は `true`。
    /// `EmoteImageCache.isAnimated(emoteId:)` はキャッシュベースの判定だが、
    /// こちらは API レスポンス由来の確実な判定として使用できる。
    var isAnimated: Bool {
        format.contains("animated")
    }

    /// テスト・楽観的 UI 等で手動生成する際のイニシャライザ
    ///
    /// - Parameters:
    ///   - id: エモート ID
    ///   - name: エモート名
    ///   - format: 対応フォーマット一覧
    ///   - emoteType: エモート種別（省略可能）
    ///   - emoteSetId: エモートセット ID（省略可能。デフォルト nil）
    init(id: String, name: String, format: [String], emoteType: String?, emoteSetId: String? = nil) {
        self.id = id
        self.name = name
        self.format = format
        self.emoteType = emoteType
        self.emoteSetId = emoteSetId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case format
        case emoteType = "emote_type"
        case emoteSetId = "emote_set_id"
    }
}
