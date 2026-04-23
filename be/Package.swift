// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TaskTrackerAPI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Run", targets: ["Run"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.3"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.11.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.2"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.29.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "Application"),
            ],
            path: "Sources/Run"
        ),
        .target(
            name: "Application",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "SQLKit", package: "sql-kit"),
            ],
            path: "Sources/Application",
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: [
                .target(name: "Application"),
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ],
            path: "Tests/ApplicationTests"
        ),
    ]
)
