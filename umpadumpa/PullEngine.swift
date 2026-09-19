import Foundation

nonisolated final class PullEngine {
    private let secrets: SecretStoring
    private let clock: Clock
    private let processes: ProcessRunning
    private let history: HistoryStoring
    private let tunnels: SSHTunneling
    private let settings: SettingsStoring
    private let paths: PathChecking
    private let lastRecipes: LastRecipeStoring
    private let lock = NSLock()

    private(set) var isRunning = false
    var onPhase: (@Sendable (PullPhase) -> Void)?

    init(
        secrets: SecretStoring,
        clock: Clock,
        processes: ProcessRunning,
        history: HistoryStoring,
        tunnels: SSHTunneling,
        settings: SettingsStoring,
        paths: PathChecking,
        lastRecipes: LastRecipeStoring
    ) {
        self.secrets = secrets
        self.clock = clock
        self.processes = processes
        self.history = history
        self.tunnels = tunnels
        self.settings = settings
        self.paths = paths
        self.lastRecipes = lastRecipes
    }

    func confirm(_ request: PullRequest) -> ConfirmSummary {
        var request = request
        if request.tables.isEmpty == false {
            request.replaceMode = .importInPlace
        }

        let replaceModeLabel = request.replaceMode == .dropDatabase
            ? "Drop database, then import"
            : "Import in place"
        let tablesLabel = request.tables.isEmpty
            ? "All tables"
            : request.tables.joined(separator: ", ")

        let strategyLabel: String
        if request.strategy == .createNew {
            strategyLabel = "Create new"
        } else if request.strategy == .backupThenReplace {
            strategyLabel = "Backup and replace"
        } else {
            strategyLabel = "Replace"
        }

        if request.strategy == .backupThenReplace && request.backupName.isEmpty {
            request.backupName = BackupName.defaultName(
                database: request.destinationDatabase,
                at: clock.now
            )
        }

        return ConfirmSummary(
            sourceLabel: "\(request.sourceConnection.name) / \(request.sourceDatabase)",
            destinationLabel: "\(request.destinationConnection.name) / \(request.destinationDatabase)",
            strategyLabel: strategyLabel,
            replaceModeLabel: replaceModeLabel,
            tablesLabel: tablesLabel,
            backupNameLabel: request.strategy == .backupThenReplace ? request.backupName : "",
            request: request
        )
    }

    func run(_ summary: ConfirmSummary) async throws -> HistoryEntry {
        lock.lock()
        if isRunning {
            lock.unlock()
            throw PullError.alreadyRunning
        }
        isRunning = true
        lock.unlock()
        report(.dumpingSource)

        defer {
            tunnels.closeOpenedTunnels()
            lock.lock()
            isRunning = false
            lock.unlock()
        }

        let request: PullRequest = {
            var request = summary.request
            if request.tables.isEmpty == false {
                request.replaceMode = .importInPlace
            }
            if request.strategy == .backupThenReplace && request.backupName.isEmpty {
                request.backupName = BackupName.defaultName(
                    database: request.destinationDatabase,
                    at: clock.now
                )
            }
            return request
        }()
        let dumpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("umpadumpa-\(UUID().uuidString).sql")
            .path

        do {
            _ = try executable(for: .mysqldump)
            _ = try executable(for: .mysql)
        } catch {
            let entry = makeHistory(request: request, succeeded: false)
            rememberPull(entry, request: request)
            report(.failed)
            throw error
        }

        var destReach: OpenTunnel?
        let reservedName: String?
        if request.strategy == .createNew {
            reservedName = request.destinationDatabase
        } else if request.strategy == .backupThenReplace {
            reservedName = request.backupName
        } else {
            reservedName = nil
        }

        if let reservedName {
            destReach = try await reachability(for: request.destinationConnection, historyRequest: request)
            let names = try await loadDatabaseNames(
                connection: request.destinationConnection,
                reach: destReach!,
                historyRequest: request
            )
            if names.contains(reservedName) {
                report(.failed)
                throw PullError.nameAlreadyExists
            }
        }

        let sourceReach = try await reachability(for: request.sourceConnection, historyRequest: request)

        do {
            try await processes.run(
                try command(
                    tool: .mysqldump,
                    connection: request.sourceConnection,
                    host: sourceReach.localHost,
                    port: sourceReach.localPort,
                    database: request.sourceDatabase,
                    extra: ["--add-drop-table"],
                    tables: request.tables,
                    outputPath: dumpFile,
                    inputPath: nil
                )
            )
        } catch let PullError.dumpFailed(detail) {
            let entry = makeHistory(request: request, succeeded: false)
            rememberPull(entry, request: request)
            report(.failed)
            throw PullError.dumpFailed(detail)
        } catch {
            let entry = makeHistory(request: request, succeeded: false)
            rememberPull(entry, request: request)
            report(.failed)
            throw PullError.dumpFailed(String(describing: error))
        }

        if destReach == nil {
            do {
                destReach = try await openReachability(for: request.destinationConnection)
            } catch {
                let entry = makeHistory(request: request, succeeded: false)
                rememberPull(entry, request: request)
                report(.failed)
                throw PullError.tunnelFailed
            }
        }

        let destinationReach = destReach!

        do {
            if request.strategy == .backupThenReplace {
                report(.creatingBackup)
                let backupFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("umpadumpa-backup-\(UUID().uuidString).sql")
                    .path
                try await processes.run(
                    try command(
                        tool: .mysqldump,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: request.destinationDatabase,
                        extra: ["--add-drop-table"],
                        outputPath: backupFile,
                        inputPath: nil
                    )
                )
                try await processes.run(
                    try command(
                        tool: .mysql,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: nil,
                        extra: ["-e", "CREATE DATABASE `\(request.backupName)`"],
                        outputPath: nil,
                        inputPath: nil
                    )
                )
                try await processes.run(
                    try command(
                        tool: .mysql,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: request.backupName,
                        extra: [],
                        outputPath: nil,
                        inputPath: backupFile
                    )
                )
            }

            report(.importingDestination)

            if request.strategy == .createNew {
                try await processes.run(
                    try command(
                        tool: .mysql,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: nil,
                        extra: ["-e", "CREATE DATABASE `\(request.destinationDatabase)`"],
                        outputPath: nil,
                        inputPath: nil
                    )
                )
            } else if request.replaceMode == .dropDatabase && request.tables.isEmpty {
                try await processes.run(
                    try command(
                        tool: .mysql,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: nil,
                        extra: ["-e", "DROP DATABASE `\(request.destinationDatabase)`"],
                        outputPath: nil,
                        inputPath: nil
                    )
                )
                try await processes.run(
                    try command(
                        tool: .mysql,
                        connection: request.destinationConnection,
                        host: destinationReach.localHost,
                        port: destinationReach.localPort,
                        database: nil,
                        extra: ["-e", "CREATE DATABASE `\(request.destinationDatabase)`"],
                        outputPath: nil,
                        inputPath: nil
                    )
                )
            }

            try await processes.run(
                try command(
                    tool: .mysql,
                    connection: request.destinationConnection,
                    host: destinationReach.localHost,
                    port: destinationReach.localPort,
                    database: request.destinationDatabase,
                    extra: [],
                    outputPath: nil,
                    inputPath: dumpFile
                )
            )
        } catch {
            let entry = makeHistory(request: request, succeeded: false)
            rememberPull(entry, request: request)
            report(.failed)
            throw PullError.importFailed
        }

        let entry = makeHistory(request: request, succeeded: true)
        rememberPull(entry, request: request)
        report(.succeeded)
        return entry
    }

    private func reachability(for connection: Connection, historyRequest: PullRequest) async throws -> OpenTunnel {
        do {
            return try await openReachability(for: connection)
        } catch {
            let entry = makeHistory(request: historyRequest, succeeded: false)
            rememberPull(entry, request: historyRequest)
            report(.failed)
            throw PullError.tunnelFailed
        }
    }

    private func openReachability(for connection: Connection) async throws -> OpenTunnel {
        if connection.usesSSH == false {
            return OpenTunnel(localHost: connection.host, localPort: connection.port)
        }
        if connection.sshHost.isEmpty || connection.sshUser.isEmpty {
            throw PullError.tunnelFailed
        }
        return try await tunnels.openTunnel(for: connection)
    }

    private func command(
        tool: ClientTool,
        connection: Connection,
        host: String,
        port: Int,
        database: String?,
        extra: [String],
        tables: [String] = [],
        outputPath: String?,
        inputPath: String?
    ) throws -> ExternalCommand {
        let executable = try executable(for: tool)
        let dumpCompression = tool == .mysqldump
            ? ["--compression-algorithms=zstd,zlib,uncompressed"]
            : []
        return ExternalCommand(
            tool: tool,
            executable: executable,
            arguments: dumpCompression + extra + [
                "-h", host,
                "-P", String(port),
                "-u", connection.user
            ] + (database.map { [$0] } ?? []) + tables,
            environment: passwordEnvironment(for: connection.id),
            outputPath: outputPath,
            inputPath: inputPath
        )
    }

    private func loadDatabaseNames(
        connection: Connection,
        reach: OpenTunnel,
        historyRequest: PullRequest
    ) async throws -> [String] {
        let listingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("umpadumpa-databases-\(UUID().uuidString).txt")
            .path
        do {
            try await processes.run(
                try command(
                    tool: .mysql,
                    connection: connection,
                    host: reach.localHost,
                    port: reach.localPort,
                    database: nil,
                    extra: ["-e", "SHOW DATABASES"],
                    outputPath: listingFile,
                    inputPath: nil
                )
            )
        } catch {
            let entry = makeHistory(request: historyRequest, succeeded: false)
            rememberPull(entry, request: historyRequest)
            report(.failed)
            throw PullError.importFailed
        }

        let listing = (try? String(contentsOfFile: listingFile, encoding: .utf8)) ?? ""
        return databaseNames(fromListing: listing)
    }

    private func executable(for tool: ClientTool) throws -> String {
        let stored = settings.load()
        let configured = (tool == .mysqldump ? stored.mysqldumpPath : stored.mysqlPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty {
            return tool == .mysqldump ? "mysqldump" : "mysql"
        }
        if paths.pathExists(configured) == false {
            throw PullError.missingClient(tool)
        }
        return configured
    }

    private func passwordEnvironment(for connectionId: UUID) -> [String: String] {
        var environment: [String: String] = [:]
        if let password = secrets.password(forConnectionId: connectionId) {
            environment["MYSQL_PWD"] = password
        }
        return environment
    }

    private func report(_ phase: PullPhase) {
        onPhase?(phase)
    }

    private func rememberPull(_ entry: HistoryEntry, request: PullRequest) {
        history.append(entry)
        if let recipeId = request.recipeId {
            lastRecipes.record(recipeId: recipeId, forSourceConnectionId: request.sourceConnection.id)
        }
    }

    private func makeHistory(request: PullRequest, succeeded: Bool) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            when: clock.now,
            source: "\(request.sourceConnection.name) / \(request.sourceDatabase)",
            destination: "\(request.destinationConnection.name) / \(request.destinationDatabase)",
            succeeded: succeeded
        )
    }

    private func databaseNames(fromListing listing: String) -> [String] {
        var names: [String] = []
        for line in listing.split(separator: "\n") {
            let name = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            if name == "Database" {
                continue
            }
            names.append(name)
        }
        return names
    }
}
