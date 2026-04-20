// DTOs.swift
// Persistence 層と既存 Sendable struct の橋渡しとなる Sendable 値型群
// protocol PersistenceService の引数・戻り値に用いる DTO を定義する

import Foundation

/// バッジのスコープ（グローバル / 特定チャンネル）
///
/// BadgeStore のグローバルバッジとチャンネルバッジを PersistenceService で一元管理するための識別子。
enum BadgeScope: Sendable, Hashable {
    case global
    case channel(broadcasterId: String)
}

/// 永続化済みバッジバージョンのスナップショット
///
/// HelixBadgeVersion の永続化境界外向け表現。
/// @Model クラスはリポジトリ境界の外へ出さず、この Sendable struct のみを公開する。
/// 画像 URL はシリアライズ安全性のため String で保持する。
struct BadgeVersionSnapshot: Sendable, Equatable, Hashable {
    /// バッジセットの識別子（例: "broadcaster", "subscriber"）
    let setId: String

    /// バッジのバージョン（例: "1", "6", "1000"）
    let version: String

    /// 1x 解像度の画像 URL 文字列
    let imageUrl1x: String

    /// 2x 解像度の画像 URL 文字列
    let imageUrl2x: String

    /// 4x 解像度の画像 URL 文字列
    let imageUrl4x: String

    /// バッジのタイトル（例: "配信者", "6ヶ月サブスク"）
    let title: String?

    /// バッジの説明文
    let description: String?
}

/// 永続化済みユーザープロフィールのスナップショット
///
/// HelixUserData の永続化境界外向け表現。
/// ProfileImageStore が使用する最小限のフィールドのみを保持する。
/// profileImageUrl は BadgeVersionSnapshot の imageUrl* と同様に String? で保持し、
/// シリアライズ安全性を確保する。呼び出し側で URL(string:) を使って変換すること。
struct UserProfileSnapshot: Sendable, Equatable, Hashable {
    /// Twitch ユーザー ID
    let userId: String

    /// ログイン名（小文字）
    let login: String

    /// 表示名（日本語や大文字を含む場合あり）
    let displayName: String

    /// プロフィール画像の URL 文字列（未設定の場合は nil）
    let profileImageUrl: String?
}

/// 画像キャッシュの論理キー
///
/// エモート・バッジ・プロフィール画像を識別する Sendable 値型。
/// URL ハッシュではなく論理キーを主キーとすることで、CDN の URL 変更に対応できる。
struct ImageCacheKey: Sendable, Hashable {
    /// 画像の種別（emote / badge / profile）
    enum Kind: Sendable, Hashable {
        case emote
        case badge
        case profile
    }

    /// 画像の種別
    let kind: Kind

    /// Kind 固有の識別子文字列
    ///
    /// - emote: `"<emoteId>:<scale>:<variant>"`（variant は "static" または "animated"）
    /// - badge: `"<setId>:<version>:<scale>"`
    /// - profile: `"<userId>"`
    let identifier: String
}
