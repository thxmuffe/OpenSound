// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ParviKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "ParviKit", type: .static, targets: ["ParviKit"])],
    targets: [.target(name: "ParviKit")]
)
