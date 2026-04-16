// ProfileImageView.swift
// Twitch ユーザープロフィール画像の円形アイコン表示ビュー
// ProfileImageCache 経由で非同期に画像を取得し、円形クリッピングで表示する

import AppKit
import SwiftUI

/// Twitch ユーザーのプロフィール画像を円形で表示するビュー
///
/// - 画像取得中・取得失敗時はグレー円形 + person アイコンのプレースホルダーを表示する
/// - `ProfileImageCache.shared` でキャッシュを共有し、同一ユーザーの重複ダウンロードを防ぐ
struct ProfileImageView: View {

    /// Twitch ユーザーID（キャッシュキーとして使用）
    let userId: String
    /// プロフィール画像 URL
    let imageUrl: URL?
    /// 表示サイズ（ポイント）
    var size: CGFloat = ProfileImageCache.displaySize

    /// 取得済み画像（nil の間はプレースホルダーを表示）
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // プレースホルダー: グレー円 + person アイコン
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // userId または imageUrl のどちらが変わっても再取得する
        // セパレータ（":"）を使用して userId + imageUrl の文字列衝突を防ぐ
        .task(id: userId + ":" + (imageUrl?.absoluteString ?? "")) {
            await loadImage()
        }
    }

    // MARK: - プライベートメソッド

    /// プロフィール画像を非同期で読み込む
    ///
    /// - userId/imageUrl 変化時はまず nil でプレースホルダーを表示し、ロード完了後に更新する
    /// - タスクがキャンセルされた場合やプロパティが変わった場合は代入しない
    private func loadImage() async {
        // 新しい画像を取得し始める前にプレースホルダーを表示する
        image = nil
        guard let imageUrl else { return }
        // ローカル変数にキャプチャして、await後に変化していないか確認する
        let capturedUserId = userId
        let capturedImageUrl = imageUrl
        let loaded = await ProfileImageCache.shared.image(for: capturedUserId, imageUrl: capturedImageUrl)
        // タスクキャンセル済み、またはプロパティが変更されている場合は代入しない
        guard !Task.isCancelled,
              userId == capturedUserId,
              imageUrl == capturedImageUrl else { return }
        image = loaded
    }
}
