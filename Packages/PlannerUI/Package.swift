// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlannerUI", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PlannerUI", targets: ["PlannerUI"])],
    dependencies: [.package(path: "../PlannerData"), .package(path: "../PlannerCatalog"), .package(path: "../PlannerTransfer")],
    targets: [.target(name: "PlannerUI", dependencies: ["PlannerData", "PlannerCatalog", "PlannerTransfer"],
                     resources: [.process("Resources"), .process("PrivacyInfo.xcprivacy")]),
              .testTarget(name: "PlannerUITests", dependencies: ["PlannerUI", "PlannerData", "PlannerCatalog", "PlannerTransfer"], resources: [.process("Fixtures")])],
    swiftLanguageModes: [.v6]
)
