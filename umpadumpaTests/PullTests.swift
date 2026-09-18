import XCTest
@testable import umpadumpa

final class PullTests: XCTestCase {
    private var secrets: MemorySecretStore!
    private var clock: FixedClock!
    private var processes: FakeProcessRunner!
    private var history: MemoryHistoryStore!
    private var tunnels: FakeSSHTunnel!
    private var engine: PullEngine!

    override func setUp() {
        secrets = MemorySecretStore()
        clock = FixedClock(now: Date(timeIntervalSince1970: 1_000_000))
        processes = FakeProcessRunner()
        history = MemoryHistoryStore()
        tunnels = FakeSSHTunnel()
        engine = PullEngine(
            secrets: secrets,
            clock: clock,
            processes: processes,
            history: history,
            tunnels: tunnels
        )

        processes.tablesByDatabase["shop"] = ["users", "orders"]
        processes.tablesByDatabase["local_shop"] = ["users", "scratch_notes"]

        secrets.setPassword("src-secret", forConnectionId: source.id)
        secrets.setPassword("dst-secret", forConnectionId: destination.id)
    }

    private let source = Connection(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "Prod",
        host: "prod.example",
        port: 3306,
        user: "dump"
    )

    private let destination = Connection(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        name: "Localhost",
        host: "127.0.0.1",
        port: 3306,
        user: "root"
    )

    private func request() -> PullRequest {
        PullRequest(
            sourceConnection: source,
            sourceDatabase: "shop",
            destinationConnection: destination,
            destinationDatabase: "local_shop",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
    }

    func testConfirmNamesSourceDestinationStrategyReplaceModeAndAllTables() {
        let summary = engine.confirm(request())

        XCTAssertEqual(summary.sourceLabel, "Prod / shop")
        XCTAssertEqual(summary.destinationLabel, "Localhost / local_shop")
        XCTAssertEqual(summary.strategyLabel, "Replace")
        XCTAssertEqual(summary.replaceModeLabel, "Import in place")
        XCTAssertEqual(summary.tablesLabel, "All tables")
    }

    func testCancelMeansRunIsNeverCalledSoDestinationStaysUntouched() async throws {
        _ = engine.confirm(request())

        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertTrue(processes.invocations.isEmpty)
    }

    func testConfirmNamesDropDatabaseReplaceMode() {
        var pull = request()
        pull.replaceMode = .dropDatabase
        let summary = engine.confirm(pull)

        XCTAssertEqual(summary.replaceModeLabel, "Drop database, then import")
    }

    func testSuccessfulImportInPlaceDumpsCompletelyBeforeMysqlAndKeepsExtraTables() async throws {
        let summary = engine.confirm(request())
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertEqual(entry.source, "Prod / shop")
        XCTAssertEqual(entry.destination, "Localhost / local_shop")
        XCTAssertEqual(entry.when, Date(timeIntervalSince1970: 1_000_000))

        XCTAssertEqual(processes.invocations.map(\.tool), [.mysqldump, .mysql])
        XCTAssertTrue(processes.dumpFileWasCompleteBeforeImport)
        XCTAssertFalse(processes.didSendDropDatabase)

        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "orders", "scratch_notes"])

        let dump = processes.invocations[0]
        XCTAssertTrue(dump.arguments.contains("--add-drop-table"))
        XCTAssertEqual(dump.environment["MYSQL_PWD"], "src-secret")
        XCTAssertFalse(dump.arguments.contains("src-secret"))

