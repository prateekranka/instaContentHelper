// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MiraCore", platforms: [.iOS("26.0")], products: [.library(name: "MiraCore", targets: ["MiraCore"])], targets: [
    .target(name: "MiraCore", path: "CreatorContentOS/Mira/Core"),
    .testTarget(name: "MiraCoreTests", dependencies: ["MiraCore"], path: "Tests/MiraCoreTests")
])
