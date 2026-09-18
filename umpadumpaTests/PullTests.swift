import XCTest
@testable import umpadumpa

final class PullTests: XCTestCase {
    private var secrets: MemorySecretStore!
    private var clock: FixedClock!
    private var processes: FakeProcessRunner!
    private var history: MemoryHistoryStore!
    private var tunnels: FakeSSHTunnel!
    private var settings: MemorySettingsStore!
    private var paths: FakePathChecker!
    private var engine: PullEngine!

    override func setUp() {
        secrets = MemorySecretStore()
        clock = FixedClock(now: Date(timeIntervalSince1970: 1_000_000))
        processes = FakeProcessRunner()
        history = MemoryHistoryStore()
        tunnels = FakeSSHTunnel()
        settings = MemorySettingsStore()
        paths = FakePathChecker()
        engine = PullEngine(
            secrets: secrets,
            clock: clock,
            processes: processes,
            history: history,
            tunnels: tunnels,
            settings: settings,
            paths: paths
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

    func testConfirmBackupThenReplaceShowsDefaultBackupNameAndKeepsReplaceMode() {
        var pull = request()
        pull.strategy = .backupThenReplace
        pull.replaceMode = .dropDatabase

        let summary = engine.confirm(pull)

        XCTAssertEqual(summary.strategyLabel, "Backup and replace")
        XCTAssertEqual(summary.replaceModeLabel, "Drop database, then import")
        XCTAssertEqual(summary.backupNameLabel, "local_shop_backup_19700112_1346")
        XCTAssertEqual(summary.request.backupName, "local_shop_backup_19700112_1346")
        XCTAssertEqual(summary.request.replaceMode, .dropDatabase)
    }

    func testConfirmBackupThenReplaceKeepsEditedBackupName() {
        var pull = request()
        pull.strategy = .backupThenReplace
        pull.backupName = "shop_keep"

        let summary = engine.confirm(pull)

        XCTAssertEqual(summary.backupNameLabel, "shop_keep")
        XCTAssertEqual(summary.request.backupName, "shop_keep")
    }

    func testBackupThenReplaceImportInPlaceCopiesWholeDestinationBeforeReplace() async throws {
        var pull = request()
        pull.strategy = .backupThenReplace
        let summary = engine.confirm(pull)
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertEqual(
            processes.tablesByDatabase["local_shop_backup_19700112_1346"],
            ["users", "scratch_notes"]
        )
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "orders", "scratch_notes"])
        XCTAssertFalse(processes.didSendDropDatabase)
        XCTAssertTrue(processes.dumpFileWasCompleteBeforeImport)

        let sourceDump = processes.invocations.first { command in
            command.tool == .mysqldump && command.arguments.contains("shop")
        }
        XCTAssertNotNil(sourceDump)
        XCTAssertEqual(sourceDump?.arguments.last, "shop")

        let destDump = processes.invocations.first { command in
            command.tool == .mysqldump && command.arguments.contains("local_shop")
        }
        XCTAssertNotNil(destDump)
        XCTAssertFalse(destDump!.arguments.contains("users"))
    }

