// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlannerTransfer", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PlannerTransfer", targets: ["PlannerTransfer"])],
    dependencies: [.package(path: "../PlannerData"), .package(path: "../PlannerCore"),
                   .package(path: "../PlannerCatalog")],
    targets: [.target(name: "PlannerTransfer", dependencies: [
                  .product(name: "PlannerCore", package: "PlannerCore")
              ], resources: [.process("Resources")]),
              .testTarget(name: "PlannerTransferTests", dependencies: [
                  "PlannerTransfer", .product(name: "PlannerData", package: "PlannerData"),
                  .product(name: "PlannerCore", package: "PlannerCore"),
                  .product(name: "PlannerCatalog", package: "PlannerCatalog")
              ], resources: [.process("Fixtures")])],
    swiftLanguageModes: [.v6])
