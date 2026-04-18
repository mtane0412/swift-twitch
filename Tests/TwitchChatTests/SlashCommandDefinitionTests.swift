// SlashCommandDefinitionTests.swift
// SlashCommandDefinition の静的コマンドリスト・構造のテスト

import Testing
@testable import TwitchChat

@Suite("SlashCommandDefinitionTests")
struct SlashCommandDefinitionTests {

    // MARK: - allCommands

    @Test("allCommands が空でないこと")
    func testAllCommandsNotEmpty() {
        #expect(!SlashCommandDefinition.allCommands.isEmpty)
    }

    @Test("allCommands の各コマンドの name が一意であること")
    func testAllCommandNamesAreUnique() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("allCommands の各コマンドの name に先頭スラッシュが含まれないこと")
    func testCommandNamesDoNotContainLeadingSlash() {
        for command in SlashCommandDefinition.allCommands {
            #expect(!command.name.hasPrefix("/"), "コマンド '\(command.name)' に先頭スラッシュが含まれています")
        }
    }

    @Test("allCommands の各コマンドの description が空でないこと")
    func testAllCommandDescriptionsNotEmpty() {
        for command in SlashCommandDefinition.allCommands {
            #expect(!command.description.isEmpty, "コマンド '\(command.name)' の description が空です")
        }
    }

    // MARK: - Identifiable

    @Test("id は name と一致すること")
    func testIdEqualsName() {
        for command in SlashCommandDefinition.allCommands {
            #expect(command.id == command.name)
        }
    }

    // MARK: - 必須コマンドの存在確認

    @Test("ban コマンドが定義されていること")
    func testBanCommandExists() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        #expect(names.contains("ban"))
    }

    @Test("timeout コマンドが定義されていること")
    func testTimeoutCommandExists() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        #expect(names.contains("timeout"))
    }

    @Test("me コマンドが定義されていること")
    func testMeCommandExists() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        #expect(names.contains("me"))
    }

    @Test("clear コマンドが定義されていること")
    func testClearCommandExists() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        #expect(names.contains("clear"))
    }
}
