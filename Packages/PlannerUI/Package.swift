// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlannerUI", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PlannerUI", targets: ["PlannerUI"])],
    dependencies: [.package(path: "../PlannerData"), .package(path: "../PlannerCore"), .package(path: "../PlannerTransfer")],
    targets: [.target(name: "PlannerUI", dependencies: ["PlannerData", "PlannerCore", "PlannerTransfer"]),
              .testTarget(name: "PlannerUITests", dependencies: ["PlannerUI", "PlannerData", "PlannerCore", "PlannerTransfer"],
                          resources: [.process("Fixtures")])],
    swiftLanguageModes: [.v6]
)
