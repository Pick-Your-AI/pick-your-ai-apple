// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlannerTransfer", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PlannerTransfer", targets: ["PlannerTransfer"])],
    dependencies: [.package(path: "../PlannerData")],
    targets: [.target(name: "PlannerTransfer", resources: [.process("Resources")]),
              .testTarget(name: "PlannerTransferTests", dependencies: ["PlannerTransfer", .product(name: "PlannerData", package: "PlannerData")], resources: [.process("Fixtures")])],
    swiftLanguageModes: [.v6])