    func testBackupThenReplaceDropDatabaseCopiesDestinationThenDrops() async throws {
        var pull = request()
        pull.strategy = .backupThenReplace
        pull.replaceMode = .dropDatabase
        let summary = engine.confirm(pull)
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertTrue(processes.didSendDropDatabase)
        XCTAssertEqual(
            processes.tablesByDatabase["local_shop_backup_19700112_1346"],
            ["users", "scratch_notes"]
        )
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "orders"])
        XCTAssertFalse(processes.tablesByDatabase["local_shop"]!.contains("scratch_notes"))
    }

    func testExistingBackupNameAbortsPullWithNoDestinationChange() async {
        processes.tablesByDatabase["shop_keep"] = ["old_backup"]

        var pull = request()
        pull.strategy = .backupThenReplace
        pull.backupName = "shop_keep"
        let summary = engine.confirm(pull)

        do {
            _ = try await engine.run(summary)
            XCTFail("expected name collision")
        } catch PullError.nameAlreadyExists {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertFalse(processes.invocations.contains(where: { $0.tool == .mysqldump }))
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(processes.tablesByDatabase["shop_keep"], ["old_backup"])
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testFailedImportAfterBackupLeavesBackupAndDoesNotSucceed() async {
        processes.failImport = true

        var pull = request()
        pull.strategy = .backupThenReplace
        let summary = engine.confirm(pull)

        do {
            _ = try await engine.run(summary)
            XCTFail("expected import failure")
        } catch PullError.importFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(
            processes.tablesByDatabase["local_shop_backup_19700112_1346"],
            ["users", "scratch_notes"]
        )
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
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

    func testCreateNewNameCollisionDoesNotStartAndCreatesNothing() async {
        processes.tablesByDatabase["shop_fresh"] = ["old"]

        var pull = request()
        pull.strategy = .createNew
        pull.destinationDatabase = "shop_fresh"
        let summary = engine.confirm(pull)

        do {
            _ = try await engine.run(summary)
            XCTFail("expected name collision")
        } catch PullError.nameAlreadyExists {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertFalse(processes.invocations.contains(where: { $0.tool == .mysqldump }))
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(processes.tablesByDatabase["shop_fresh"], ["old"])
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testCreateNewImportsIntoNewDatabaseAndLeavesPreviousDestinationUnchanged() async throws {
        var pull = request()
        pull.strategy = .createNew
        pull.destinationDatabase = "shop_fresh"
        let summary = engine.confirm(pull)
        let entry = try await engine.run(summary)

        XCTAssertTrue(entry.succeeded)
        XCTAssertEqual(entry.destination, "Localhost / shop_fresh")
        XCTAssertTrue(processes.dumpFileWasCompleteBeforeImport)
        XCTAssertFalse(processes.didSendDropDatabase)
        XCTAssertTrue(processes.didSendCreateDatabase)
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(processes.tablesByDatabase["shop_fresh"], ["users", "orders"])
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

    func testSSHDestinationImportUsesTunnelAddress() async throws {
        var pull = request()
        pull.destinationConnection.usesSSH = true
        pull.destinationConnection.sshHost = "jump.local"
        pull.destinationConnection.sshUser = "me"
        tunnels.localPort = 62000

        _ = try await engine.run(engine.confirm(pull))

        let mysql = processes.invocations.last
        XCTAssertEqual(mysql?.tool, .mysql)
        XCTAssertTrue(mysql?.arguments.contains("127.0.0.1") == true)
        XCTAssertTrue(mysql?.arguments.contains("62000") == true)
    }

    func testTunnelFailureRecordsFailedHistoryAndDoesNotTouchDestination() async {
        var pull = request()
        pull.sourceConnection.usesSSH = true
        pull.sourceConnection.sshHost = "bastion.example"
        pull.sourceConnection.sshUser = "jump"
        tunnels.failOpen = true

        do {
            _ = try await engine.run(engine.confirm(pull))
            XCTFail("expected tunnel failure")
        } catch PullError.tunnelFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertTrue(processes.invocations.isEmpty)
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
    }

    func testDirectConnectionStillUsesMySQLHostAndPort() async throws {
        _ = try await engine.run(engine.confirm(request()))

        let dump = processes.invocations[0]
        XCTAssertTrue(dump.arguments.contains("prod.example"))
        XCTAssertTrue(dump.arguments.contains("3306"))
        XCTAssertTrue(tunnels.openedFor.isEmpty)
    }

    func testEmptySettingsUsePathClientNames() async throws {
        settings.save(.usingPath)

        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        XCTAssertEqual(processes.invocations[0].executable, "mysqldump")
        XCTAssertEqual(processes.invocations[1].executable, "mysql")
    }

    func testConfiguredSettingsPathsAreUsedOnDumpAndImport() async throws {
        settings.save(
            ClientSettings(
                mysqldumpPath: "/opt/homebrew/bin/mysqldump",
                mysqlPath: "/opt/homebrew/bin/mysql"
            )
        )

        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        XCTAssertEqual(processes.invocations[0].executable, "/opt/homebrew/bin/mysqldump")
        XCTAssertEqual(processes.invocations[1].executable, "/opt/homebrew/bin/mysql")
    }

    func testMissingConfiguredClientFailsBeforeDestinationAndRecordsFailedHistory() async {
        settings.save(
            ClientSettings(
                mysqldumpPath: "/missing/mysqldump",
                mysqlPath: "/opt/homebrew/bin/mysql"
            )
        )
        paths.missing.insert("/missing/mysqldump")

        let summary = engine.confirm(request())

        do {
            _ = try await engine.run(summary)
            XCTFail("expected missing client")
        } catch PullError.missingClient(.mysqldump) {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertTrue(processes.invocations.isEmpty)
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
    }
}

final class SettingsStoreTests: XCTestCase {
    func testSettingsStoreAbsoluteClientPathsOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)
        let store = DiskSettingsStore(disk: disk)

        store.save(
            ClientSettings(
                mysqldumpPath: "/opt/homebrew/bin/mysqldump",
                mysqlPath: "/opt/homebrew/bin/mysql"
            )
        )

        let loaded = store.load()
        XCTAssertEqual(loaded.mysqldumpPath, "/opt/homebrew/bin/mysqldump")
        XCTAssertEqual(loaded.mysqlPath, "/opt/homebrew/bin/mysql")
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

    func testSavedSSHConnectionKeepsSecretsOutOfDiskJSON() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let store = DiskStore(folder: folder)

        let connection = Connection(
            id: UUID(),
            name: "Prod SSH",
            host: "10.0.0.8",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .privateKey,
            sshKeyPath: "/Users/me/keys/prod.pem"
        )
        store.saveConnection(connection)
        secrets.setPassword("mysql-secret", forConnectionId: connection.id)
        secrets.setSSHPassword("ssh-secret", forConnectionId: connection.id)
        secrets.setSSHPassphrase("pem-phrase", forConnectionId: connection.id)

        let diskJSON = try String(contentsOf: store.connectionsFile, encoding: .utf8)
        XCTAssertFalse(diskJSON.contains("mysql-secret"))
        XCTAssertFalse(diskJSON.contains("ssh-secret"))
        XCTAssertFalse(diskJSON.contains("pem-phrase"))
        XCTAssertTrue(diskJSON.contains("bastion.example"))
        XCTAssertTrue(diskJSON.contains("prod.pem"))

        let loaded = store.loadConnections()
        XCTAssertEqual(loaded, [connection])
        XCTAssertEqual(secrets.sshPassword(forConnectionId: connection.id), "ssh-secret")
        XCTAssertEqual(secrets.sshPassphrase(forConnectionId: connection.id), "pem-phrase")
    }
}
