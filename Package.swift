// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCameraPreview",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapgoCameraPreview",
            targets: ["CapgoCameraPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.1.0")
    ],
    targets: [
        .target(
            name: "CapgoCameraPreview",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/CapgoCameraPreviewPlugin"),
        .testTarget(
            name: "CapgoCameraPreviewTests",
            dependencies: ["CapgoCameraPreview"],
            path: "ios/Tests/CameraPreviewPluginTests")
    ]
)
