// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlannerCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "PlannerCore", targets: ["PlannerCore"])],
    targets: [
        .target(name: "PlannerCore"),
        .testTarget(name: "PlannerCoreTests", dependencies: ["PlannerCore"], resources: [.process("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
