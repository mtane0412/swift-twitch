// swift-tools-version: 6.0
// Package.swift
// TwitchChat macOS アプリのパッケージ定義
// Twitch IRC チャットを表示する macOS 15+ ネイティブアプリ

import PackageDescription
import Foundation

// GitHub Actions は CI=true を自動設定する。
// CI 環境（Xcode 16 / Swift 6.0.3）では CommandLineTools 専用のリンカフラグが不要。
// ローカル環境（CommandLineTools のみ）では isCI = false となり既存の動作を維持する。
// 外部 swift-testing パッケージは CI でも引き続き使用する（Xcode 16 と互換）。
let isCI = ProcessInfo.processInfo.environment["CI"] != nil

let package = Package(
    name: "TwitchChat",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: isCI ? [] : [
        // Swift Testing フレームワーク（CommandLineTools 環境でのテスト実行に使用）
        // swift-testing は安定リリースタグが存在しない開発パッケージのため branch 指定が必須。
        // Package.resolved にリビジョンが固定されているため再現性は保たれている。
        // CI 環境（Xcode 16 / Swift 6.1.2）では組み込み Testing を使用するため除外する。
        // ローカル環境（Swift 6.3）は組み込み Testing の API が外部パッケージと非互換のため
        // 外部パッケージを使用する。
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "TwitchChat",
            path: "Sources/TwitchChat",
            // Info.plist はリンカフラグで直接バイナリに埋め込むため、
            // SPM のリソース対象から除外して "unhandled file" 警告を抑制する
            exclude: ["Info.plist"],
            linkerSettings: [
                // Info.plist をバイナリに埋め込み、macOS が GUI アプリとして認識できるようにする
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TwitchChat/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "TwitchChatTests",
            dependencies: isCI
                ? ["TwitchChat"]
                : [
                    "TwitchChat",
                    .product(name: "Testing", package: "swift-testing")
                ],
            path: "Tests/TwitchChatTests",
            linkerSettings: isCI ? [] : [
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
