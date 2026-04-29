// AppStorageKeys.swift
// @AppStorage で使用するキー文字列の共有定数
// 複数 View に分散した文字列リテラルを一元管理し、typo や同期漏れを防ぐ

/// `@AppStorage` キーの名前空間
enum AppStorageKeys {
    /// ライブ配信プレイヤー機能の有効・無効
    static let livePlayerEnabled = "livePlayerEnabled"
}
