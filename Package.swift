// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCapacitorPhotoLibrary",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapgoCapacitorPhotoLibrary",
            targets: ["PhotoLibraryPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "PhotoLibraryPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/PhotoLibraryPlugin"),
        .testTarget(
            name: "PhotoLibraryPluginTests",
            dependencies: ["PhotoLibraryPlugin"],
            path: "ios/Tests/PhotoLibraryPluginTests")
    ]
)
