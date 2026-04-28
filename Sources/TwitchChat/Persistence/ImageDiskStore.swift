// ImageDiskStore.swift
// Application Support 配下の画像バイナリディスクキャッシュ（L2）
//
// SHA256 ハッシュに基づいたディレクトリ構造でバイナリを管理する。
// SwiftData の PersistedImageAsset はメタデータ（byteSize・lastAccessedAt）を保持し、
// 実バイナリはこの actor が担当する。
//
// パス構造: <rootDirectory>/ImageCache/<bucket>/<sha[0..2]>/<sha[2..4]>/<sha[4..]>.bin

import CryptoKit
import Foundation

/// 画像バイナリのディスクキャッシュを管理する actor
///
/// 責務: ファイル I/O・SHA256 パス算出・isExcludedFromBackupKey 設定・容量上限の定義
/// 容量集計・LRU eviction・起動時 reconcile は PersistenceActor 側で行う。
actor ImageDiskStore {

    // MARK: - バケット

    /// 画像の種別ごとに対応するディレクトリバケット
    enum Bucket: String, CaseIterable, Sendable {
        case emotes
        case badges
        case profiles

        init(kind: ImageCacheKey.Kind) {
            switch kind {
            case .emote: self = .emotes
            case .badge: self = .badges
            case .profile: self = .profiles
            }
        }
    }

    // MARK: - 容量上限

    /// バケットごとの容量上限設定
    struct Capacity: Sendable {
        let emotesMB: Int
        let badgesMB: Int
        let profilesMB: Int

        static let `default` = Capacity(emotesMB: 200, badgesMB: 50, profilesMB: 50)

        /// 指定バケットの上限をバイト数で返す
        func bytes(for bucket: Bucket) -> Int {
            switch bucket {
            case .emotes: return emotesMB * 1024 * 1024
            case .badges: return badgesMB * 1024 * 1024
            case .profiles: return profilesMB * 1024 * 1024
            }
        }
    }

    // MARK: - プロパティ

    private let rootDirectory: URL
    private let storedCapacity: Capacity

    // MARK: - 初期化

    /// ルートディレクトリを指定して ImageDiskStore を生成する
    ///
    /// - Parameters:
    ///   - rootDirectory: キャッシュルート（Application Support 配下または一時ディレクトリ）
    ///   - capacity: バケット別容量上限（デフォルト: emotes=200MB / badges=50MB / profiles=50MB）
    /// - Throws: ImageCache ルートまたはバケットディレクトリの作成・属性設定に失敗した場合
    init(rootDirectory: URL, capacity: Capacity = .default) throws {
        // ディレクトリを先に作成してから realpath() でシムリンクを完全解決する。
        // URL.resolvingSymlinksInPath() は macOS の /var → /private/var を解決しない。
        // enumerator が返す /private/var パスと一致させるため realpath() syscall を使う。
        self.storedCapacity = capacity
        try Self.setupDirectories(rootDirectory: rootDirectory)
        let resolvedPath = Self.realPath(rootDirectory.path)
        self.rootDirectory = URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    // MARK: - パブリック API

    /// 指定キーの画像バイナリを読み出す
    ///
    /// ファイルが存在しない場合は nil を返す（エラーは握りつぶす）。
    /// lastAccessedAt の更新は呼び出し元（PersistenceActor）で debounce する。
    func loadData(key: ImageCacheKey) -> Data? {
        let url = filePath(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 指定キーの画像バイナリをアトミック書き込みする
    ///
    /// - Returns: 実際に書き込んだバイト数
    /// - Throws: ディレクトリ作成または書き込みに失敗した場合
    func writeData(_ data: Data, key: ImageCacheKey) throws -> Int {
        let url = filePath(for: key)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // .atomic は write→rename でアトミック性を保証する（OS が fsync 相当を行う）
        try data.write(to: url, options: .atomic)
        return data.count
    }

    /// 指定キーのファイルを削除する（ファイルが存在しない場合は何もしない）
    func deleteFile(key: ImageCacheKey) {
        try? FileManager.default.removeItem(at: filePath(for: key))
    }

    /// 指定キーのファイル URL を返す（ファイルの存在は保証しない）
    ///
    /// nonisolated のため await 不要で呼び出せる（純粋な SHA256 計算のみ）。
    nonisolated func fileURL(for key: ImageCacheKey) -> URL {
        filePath(for: key)
    }

    /// ImageCache 配下の全 .bin ファイルを列挙する（孤児ファイル検出用）
    func enumerateAllFiles() -> [URL] {
        let cacheRoot = rootDirectory.appendingPathComponent("ImageCache")
        guard let enumerator = FileManager.default.enumerator(
            at: cacheRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "bin" {
            result.append(url)
        }
        return result
    }

    /// 指定バケットの容量上限をバイト数で返す
    ///
    /// nonisolated のため await 不要で呼び出せる（storedCapacity は let 定数）。
    nonisolated func capacity(for bucket: Bucket) -> Int {
        storedCapacity.bytes(for: bucket)
    }

    // MARK: - プライベートメソッド

    /// SHA256 ハッシュに基づいてファイルパスを算出する
    ///
    /// 入力: "<kindRaw>:<identifier>" （PersistenceActor.imageCacheKeyRaw と同規則）
    /// パス: <rootDirectory>/ImageCache/<bucket>/<sha[0..2]>/<sha[2..4]>/<sha[4..]>.bin
    nonisolated private func filePath(for key: ImageCacheKey) -> URL {
        let bucket = Bucket(kind: key.kind)
        let input = "\(key.kind.rawValue):\(key.identifier)"
        let hashBytes = SHA256.hash(data: Data(input.utf8))
        let hex = hashBytes.compactMap { String(format: "%02x", $0) }.joined()

        return rootDirectory
            .appendingPathComponent("ImageCache")
            .appendingPathComponent(bucket.rawValue)
            .appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2).prefix(2)))
            .appendingPathComponent("\(String(hex.dropFirst(4))).bin")
    }

    // MARK: - 初期化ヘルパー（非 actor コンテキストで呼ぶため static）

    /// POSIX realpath() でシムリンクを完全解決し、正規絶対パスを返す
    ///
    /// パスが存在しない場合や解決失敗時は元のパスを返す。
    private static func realPath(_ path: String) -> String {
        guard let resolved = Darwin.realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// ImageCache ルートおよびバケットディレクトリを作成し、isExcludedFromBackup を設定する
    private static func setupDirectories(rootDirectory: URL) throws {
        let cacheRoot = rootDirectory.appendingPathComponent("ImageCache")

        // バケットディレクトリを作成
        for bucket in Bucket.allCases {
            let bucketDir = cacheRoot.appendingPathComponent(bucket.rawValue)
            try FileManager.default.createDirectory(at: bucketDir, withIntermediateDirectories: true)
        }

        // ImageCache ルートを backup 除外に設定
        try setExcludedFromBackup(url: cacheRoot)

        // 各バケットも backup 除外に設定
        for bucket in Bucket.allCases {
            let bucketDir = cacheRoot.appendingPathComponent(bucket.rawValue)
            try setExcludedFromBackup(url: bucketDir)
        }
    }

    private static func setExcludedFromBackup(url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}
