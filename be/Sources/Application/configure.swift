import Fluent
import FluentPostgresDriver
import JWT
import Vapor

public func configure(_ app: Application) async throws {
    app.passwords.use(.bcrypt)
    app.middleware.use(TraceIDMiddleware())
    app.middleware.use(RequestLoggingMiddleware())
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(CORSMiddleware(configuration: .default()))

    let hostname = Environment.get("HOSTNAME") ?? "0.0.0.0"
    let port = Environment.get("PORT").flatMap(Int.init(_:)) ?? 8080
    app.http.server.configuration.hostname = hostname
    app.http.server.configuration.port = port

    if let jwtSecret = Environment.get("JWT_SECRET"), !jwtSecret.isEmpty {
        app.jwt.signers.use(.hs256(key: jwtSecret), kid: "default")
    } else {
        app.jwt.signers.use(.hs256(key: "dev-insecure-change-me-min-32-characters!!"), kid: "default")
    }

    let databaseHost = Environment.get("DATABASE_HOST") ?? "localhost"
    let databasePort = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? 5432
    let databaseName = Environment.get("DATABASE_NAME") ?? "tasktracker"
    let databaseUser = Environment.get("DATABASE_USERNAME") ?? "vapor"
    let databasePassword = Environment.get("DATABASE_PASSWORD") ?? "vapor"

    app.databases.use(
        .postgres(
            configuration: .init(
                hostname: databaseHost,
                port: databasePort,
                username: databaseUser,
                password: databasePassword,
                database: databaseName,
                tls: .disable
            )
        ),
        as: .psql
    )

    app.migrations.add(CreateSchema())
    app.migrations.add(SeedRBACAndDemo())

    try await app.autoMigrate()

    try await routes(app)
}
