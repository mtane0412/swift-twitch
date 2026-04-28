// PersistenceActor+ImageCache.swift
// PersistenceActor の画像バイナリ I/O・LRU sweep・debounce flush を担う extension
// PersistenceActor.swift のファイル長制限（800行）維持のため分離

import Foundation
import SwiftData

// MARK: - 画像バイナリ（ImageDiskStore 統合）

extension PersistenceActor {

    /// DI: ImageDiskStore を注入する（@ModelActor 生成 init の後付け設定）
    func attachDiskStore(_ store: ImageDiskStore) {
        imageDiskStore = store
    }

    /// キャッシュキーで画像バイナリを取得する
    ///
    /// - SwiftData レコードあり・ファイルあり → データ返却（lastAccessedAt を debounce 更新）
    /// - SwiftData レコードあり・ファイルなし → 整合性違反: レコード削除して nil 返却
    /// - SwiftData レコードなし → nil 返却
    func loadImageData(key: ImageCacheKey) async -> Data? {
        let cacheKeyStr = imageCacheKeyRaw(key)
        let descriptor = FetchDescriptor<PersistedImageAsset>(
            predicate: #Predicate { $0.cacheKey == cacheKeyStr }
        )
        guard let asset = (try? modelContext.fetch(descriptor))?.first else { return nil }

        guard let store = imageDiskStore else {
            // diskStore 未設定（InMemory フォールバック状態）は nil を返す
            return nil
        }

        guard let data = await store.loadData(key: key) else {
            // ファイル無しレコード: 整合性違反を修正して nil 返却
            modelContext.delete(asset)
            try? modelContext.save()
            return nil
        }

        // lastAccessedAt の更新は 60 秒 debounce でまとめて flush する
        pendingTouches.insert(cacheKeyStr)
        scheduleTouchFlushIfNeeded()
        return data
    }

    /// 画像バイナリを保存する（upsert）
    ///
    /// 書き込み順: BLOB ファイル書き込み（fsync 相当） → SwiftData コミット
    /// ファイル書き込み失敗時は SwiftData に手を付けずに throw する。
    /// SwiftData save 失敗時は best-effort でファイルを削除して巻き戻す。
    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) async throws {
        guard let store = imageDiskStore else { return }

        // Step 1: ファイルを先に書き込む（BLOB fsync）
        let bytes = try await store.writeData(data, key: key)

        // Step 2: SwiftData メタデータを upsert する
        let cacheKeyStr = imageCacheKeyRaw(key)
        let descriptor = FetchDescriptor<PersistedImageAsset>(
            predicate: #Predicate { $0.cacheKey == cacheKeyStr }
        )
        let now = Date()
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.mime = mime
            existing.byteSize = bytes
            existing.lastAccessedAt = now
        } else {
            modelContext.insert(PersistedImageAsset(
                cacheKey: cacheKeyStr,
                kind: key.kind.rawValue,
                identifier: key.identifier,
                mime: mime,
                byteSize: bytes,
                lastAccessedAt: now,
                createdAt: now
            ))
        }

        // Step 3: SwiftData コミット（失敗時は best-effort でファイル削除）
        do {
            try modelContext.save()
        } catch {
            await store.deleteFile(key: key)
            throw error
        }

        // Step 4: バケット容量超過チェック
        let bucket = ImageDiskStore.Bucket(kind: key.kind)
        await runSweepIfNeeded(for: bucket)
    }

    /// 起動時 reconcile + 全バケット sweep（起動 5 秒後 / didResignActive から呼ぶ）
    func runReconcileAndSweep() async {
        guard let store = imageDiskStore else { return }
        await reconcile(store: store)
        for bucket in ImageDiskStore.Bucket.allCases {
            await runSweepIfNeeded(for: bucket)
        }
    }
}

// MARK: - 画像 Private Helpers

private extension PersistenceActor {

    /// ImageCacheKey をキャッシュキー文字列に変換する
    func imageCacheKeyRaw(_ key: ImageCacheKey) -> String {
        "\(key.kind.rawValue):\(key.identifier)"
    }

