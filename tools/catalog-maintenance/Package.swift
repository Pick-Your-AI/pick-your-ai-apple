// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatalogMaintenanceRehearsal",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MaintenanceDrill", targets: ["MaintenanceDrill"])],
    dependencies: [
        .package(path: "../../Packages/PlannerCore"),
        .package(path: "../../Packages/PlannerData"),
        .package(path: "../../Packages/PlannerCatalog"),
        .package(path: "../../Packages/PlannerTransfer")
    ],
    targets: [.executableTarget(name: "MaintenanceDrill", dependencies: [
        .product(name: "PlannerCore", package: "PlannerCore"),
        .product(name: "PlannerData", package: "PlannerData"),
        .product(name: "PlannerCatalog", package: "PlannerCatalog"),
        .product(name: "PlannerTransfer", package: "PlannerTransfer")
    ], resources: [.copy("Fixtures")])],
    swiftLanguageModes: [.v6]
)
