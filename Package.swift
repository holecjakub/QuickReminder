// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickReminderCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "QuickReminderCore",
            targets: ["QuickReminderCore"]
        )
    ],
    targets: [
        .target(
            name: "QuickReminderCore",
            path: "Sources/QuickReminder",
            exclude: ["QuickReminderApp.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("MapKit"),
                .linkedFramework("CoreLocation")
            ]
        ),
        .testTarget(
            name: "QuickReminderCoreTests",
            dependencies: ["QuickReminderCore"],
            path: "Tests/QuickReminderCoreTests"
        )
    ]
)