    // MARK: - LRU sweep

    /// バケットの合計 byteSize が上限を超えていれば LRU 順に削除する
    ///
    /// 削除順: SwiftData コミット → ファイル削除（整合性保証）
    func runSweepIfNeeded(for bucket: ImageDiskStore.Bucket) async {
        guard let store = imageDiskStore else { return }
        let kindStr = kindRaw(for: bucket)
        let limit = store.capacity(for: bucket)

        // バケット合計サイズを集計
        let allDescriptor = FetchDescriptor<PersistedImageAsset>(
            predicate: #Predicate { $0.kind == kindStr },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
        )
        guard let assets = try? modelContext.fetch(allDescriptor) else { return }
        let total = assets.reduce(0) { $0 + $1.byteSize }
        guard total > limit else { return }

        // 容量超過分を lastAccessedAt 昇順（古い順）で削除
        var freed = 0
        let target = total - limit
        var toDelete: [(key: ImageCacheKey, asset: PersistedImageAsset)] = []
        for asset in assets {
            guard freed < target else { break }
            let key = ImageCacheKey(kind: kind(from: asset.kind), identifier: asset.identifier)
            toDelete.append((key: key, asset: asset))
            freed += asset.byteSize
        }

        // 削除順: SwiftData コミット → ファイル削除
        for item in toDelete { modelContext.delete(item.asset) }
        try? modelContext.save()
        for item in toDelete { await store.deleteFile(key: item.key) }
    }

    /// 物理ファイルと SwiftData レコードの整合性を修復する
    ///
    /// - レコードあり・ファイルなし → レコードを削除
    /// - ファイルあり・レコードなし → 孤児ファイルを削除
    func reconcile(store: ImageDiskStore) async {
        let allPhysical = await store.enumerateAllFiles()
        let physicalPaths = Set(allPhysical.map(\.path))

        let allDescriptor = FetchDescriptor<PersistedImageAsset>()
        guard let assets = try? modelContext.fetch(allDescriptor) else { return }

        var validPaths: Set<String> = []
        for asset in assets {
            let key = ImageCacheKey(kind: kind(from: asset.kind), identifier: asset.identifier)
            let filePath = store.fileURL(for: key).path
            if physicalPaths.contains(filePath) {
                validPaths.insert(filePath)
            } else {
                // ファイル無しレコード → 削除
                modelContext.delete(asset)
            }
        }
        try? modelContext.save()

        // 孤児ファイル（レコード無しファイル）を削除
        for path in physicalPaths where !validPaths.contains(path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - lastAccessedAt Debounce

    /// pendingTouches の flush Task をスケジュールする（すでに起動済みなら何もしない）
    func scheduleTouchFlushIfNeeded() {
        guard !debounceFlushScheduled else { return }
        debounceFlushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            await self?.flushPendingTouches()
        }
    }

    /// pendingTouches に溜まった lastAccessedAt 更新を一括コミットする
    func flushPendingTouches() async {
        guard !pendingTouches.isEmpty else {
            debounceFlushScheduled = false
            return
        }
        let keys = pendingTouches
        pendingTouches.removeAll()
        debounceFlushScheduled = false

        let now = Date()
        for cacheKeyStr in keys {
            let descriptor = FetchDescriptor<PersistedImageAsset>(
                predicate: #Predicate { $0.cacheKey == cacheKeyStr }
            )
            if let asset = (try? modelContext.fetch(descriptor))?.first {
                asset.lastAccessedAt = now
            }
        }
        try? modelContext.save()
    }

    // MARK: - kind 変換ヘルパー

    func kindRaw(for bucket: ImageDiskStore.Bucket) -> String {
        switch bucket {
        case .emotes: return "emote"
        case .badges: return "badge"
        case .profiles: return "profile"
        }
    }

    func kind(from kindRaw: String) -> ImageCacheKey.Kind {
        switch kindRaw {
        case "badge": return .badge
        case "profile": return .profile
        default: return .emote
        }
    }
}
