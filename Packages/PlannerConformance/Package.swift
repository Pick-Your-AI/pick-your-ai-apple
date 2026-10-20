// swift-tools-version: 6.0
import PackageDescription

// A test-only consumer of existing client boundaries. It supplies no app product.
let package = Package(
    name: "PlannerConformance",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [.package(path: "../PlannerCore"), .package(path: "../PlannerTransfer")],
    targets: [.testTarget(name: "PlannerConformanceTests",
                          dependencies: [.product(name: "PlannerCore", package: "PlannerCore"),
                                         .product(name: "PlannerTransfer", package: "PlannerTransfer")],
                          resources: [.process("Fixtures")])])
