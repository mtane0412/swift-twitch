// swift-tools-version: 6.0
// Package.swift
// TwitchChat macOS アプリのパッケージ定義
// Twitch IRC チャットを表示する macOS 15+ ネイティブアプリ

import PackageDescription

let package = Package(
    name: "TwitchChat",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Swift Testing フレームワーク（CommandLineTools 環境でのテスト実行に使用）
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "TwitchChat",
            path: "Sources/TwitchChat"
        ),
        .testTarget(
            name: "TwitchChatTests",
            dependencies: [
                "TwitchChat",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/TwitchChatTests",
            linkerSettings: [
                // CommandLineTools 環境で lib_TestingInterop を見つけるためのパス設定
                .unsafeFlags([
                    "-L",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
