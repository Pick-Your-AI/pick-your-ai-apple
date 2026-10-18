// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlannerData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PlannerData", targets: ["PlannerData"]),
               .executable(name: "DraftCrashProbe", targets: ["DraftCrashProbe"])],
    targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
              .target(name: "PlannerData", dependencies: ["CSQLite"]),
              .executableTarget(name: "DraftCrashProbe", dependencies: ["PlannerData"]),
              .testTarget(name: "PlannerDataTests", dependencies: ["PlannerData", "CSQLite"])])
