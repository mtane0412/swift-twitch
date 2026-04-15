// ChannelManagerTests.swift
// ChannelManager の単体テスト
// MockTwitchIRCClient と MockHelixAPIClient を使って複数チャンネル管理の振る舞いを検証する

import Testing
import Foundation
@testable import TwitchChat

@Suite("ChannelManager テスト")
@MainActor
struct ChannelManagerTests {

    // MARK: - 初期状態

    @Test("初期状態はチャンネルなし、選択チャンネルなし")
    func testInitialState() {
        let manager = ChannelManager(authState: AuthState())

        #expect(manager.channels.isEmpty)
        #expect(manager.channelOrder.isEmpty)
        #expect(manager.selectedChannel == nil)
        #expect(manager.selectedViewModel == nil)
    }

    // MARK: - チャンネル参加

    @Test("joinChannel で新しいチャンネルに接続できる")
    func testJoinNewChannel() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        // チャンネル名は小文字なので正規化しても変わらない
        await manager.joinChannel("haishinsha1")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.channels.count == 1)
        #expect(manager.channelOrder == ["haishinsha1"])
        #expect(manager.selectedChannel == "haishinsha1")
        #expect(manager.selectedViewModel != nil)
    }

    @Test("複数チャンネルに同時接続できる")
    func testJoinMultipleChannels() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // 両チャンネルが接続中であること
        #expect(manager.channels.count == 2)
        #expect(manager.channelOrder.contains("haishinsha1"))
        #expect(manager.channelOrder.contains("haishinsha2"))
        // 最後に選択したチャンネルが表示されること
        #expect(manager.selectedChannel == "haishinsha2")
    }

    @Test("joinChannel は既存チャンネルへの再参加時に選択のみ切り替える")
    func testJoinExistingChannelSwitchesSelection() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // haishinsha1 を再度 join → 接続数は増えず選択が切り替わること
        await manager.joinChannel("haishinsha1")
        #expect(manager.channels.count == 2)
        #expect(manager.selectedChannel == "haishinsha1")
    }

    @Test("チャンネル名は小文字に正規化される")
    func testChannelNameNormalized() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        // 大文字混じりの名前を渡しても小文字で管理される
        await manager.joinChannel("NintendoJP")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.channels["nintendojp"] != nil)
        #expect(manager.selectedChannel == "nintendojp")
    }

    // MARK: - チャンネル退出

    @Test("leaveChannel で接続を切断してリストから削除される")
    func testLeaveChannel() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.leaveChannel("haishinsha1")

        #expect(manager.channels.count == 1)
        #expect(manager.channels["haishinsha1"] == nil)
        #expect(manager.channelOrder == ["haishinsha2"])
    }

    @Test("選択中のチャンネルを退出すると選択が解除される")
    func testLeaveSelectedChannelClearsSelection() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.leaveChannel("haishinsha1")

        #expect(manager.selectedChannel == nil)
        #expect(manager.selectedViewModel == nil)
    }

    @Test("disconnectAll で全チャンネルが切断される")
    func testDisconnectAll() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        await manager.joinChannel("haishinsha3")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.disconnectAll()

        #expect(manager.channels.isEmpty)
        #expect(manager.channelOrder.isEmpty)
        #expect(manager.selectedChannel == nil)
    }
}
