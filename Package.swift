// swift-tools-version: 6.0

import PackageDescription

// Builds the Foundation-only logic in QuietCast/ without moving those files.
// Screens and playback stay in the Xcode app target.
let package = Package(
    name: "QuietCast",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "QuietCastLogic", targets: ["QuietCastLogic"]),
    ],
    targets: [
        .target(
            name: "QuietCastLogic",
            path: "QuietCast",
            exclude: [
                "Assets.xcassets",
                "AudioPlayer.swift",
                "BuildInfo.swift",
                "ContentView.swift",
                "DownloadManager.swift",
                "EpisodeListView.swift",
                "Info.plist",
                "LibraryView.swift",
                "NowPlayingBar.swift",
                "QuietCast.entitlements",
                "QuietCastApp.swift",
                "RemoteCommandHandler.swift",
                "SearchView.swift",
                "SettingsView.swift",
                "SpeechAnnouncer.swift",
                "VolumeEnforcer.swift",
                "iTunesSearchService.swift",
                "silence.wav",
            ],
            sources: [
                "AppSettings.swift",
                "HTMLCleaner.swift",
                "Models.swift",
                "PersistenceManager.swift",
                "RSSParser.swift",
                "TimeGate.swift",
                "VolumePolicy.swift",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "QuietCastTests",
            dependencies: ["QuietCastLogic"],
            path: "QuietCastTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
