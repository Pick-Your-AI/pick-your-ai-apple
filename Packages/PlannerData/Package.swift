// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PlannerData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PlannerData", targets: ["PlannerData"]),
               .executable(name: "DraftCrashProbe", targets: ["DraftCrashProbe"]),
               .executable(name: "PendingWriteCrashProbe", targets: ["PendingWriteCrashProbe"])],
    targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
              .target(name: "PlannerData", dependencies: ["CSQLite"]),
              .executableTarget(name: "DraftCrashProbe", dependencies: ["PlannerData"]),
              .executableTarget(name: "PendingWriteCrashProbe", dependencies: ["PlannerData"]),
              .testTarget(name: "PlannerDataTests", dependencies: ["PlannerData", "CSQLite"])])
