// EmotePickerSection.swift
// エモートピッカーのセクション定義モデル
// エモートをチャンネルごとに分類してピッカーのセクション表示に使用する

import Foundation

/// エモートピッカーのセクション
///
/// エモートをチャンネルごとに分類して表示するためのモデル。
/// - `currentChannel`: 現在視聴中のチャンネルのエモート
/// - `subscribedChannel`: 購読中の他チャンネルのエモート（ビッツエモートを含む）
/// - `hypeTrain`: ハイプトレインエモート（チャンネル横断の HYPE 枠）
/// - `global`: Twitch グローバルエモート（ownerId なし特殊エモートを含む）
struct EmotePickerSection: Identifiable, Equatable, Sendable {

    // MARK: - セクション種別

    /// セクションの種別
    enum Kind: Equatable, Sendable {
        /// 現在視聴中のチャンネル
        case currentChannel
        /// 購読中の他チャンネル（ビッツエモートを含む）
        case subscribedChannel(ownerId: String)
        /// ハイプトレインエモート（チャンネル横断の HYPE 枠）
        case hypeTrain
        /// Twitch グローバルエモート（リワード・プライム等の ownerId なしエモートを含む）
        case global
    }

    // MARK: - プロパティ

    /// セクションの一意識別子
    ///
    /// - `currentChannel`: "current"
    /// - `subscribedChannel(ownerId)`: "channel-{ownerId}"
    /// - `hypeTrain`: "hype"
    /// - `global`: "global"
    let id: String

    /// セクションの種別
    let kind: Kind

    /// セクションヘッダーに表示するタイトル
    let title: String

    /// セクションヘッダーのアイコン取得に使用する Twitch ユーザー ID
    ///
    /// `ProfileImageStore.profileImageUrl(for:)` に渡してチャンネルアイコンを取得する。
    /// グローバル・ハイプトレイン・その他セクションは `nil`。
    let iconUserId: String?

    /// このセクションに含まれるエモート一覧
    let emotes: [HelixEmote]
}
