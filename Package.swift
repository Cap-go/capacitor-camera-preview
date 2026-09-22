// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCameraPreview",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "CapgoCameraPreview",
            targets: ["CapgoCameraPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor.git", from: "9.0.0-alpha.7")
    ],
    targets: [
        .target(
            name: "CapgoCameraPreview",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor"),
            ],
            path: "ios/Sources/CapgoCameraPreviewPlugin"),
        .testTarget(
            name: "CapgoCameraPreviewTests",
            dependencies: ["CapgoCameraPreview"],
            path: "ios/Tests/CameraPreviewPluginTests")
    ]
)
