// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlannerCatalog",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "PlannerCatalog", targets: ["PlannerCatalog"])],
    targets: [
        .target(name: "PlannerCatalog"),
        .testTarget(name: "PlannerCatalogTests", dependencies: ["PlannerCatalog"])
    ],
    swiftLanguageModes: [.v6]
)
