import Foundation

nonisolated final class PullEngine {
    private let secrets: SecretStoring
    private let clock: Clock
    private let processes: ProcessRunning
    private let history: HistoryStoring
    private let lock = NSLock()

    private(set) var isRunning = false

    init(
        secrets: SecretStoring,
        clock: Clock,
        processes: ProcessRunning,
        history: HistoryStoring
    ) {
        self.secrets = secrets
        self.clock = clock
        self.processes = processes
        self.history = history
    }

    func confirm(_ request: PullRequest) -> ConfirmSummary {
        ConfirmSummary(
            sourceLabel: "\(request.sourceConnection.name) / \(request.sourceDatabase)",
            destinationLabel: "\(request.destinationConnection.name) / \(request.destinationDatabase)",
            strategyLabel: "Replace",
            replaceModeLabel: "Import in place",
            tablesLabel: request.tables.isEmpty ? "All tables" : request.tables.joined(separator: ", "),
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

        defer {
            lock.lock()
            isRunning = false
            lock.unlock()
        }

        let request = summary.request
        let dumpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("umpadumpa-\(UUID().uuidString).sql")
            .path

        do {
            try await processes.run(
                ExternalCommand(
                    tool: .mysqldump,
                    arguments: mysqlArguments(for: request.sourceConnection, database: request.sourceDatabase, extra: ["--add-drop-table"]),
                    environment: passwordEnvironment(for: request.sourceConnection.id),
                    outputPath: dumpFile,
                    inputPath: nil
                )
            )
        } catch {
            let entry = makeHistory(request: request, succeeded: false)
            history.append(entry)
            throw PullError.dumpFailed
        }

        do {
            try await processes.run(
                ExternalCommand(
                    tool: .mysql,
                    arguments: mysqlArguments(for: request.destinationConnection, database: request.destinationDatabase, extra: []),
                    environment: passwordEnvironment(for: request.destinationConnection.id),
                    outputPath: nil,
                    inputPath: dumpFile
                )
            )
        } catch {
            let entry = makeHistory(request: request, succeeded: false)
            history.append(entry)
            throw PullError.importFailed
        }

        let entry = makeHistory(request: request, succeeded: true)
        history.append(entry)
        return entry
    }

    private func mysqlArguments(for connection: Connection, database: String, extra: [String]) -> [String] {
        extra + [
            "-h", connection.host,
            "-P", String(connection.port),
            "-u", connection.user,
            database
        ]
    }

    private func passwordEnvironment(for connectionId: UUID) -> [String: String] {
        var environment: [String: String] = [:]
        if let password = secrets.password(forConnectionId: connectionId) {
            environment["MYSQL_PWD"] = password
        }
        return environment
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
}
