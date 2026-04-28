// ImageDiskStoreTests.swift
// ImageDiskStore の単体テスト
// 一時ディレクトリを用いた実ファイル I/O で SHA256 パス算出・書き込み・削除・LRU sweep・isExcludedFromBackup を検証する

import CryptoKit
import Foundation
import Testing
@testable import TwitchChat

/// ImageDiskStore のテストスイート
@Suite("ImageDiskStore テスト")
struct ImageDiskStoreTests {

    // MARK: - ヘルパー

    /// 一時ルートディレクトリを作成する（テスト終了後は呼び出し元が defer で削除する）
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageDiskStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - SHA256 パス算出

    @Test("エモートキーの SHA256 ファイルパスが正しく算出される")
    func エモートキーのSHA256パスが正しく算出される() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .emote, identifier: "12345:2.0:animated")

        // SHA256 hex を CryptoKit で手計算する（"emote:<identifier>" が入力）
        let input = "emote:12345:2.0:animated"
        let hashBytes = SHA256.hash(data: Data(input.utf8))
        let hex = hashBytes.compactMap { String(format: "%02x", $0) }.joined()

        // 期待するパス要素を組み立てる: <先頭2桁>/<次2桁>/<残り>.bin
        let expectedDir1 = String(hex.prefix(2))
        let expectedDir2 = String(hex.dropFirst(2).prefix(2))
        let expectedFile = "\(String(hex.dropFirst(4))).bin"

        // 検証: fileURL が SHA256 ハッシュから算出したパス階層と一致する（nonisolated のため await 不要）
        let fileURL = store.fileURL(for: key)
        #expect(fileURL.lastPathComponent == expectedFile, "ファイル名が SHA256 の残りバイトと一致しない")
        #expect(fileURL.deletingLastPathComponent().lastPathComponent == expectedDir2, "第2ディレクトリが SHA256 の3-4バイト目と一致しない")
        #expect(fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == expectedDir1, "第1ディレクトリが SHA256 の1-2バイト目と一致しない")
        #expect(fileURL.path.contains("/ImageCache/emotes/"), "バケット 'emotes' 配下でない")
    }

    @Test("バッジキーのファイルパスがバケット 'badges' 配下に生成される")
    func バッジキーのパスがbadgesバケット配下になる() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .badge, identifier: "broadcaster:1")

        // 検証: パスに "badges" が含まれる（nonisolated のため await 不要）
        let fileURL = store.fileURL(for: key)
        #expect(fileURL.path.contains("/ImageCache/badges/"))
    }

    @Test("プロフィールキーのファイルパスがバケット 'profiles' 配下に生成される")
    func プロフィールキーのパスがprofilesバケット配下になる() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .profile, identifier: "ユーザー001")

        // 検証: パスに "profiles" が含まれる（nonisolated のため await 不要）
        let fileURL = store.fileURL(for: key)
        #expect(fileURL.path.contains("/ImageCache/profiles/"))
    }

    // MARK: - ラウンドトリップ（書き込み・読み出し）

    @Test("エモート画像データを書き込んで読み出せる")
    func エモート画像データの書き込みと読み出しができる() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .emote, identifier: "25:2.0:static")
        let testData = Data("エモートテストデータ_Kappa".utf8)

        // 操作: 書き込み
        let writtenBytes = try await store.writeData(testData, key: key)

        // 検証: 返り値のバイト数が一致し、読み出しデータも一致する
        #expect(writtenBytes == testData.count)
        let loaded = await store.loadData(key: key)
        #expect(loaded == testData)
    }

    @Test("バッジ画像データを書き込んで読み出せる")
    func バッジ画像データの書き込みと読み出しができる() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .badge, identifier: "subscriber:6")
        let testData = Data("バッジテストデータ_6ヶ月サブスク".utf8)

        // 操作: 書き込み
        _ = try await store.writeData(testData, key: key)

        // 検証: 読み出しデータが一致する
        let loaded = await store.loadData(key: key)
        #expect(loaded == testData)
    }

    @Test("プロフィール画像データを書き込んで読み出せる")
    func プロフィール画像データの書き込みと読み出しができる() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .profile, identifier: "配信者001")
        let testData = Data("プロフィール画像テストデータ".utf8)

        // 操作: 書き込み
        _ = try await store.writeData(testData, key: key)

        // 検証: 読み出しデータが一致する
        let loaded = await store.loadData(key: key)
        #expect(loaded == testData)
    }

    @Test("同一キーへの上書きで最新データが読み出される")
    func 同一キーへの上書きで最新データが読み出される() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .emote, identifier: "1902:2.0:static")
        let firstData = Data("最初のデータ".utf8)
        let secondData = Data("上書き後のデータ_LUL".utf8)

        // 操作: 2 回書き込む
        _ = try await store.writeData(firstData, key: key)
        let writtenBytes = try await store.writeData(secondData, key: key)

        // 検証: 最新データが読み出せる
        #expect(writtenBytes == secondData.count)
        let loaded = await store.loadData(key: key)
        #expect(loaded == secondData)
    }

    @Test("存在しないキーの loadData が nil を返す")
    func 存在しないキーのloadDataがnilを返す() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .emote, identifier: "存在しないエモートID:2.0:static")

        // 検証: ファイルが無いので nil が返る
        let loaded = await store.loadData(key: key)
        #expect(loaded == nil)
    }

    // MARK: - ファイル削除

    @Test("deleteFile 後に loadData が nil を返す")
    func deleteFile後にloadDataがnilを返す() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .badge, identifier: "broadcaster:1")
        let testData = Data("バッジ削除テスト".utf8)

        // 前提: 書き込んで読み出せる状態にする
        _ = try await store.writeData(testData, key: key)
        #expect(await store.loadData(key: key) != nil)

        // 操作: 削除
        await store.deleteFile(key: key)

        // 検証: 削除後は nil
        let loaded = await store.loadData(key: key)
        #expect(loaded == nil)
    }

    // MARK: - isExcludedFromBackup

    @Test("ImageCache ルートディレクトリに isExcludedFromBackup が設定される")
    func ImageCacheルートにisExcludedFromBackupが設定される() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // 操作: ImageDiskStore を生成（init で isExcludedFromBackup を設定する）
        let store = try ImageDiskStore(rootDirectory: root)
        _ = store

        // 検証: ImageCache ルートが backup 除外になっている
        let cacheRoot = root.appendingPathComponent("ImageCache")
        let values = try cacheRoot.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("各バケットディレクトリに isExcludedFromBackup が設定される")
    func 各バケットディレクトリにisExcludedFromBackupが設定される() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        _ = store

        // 検証: emotes / badges / profiles の各バケットが backup 除外になっている
        for bucket in ["emotes", "badges", "profiles"] {
            let bucketDir = root.appendingPathComponent("ImageCache/\(bucket)")
            let values = try bucketDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true, "バケット '\(bucket)' が backup 除外でない")
        }
    }

    // MARK: - enumerateAllFiles

    @Test("enumerateAllFiles が書き込んだ全ファイルを列挙する")
    func enumerateAllFilesが全ファイルを列挙する() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let keys: [ImageCacheKey] = [
            ImageCacheKey(kind: .emote, identifier: "25:2.0:animated"),
            ImageCacheKey(kind: .badge, identifier: "broadcaster:1"),
            ImageCacheKey(kind: .profile, identifier: "視聴者ユーザー001")
        ]

        // 操作: 3 種の画像を書き込む
        for key in keys {
            _ = try await store.writeData(Data("テストデータ".utf8), key: key)
        }

        // 検証: 3 ファイルが列挙される（URL 表現差異を避けてパス文字列で比較）
        let allFiles = await store.enumerateAllFiles()
        #expect(allFiles.count == 3)
        let allPaths = allFiles.map(\.path)
        for key in keys {
            let expected = store.fileURL(for: key).path
            #expect(allPaths.contains(expected), "ファイルが列挙されていない: \(expected)")
        }
    }

    @Test("deleteFile 後は enumerateAllFiles に含まれない")
    func deleteFile後はenumerateAllFilesに含まれない() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ImageDiskStore(rootDirectory: root)
        let key = ImageCacheKey(kind: .emote, identifier: "1902:2.0:static")
        _ = try await store.writeData(Data("削除テスト".utf8), key: key)

        // 操作: 削除
        await store.deleteFile(key: key)

        // 検証: 削除後はファイルが列挙されない（パス文字列で比較）
        let allFiles = await store.enumerateAllFiles()
        let expectedPath = store.fileURL(for: key).path
        #expect(!allFiles.map(\.path).contains(expectedPath))
    }

    // MARK: - capacity

    @Test("capacity(for:) がバケット別の上限バイト数を返す")
    func capacityがバケット別の上限バイト数を返す() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let capacity = ImageDiskStore.Capacity(emotesMB: 200, badgesMB: 50, profilesMB: 50)
        let store = try ImageDiskStore(rootDirectory: root, capacity: capacity)

        // 検証: MB → バイト換算が正しい（capacity は nonisolated のため await 不要）
        #expect(store.capacity(for: .emotes) == 200 * 1024 * 1024)
        #expect(store.capacity(for: .badges) == 50 * 1024 * 1024)
        #expect(store.capacity(for: .profiles) == 50 * 1024 * 1024)
    }
}