        let mysql = processes.invocations[1]
        XCTAssertEqual(mysql.environment["MYSQL_PWD"], "dst-secret")
        XCTAssertEqual(mysql.arguments.last, "local_shop")
    }

    func testDropDatabaseIssuesDropThenCreateThenImportAndRemovesExtraTables() async throws {
        var pull = request()
        pull.replaceMode = .dropDatabase
        let summary = engine.confirm(pull)
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertTrue(processes.didSendDropDatabase)
        XCTAssertTrue(processes.didSendCreateDatabase)
        XCTAssertTrue(processes.dumpFileWasCompleteBeforeImport)

        let tools = processes.invocations.map(\.tool)
        XCTAssertEqual(tools, [.mysqldump, .mysql, .mysql, .mysql])

        let drop = processes.invocations[1]
        XCTAssertTrue(drop.arguments.contains("-e"))
        XCTAssertTrue(drop.arguments.joined(separator: " ").contains("DROP DATABASE"))
        XCTAssertNil(drop.inputPath)

        let create = processes.invocations[2]
        XCTAssertTrue(create.arguments.contains("-e"))
        XCTAssertTrue(create.arguments.joined(separator: " ").contains("CREATE DATABASE"))
        XCTAssertNil(create.inputPath)

        let mysql = processes.invocations[3]
        XCTAssertEqual(mysql.inputPath, processes.invocations[0].outputPath)
        XCTAssertEqual(mysql.arguments.last, "local_shop")

        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "orders"])
        XCTAssertFalse(processes.tablesByDatabase["local_shop"]!.contains("scratch_notes"))
    }

    func testDumpFailureNeverRunsMysqlAndRecordsFailedHistory() async {
        processes.failDump = true
        let summary = engine.confirm(request())

        do {
            _ = try await engine.run(summary)
            XCTFail("expected dump failure")
        } catch PullError.dumpFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(processes.invocations.map(\.tool), [.mysqldump])
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
        XCTAssertEqual(history.entries[0].source, "Prod / shop")
        XCTAssertEqual(history.entries[0].destination, "Localhost / local_shop")
    }

    func testSecondPullIsRefusedWhileOneIsRunning() async throws {
        processes.holdDump = true
        let summary = engine.confirm(request())

        let first = Task {
            try await engine.run(summary)
        }

        await processes.waitUntilDumpIsHeld()

        do {
            _ = try await engine.run(summary)
            XCTFail("second pull should be refused")
        } catch PullError.alreadyRunning {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertTrue(engine.isRunning)

        processes.releaseDump()
        _ = try await first.value
        XCTAssertFalse(engine.isRunning)
    }

    func testConfirmNamesChosenTablesAndForcesImportInPlace() {
        var pull = request()
        pull.replaceMode = .dropDatabase
        pull.tables = ["users", "orders"]

        let summary = engine.confirm(pull)

        XCTAssertEqual(summary.tablesLabel, "users, orders")
        XCTAssertEqual(summary.replaceModeLabel, "Import in place")
        XCTAssertEqual(summary.request.replaceMode, .importInPlace)
        XCTAssertEqual(summary.request.tables, ["users", "orders"])
    }

    func testEmptyTablesStillMeansEntireDatabase() {
        let summary = engine.confirm(request())

        XCTAssertEqual(summary.tablesLabel, "All tables")
        XCTAssertEqual(summary.request.tables, [])
    }

    func testSubsetDumpForwardsTableNamesAndDoesNotDropOtherDestinationTables() async throws {
        var pull = request()
        pull.replaceMode = .dropDatabase
        pull.tables = ["users"]

        let summary = engine.confirm(pull)
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertFalse(processes.didSendDropDatabase)
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])

        let dump = processes.invocations[0]
        XCTAssertEqual(dump.tool, .mysqldump)
        XCTAssertTrue(dump.arguments.contains("users"))
        XCTAssertFalse(dump.arguments.contains("orders"))
        XCTAssertEqual(dump.arguments.last, "users")
    }

    func testEntireDatabaseDumpDoesNotForwardTableNames() async throws {
        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        let dump = processes.invocations[0]
        XCTAssertEqual(dump.arguments.last, "shop")
        XCTAssertFalse(dump.arguments.contains("users"))
        XCTAssertFalse(dump.arguments.contains("orders"))
    }

    func testConfirmCreateNewShowsNewDatabaseNameAsDestination() {
        var pull = request()
        pull.strategy = .createNew
        pull.destinationDatabase = "shop_fresh"

        let summary = engine.confirm(pull)

        XCTAssertEqual(summary.strategyLabel, "Create new")
        XCTAssertEqual(summary.destinationLabel, "Localhost / shop_fresh")
        XCTAssertEqual(summary.request.destinationDatabase, "shop_fresh")
    }

    func testHistoryRowsAreOnlyALog() async throws {
        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        XCTAssertEqual(history.entries.count, 1)
        // HistoryEntry is a record of what ran. There is no way to execute it.
        XCTAssertNil(Mirror(reflecting: history.entries[0]).children.first { $0.label == "request" })
    }

    func testSSHSourceDumpUsesTunnelAddressNotRemoteMySQLHost() async throws {
        var pull = request()
        pull.sourceConnection.usesSSH = true
        pull.sourceConnection.sshHost = "bastion.example"
        pull.sourceConnection.sshPort = 2222
        pull.sourceConnection.sshUser = "jump"
        pull.sourceConnection.sshAuthMethod = .password

        tunnels.localPort = 61000
        let summary = engine.confirm(pull)
        _ = try await engine.run(summary)

        let dump = processes.invocations[0]
        XCTAssertEqual(dump.tool, .mysqldump)
        XCTAssertTrue(dump.arguments.contains("127.0.0.1"))
        XCTAssertTrue(dump.arguments.contains("61000"))
        XCTAssertFalse(dump.arguments.contains("prod.example"))
        XCTAssertEqual(processes.invocations.map(\.tool), [.mysqldump, .mysql])
    }
}

final class ConnectionStoreTests: XCTestCase {
    func testSavedConnectionKeepsPasswordInSecretsNotOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let store = DiskStore(folder: folder)

        var connection = Connection(
            id: UUID(),
            name: "Prod",
            host: "prod.example",
            port: 3307,
            user: "dump"
        )
        store.saveConnection(connection)
        secrets.setPassword("hunter2", forConnectionId: connection.id)

        let diskJSON = try String(contentsOf: store.connectionsFile, encoding: .utf8)
        XCTAssertFalse(diskJSON.contains("hunter2"))

        let loaded = store.loadConnections()
        XCTAssertEqual(loaded, [connection])
        XCTAssertEqual(secrets.password(forConnectionId: connection.id), "hunter2")
    }
}
