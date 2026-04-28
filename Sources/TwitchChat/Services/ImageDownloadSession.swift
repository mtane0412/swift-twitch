// ImageDownloadSession.swift
// 画像ダウンロード専用 URLSession（L2 ディスクキャッシュと二重管理にならないよう URLCache を無効化）
//
// URLSession.shared はデフォルトで URLCache（L2 相当）を使用するため、
// アプリ独自の ImageDiskStore（L2）と競合する。
// この shared インスタンスは URLCache を 0 に設定し、L2 管理を ImageDiskStore に一元化する。

import Foundation

/// 画像ダウンロード専用の URLSession
///
/// `URLCache` を無効化することで OS の URL キャッシュと ImageDiskStore の二重管理を回避する。
/// 3 つの ImageCache（エモート・バッジ・プロフィール）が共用する。
enum ImageDownloadSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
