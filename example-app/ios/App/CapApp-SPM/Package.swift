// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.1.0"),
        .package(name: "CapacitorApp", path: "../../../node_modules/.bun/@capacitor+app@7.1.1+15e98482558ccfe6/node_modules/@capacitor/app"),
        .package(name: "CapacitorHaptics", path: "../../../node_modules/.bun/@capacitor+haptics@7.0.3+15e98482558ccfe6/node_modules/@capacitor/haptics"),
        .package(name: "CapacitorKeyboard", path: "../../../node_modules/.bun/@capacitor+keyboard@7.0.4+15e98482558ccfe6/node_modules/@capacitor/keyboard"),
        .package(name: "CapacitorStatusBar", path: "../../../node_modules/.bun/@capacitor+status-bar@7.0.3+15e98482558ccfe6/node_modules/@capacitor/status-bar"),
        .package(name: "CapgoCameraPreview", path: "../../../node_modules/.bun/@capgo+camera-preview@file+../node_modules/@capgo/camera-preview")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "CapacitorApp", package: "CapacitorApp"),
                .product(name: "CapacitorHaptics", package: "CapacitorHaptics"),
                .product(name: "CapacitorKeyboard", package: "CapacitorKeyboard"),
                .product(name: "CapacitorStatusBar", package: "CapacitorStatusBar"),
                .product(name: "CapgoCameraPreview", package: "CapgoCameraPreview")
            ]
        )
    ]
)
