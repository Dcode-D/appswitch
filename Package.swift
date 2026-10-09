// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AppSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AppSwitchCore", targets: ["AppSwitchCore"]),
        .executable(name: "appswitch", targets: ["appswitch"]),
    ],
    targets: [
        .target(name: "AppSwitchCore"),
        .executableTarget(name: "appswitch", dependencies: ["AppSwitchCore"]),
        .testTarget(name: "AppSwitchCoreTests", dependencies: ["AppSwitchCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
