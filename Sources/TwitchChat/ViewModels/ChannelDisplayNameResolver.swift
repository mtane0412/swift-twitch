// ChannelDisplayNameResolver.swift
// チャンネルログイン名から表示名を解決するロジック
// FollowedStreamStore の userName を優先し、取得できない場合は channelLogin をそのまま返す

import Foundation

/// チャンネルの表示名を解決するリゾルバ
///
/// フォロー中の配信者には `FollowedStream.userName`（例: "山田太郎"）を返し、
/// フォロー外または未ライブのチャンネルには `channelLogin` をそのまま返す。
/// SwiftUI 非依存の純粋なロジック層として実装する。
@MainActor
struct ChannelDisplayNameResolver {

    private let store: FollowedStreamStore

    /// `ChannelDisplayNameResolver` を初期化する
    ///
    /// - Parameter store: フォロー中ストリーム情報のストア
    init(store: FollowedStreamStore) {
        self.store = store
    }

    /// チャンネルログイン名に対応する表示名を返す
    ///
    /// 大文字小文字の正規化は `FollowedStreamStore.stream(forUserLogin:)` が担う。
    /// - Parameter channelLogin: チャンネルのログイン名
    /// - Returns: フォロー中かつライブ中なら `FollowedStream.userName`、それ以外は `channelLogin` をそのまま返す
    func displayName(for channelLogin: String) -> String {
        store.stream(forUserLogin: channelLogin)?.userName ?? channelLogin
    }
}
