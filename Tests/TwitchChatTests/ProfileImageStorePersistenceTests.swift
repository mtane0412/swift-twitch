// ProfileImageStorePersistenceTests.swift
// ProfileImageStore の永続化配線テスト（キャッシュ先読み / write-back / clear 後の復元）
// および ProfileImageCache の L2 キャッシュ統合テスト

import AppKit
import Foundation
import Testing
@testable import TwitchChat

/// ProfileImageStore の永続化配線テストスイート
@Suite("ProfileImageStorePersistenceTests")
@MainActor
struct ProfileImageStorePersistenceTests {

    // MARK: - ヘルパー

    /// テスト用ユーザープロフィールスナップショットを生成する
    private func makeYamadaProfile() -> UserProfileSnapshot {
        UserProfileSnapshot(
            userId: "ユーザーID001",
            login: "yamada_taro",
            displayName: "山田太郎",
            profileImageUrl: "https://cdn.example.com/profile/yamada.png"
        )
    }

    /// 永続化サービスに期待数のプロフィールが保存されるまでポーリング待機する
    private func waitForSavedProfiles(
        in persistence: InMemoryPersistenceService,
        userIds: [String],
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> [UserProfileSnapshot] {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let saved = await persistence.loadUserProfiles(userIds: userIds)
            if saved.count == userIds.count { return saved }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await persistence.loadUserProfiles(userIds: userIds)
    }

    // MARK: - キャッシュ先読み（API 呼び出し抑制）

    @Test("永続化済みプロフィールはfetchUsers呼び出し時にAPIを呼ばずに解決される")
    func 永続化済みプロフィールはfetchUsers呼び出し時にAPIを呼ばずに解決される() async throws {
        // 前提: 山田太郎のプロフィールを InMemoryPersistenceService に事前保存する
        let persistence = InMemoryPersistenceService()
        let yamada = makeYamadaProfile()
        try await persistence.saveUserProfiles([yamada])

        // 前提: API クライアントは呼ばれてはならない（永続化から解決できるため）
        let apiClient = MockProfileImageAPIClient()

        // 操作: persistenceService 付きで ProfileImageStore を初期化し fetchUsers を呼ぶ
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API は呼ばれなかった
        let callCount = await apiClient.callCount
        #expect(callCount == 0)

        // 検証: 永続化から復元されたプロフィールで表示名・画像URLを解決できる
        let displayName = store.displayName(for: "ユーザーID001")
        let imageURL = store.profileImageUrl(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
        #expect(imageURL?.absoluteString == "https://cdn.example.com/profile/yamada.png")
    }

    @Test("永続化にないプロフィールはAPIを呼んで取得する")
    func 永続化にないプロフィールはAPIを呼んで取得する() async {
        // 前提: 永続化サービスは空、API クライアントは山田太郎を返す
        let persistence = InMemoryPersistenceService()
        let apiClient = MockProfileImageAPIClient()
        await apiClient.setUsers([
            HelixUserData(
                id: "ユーザーID001",
                login: "yamada_taro",
                displayName: "山田太郎",
                profileImageUrl: URL(string: "https://cdn.example.com/profile/yamada.png")
            )
        ])

        // 操作: fetchUsers を呼ぶ（永続化にないので API を呼ぶはず）
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API が1回呼ばれた
        let callCount = await apiClient.callCount
        #expect(callCount == 1)

        // 検証: displayName が解決できる
        let displayName = store.displayName(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
    }

    // MARK: - write-back

    @Test("APIフェッチ後にプロフィールが永続化サービスに保存される")
    func APIフェッチ後にプロフィールが永続化サービスに保存される() async {
        // 前提: 空の永続化サービスと、山田太郎・佐藤花子を返す API クライアント
        let persistence = InMemoryPersistenceService()
        let apiClient = MockProfileImageAPIClient()
        await apiClient.setUsers([
            HelixUserData(
                id: "ユーザーID001",
                login: "yamada_taro",
                displayName: "山田太郎",
                profileImageUrl: URL(string: "https://cdn.example.com/profile/yamada.png")
            ),
            HelixUserData(
                id: "ユーザーID002",
                login: "sato_hanako",
                displayName: "佐藤花子",
                profileImageUrl: nil
            )
        ])

        // 操作: fetchUsers で2ユーザーを取得する
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001", "ユーザーID002"])

        // 検証: 永続化サービスに両ユーザーのプロフィールが保存されている（write-back の完了を bounded poll で待機）
        let saved = await waitForSavedProfiles(
            in: persistence,
            userIds: ["ユーザーID001", "ユーザーID002"]
        )
        #expect(saved.count == 2)
        #expect(saved.map(\.displayName).contains("山田太郎"))
        #expect(saved.map(\.displayName).contains("佐藤花子"))
    }

    // MARK: - clear 後の復元

    @Test("clear後にfetchUsersを呼ぶと永続化キャッシュから復元されAPIを呼ばない")
    func clear後にfetchUsersを呼ぶと永続化キャッシュから復元されAPIを呼ばない() async throws {
        // 前提: 永続化に山田太郎を保存済み
        let persistence = InMemoryPersistenceService()
        let yamada = makeYamadaProfile()
        try await persistence.saveUserProfiles([yamada])

        let apiClient = MockProfileImageAPIClient()
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: まず fetchUsers を呼んでキャッシュに入れる
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 操作: clear() を呼ぶ（in-memory キャッシュを消去、永続化データは保持）
        store.clear()

        // 操作: 再度 fetchUsers を呼ぶ
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API は呼ばれなかった（永続化から復元）
        let callCount = await apiClient.callCount
        #expect(callCount == 0)

        // 検証: clear 後でも displayName が解決できる
        let displayName = store.displayName(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
    }
}

// MARK: - ProfileImageCache L2 統合テスト

/// ProfileImageCache の L2 キャッシュ（ImageDiskStore / PersistenceService）統合テストスイート
///
/// シングルトン ProfileImageCache.shared の状態を共有するため、テストを順次実行する。
@Suite("ProfileImageCache L2 統合テスト", .serialized)
struct ProfileImageCacheL2Tests {

    @Test("L2 に有効な画像データがある場合は HTTP なしでプロフィール画像を返す")
    func L2ヒット時はHTTPなしでプロフィール画像を返す() async {
        // 前提: ユーザーID "ユーザーID_L2テスト_山田" の L2 データをモックに投入する
        let userId = "ユーザーID_L2テスト_山田_\(UUID())"
        let mock = MockPersistenceService()
        guard let pngData = makeMiniPNGData() else {
            Issue.record("テスト用 PNG データ生成失敗")
            return
        }
        let l2Key = ImageCacheKey(kind: .profile, identifier: userId)
        await mock.seedImageData(pngData, key: l2Key)

        ProfileImageCache.shared.attachPersistence(mock)
        defer { ProfileImageCache.shared.attachPersistenceForTesting(nil) }

        // 前提: 存在しない URL（L2 ヒット時は HTTP は呼ばれないので何でも良い）
        let dummyURL = URL(string: "https://example.com/dummy.png")!

        // 実行: image(for:imageUrl:) を呼ぶ（L2 ヒットで返るはず）
        let result = await ProfileImageCache.shared.image(for: userId, imageUrl: dummyURL)

        // 検証: 画像が返った（L2 から復元）
        #expect(result != nil)
        // 検証: loadImageData が1回呼ばれた
        let loadCount = await mock.loadImageDataCallCount
        #expect(loadCount == 1)
        // 検証: L2 保存は呼ばれなかった（HTTP は不発火）
        let saveCount = await mock.saveImageDataCallCount
        #expect(saveCount == 0)
    }

    // MARK: - ヘルパー

    /// CoreGraphics で 2×2 ピクセルの PNG データを生成する（L2 シード用）
    private func makeMiniPNGData() -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
