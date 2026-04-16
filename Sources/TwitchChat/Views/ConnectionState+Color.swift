// ConnectionState+Color.swift
// ConnectionState に対応する表示色を提供する SwiftUI 拡張
// タブバーやサイドバーアイコンの接続状態ボーダー色の一元管理

import SwiftUI

extension ConnectionState {
    /// 接続状態を表す色
    ///
    /// - connected: 緑（接続済み）
    /// - connecting: 黄（接続中）
    /// - error: 赤（エラー）
    /// - disconnected: グレー（未接続）
    var connectionColor: Color {
        switch self {
        case .connected: .green
        case .connecting: .yellow
        case .error: .red
        case .disconnected: .gray
        }
    }
}
