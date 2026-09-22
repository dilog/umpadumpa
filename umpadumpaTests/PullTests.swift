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

    func testSourceDumpAsksMySQLClientForProtocolCompression() async throws {
        _ = try await engine.run(engine.confirm(request()))

        let dump = processes.invocations.first { command in
            command.tool == .mysqldump && command.arguments.contains("shop")
        }
        XCTAssertNotNil(dump)
        XCTAssertTrue(dump!.arguments.contains("--compression-algorithms=zstd,zlib,uncompressed"))
        XCTAssertFalse(dump!.arguments.contains("--compress"))
        XCTAssertFalse(dump!.arguments.contains { $0.localizedCaseInsensitiveContains("gzip") })
        XCTAssertEqual((dump!.outputPath as NSString?)?.pathExtension, "sql")
    }

    func testBackupDumpAsksMySQLClientForTheSameProtocolCompression() async throws {
        var pull = request()
        pull.strategy = .backupThenReplace
        _ = try await engine.run(engine.confirm(pull))

        let destDump = processes.invocations.first { command in
            command.tool == .mysqldump && command.arguments.contains("local_shop")
        }
        XCTAssertNotNil(destDump)
        XCTAssertTrue(destDump!.arguments.contains("--compression-algorithms=zstd,zlib,uncompressed"))
        XCTAssertFalse(destDump!.arguments.contains("--compress"))
        XCTAssertFalse(destDump!.arguments.contains { $0 == "--gzip" || $0.hasSuffix(".gz") })
        XCTAssertEqual((destDump!.outputPath as NSString?)?.pathExtension, "sql")
    }

    func testEntireDatabaseDumpUsesShowTablesAndReportsNOfMDuringDump() async throws {
        var progress: [PullProgress] = []
        let lock = NSLock()
        engine.onProgress = { update in
            lock.lock()
            progress.append(update)
            lock.unlock()
        }

        _ = try await engine.run(engine.confirm(request()))

        let showTables = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.joined(separator: " ").contains("SHOW TABLES")
        }
        XCTAssertNotNil(showTables)
        XCTAssertTrue(showTables!.arguments.contains("shop"))

        let dumpProgress = progress.filter { update in
            update.phase == .dumpingSource && update.tablesTotal > 0
        }
        XCTAssertEqual(dumpProgress.first?.tablesTotal, 2)
        XCTAssertEqual(dumpProgress.first?.tablesReached, 0)
        XCTAssertEqual(dumpProgress.last?.tablesReached, 2)
        XCTAssertEqual(dumpProgress.last?.tablesTotal, 2)

        let importProgress = progress.filter { $0.phase == .importingDestination }
        XCTAssertFalse(importProgress.isEmpty)
        XCTAssertTrue(importProgress.allSatisfy { $0.tablesTotal == 0 && $0.tablesReached == 0 })
    }

    func testSubsetDumpUsesPullTablesAsMAndDoesNotShowTablesForM() async throws {
        var progress: [PullProgress] = []
        let lock = NSLock()
        engine.onProgress = { update in
            lock.lock()
            progress.append(update)
            lock.unlock()
        }

        var pull = request()
        pull.tables = ["users"]
        _ = try await engine.run(engine.confirm(pull))

        let showedTables = processes.invocations.contains { command in
            command.tool == .mysql && command.arguments.joined(separator: " ").contains("SHOW TABLES")
        }
        XCTAssertFalse(showedTables)

        let dumpProgress = progress.filter { update in
            update.phase == .dumpingSource && update.tablesTotal > 0
        }
        XCTAssertEqual(dumpProgress.first?.tablesTotal, 1)
        XCTAssertEqual(dumpProgress.last?.tablesReached, 1)
        XCTAssertEqual(dumpProgress.last?.tablesTotal, 1)
    }

    func testBackupDumpReportsTableProgressTheSameWay() async throws {
        var progress: [PullProgress] = []
        let lock = NSLock()
        engine.onProgress = { update in
            lock.lock()
            progress.append(update)
            lock.unlock()
        }

        var pull = request()
        pull.strategy = .backupThenReplace
        _ = try await engine.run(engine.confirm(pull))

        let backupShowTables = processes.invocations.filter { command in
            command.tool == .mysql && command.arguments.joined(separator: " ").contains("SHOW TABLES")
        }
        XCTAssertEqual(backupShowTables.count, 2)

        let backupProgress = progress.filter { update in
            update.phase == .creatingBackup && update.tablesTotal > 0
        }
        XCTAssertEqual(backupProgress.first?.tablesTotal, 2)
        XCTAssertEqual(backupProgress.last?.tablesReached, 2)
        XCTAssertEqual(backupProgress.last?.tablesTotal, 2)
    }

    func testBackupThenReplaceReportsDumpBackupImportThenSucceeded() async throws {
        var phases: [PullPhase] = []
        let lock = NSLock()
        engine.onPhase = { phase in
            lock.lock()
            phases.append(phase)
            lock.unlock()
        }

        var pull = request()
        pull.strategy = .backupThenReplace
        let summary = engine.confirm(pull)
        _ = try await engine.run(summary)

        XCTAssertEqual(
            phases,
            [.dumpingSource, .creatingBackup, .importingDestination, .succeeded]
        )
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

        XCTAssertEqual(processes.invocations.filter { $0.tool == .mysqldump }.count, 1)
        XCTAssertTrue(processes.dumpFileWasCompleteBeforeImport)
        XCTAssertFalse(processes.didSendDropDatabase)

        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "orders", "scratch_notes"])

        let dump = processes.invocations.first { $0.tool == .mysqldump }!
        XCTAssertTrue(dump.arguments.contains("--add-drop-table"))
        XCTAssertEqual(dump.environment["MYSQL_PWD"], "src-secret")
        XCTAssertFalse(dump.arguments.contains("src-secret"))

        let mysql = processes.invocations.last { $0.tool == .mysql && $0.inputPath != nil }!
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

        XCTAssertTrue(processes.invocations.contains { $0.tool == .mysqldump })

        let drop = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.joined(separator: " ").contains("DROP DATABASE")
        }!
        XCTAssertTrue(drop.arguments.contains("-e"))
        XCTAssertNil(drop.inputPath)

        let create = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.joined(separator: " ").contains("CREATE DATABASE")
        }!
        XCTAssertTrue(create.arguments.contains("-e"))
        XCTAssertNil(create.inputPath)

        let dump = processes.invocations.first { $0.tool == .mysqldump }!
        let mysql = processes.invocations.last { $0.tool == .mysql && $0.inputPath != nil }!
        XCTAssertEqual(mysql.inputPath, dump.outputPath)
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
        } catch PullError.dumpFailed(_) {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(processes.invocations.filter { $0.tool == .mysqldump }.count, 1)
        XCTAssertFalse(processes.invocations.contains { $0.tool == .mysql && $0.inputPath != nil })
        XCTAssertEqual(processes.tablesByDatabase["local_shop"], ["users", "scratch_notes"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
        XCTAssertEqual(history.entries[0].source, "Prod / shop")
        XCTAssertEqual(history.entries[0].destination, "Localhost / local_shop")
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testSSHTunnelsAreClosedWhenDumpFails() async {
        var pull = request()
        pull.sourceConnection.usesSSH = true
        pull.sourceConnection.sshHost = "bastion.example"
        pull.sourceConnection.sshUser = "jump"
        processes.failDump = true

        do {
            _ = try await engine.run(engine.confirm(pull))
            XCTFail("expected dump failure")
        } catch PullError.dumpFailed(_) {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(processes.invocations.filter { $0.tool == .mysqldump }.count, 1)
        XCTAssertEqual(tunnels.openedFor.count, 1)
        XCTAssertEqual(tunnels.closeCount, 1)
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

        let dump = processes.invocations.first { $0.tool == .mysqldump }!
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

        let dump = processes.invocations.first { $0.tool == .mysqldump }!
        XCTAssertTrue(dump.arguments.contains("127.0.0.1"))
        XCTAssertTrue(dump.arguments.contains("61000"))
        XCTAssertFalse(dump.arguments.contains("prod.example"))
        XCTAssertEqual(tunnels.closeCount, 1)
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
        XCTAssertEqual(tunnels.closeCount, 1)
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
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testDirectConnectionStillUsesMySQLHostAndPort() async throws {
        _ = try await engine.run(engine.confirm(request()))

        let dump = processes.invocations.first { $0.tool == .mysqldump }!
        XCTAssertTrue(dump.arguments.contains("prod.example"))
        XCTAssertTrue(dump.arguments.contains("3306"))
        XCTAssertTrue(tunnels.openedFor.isEmpty)
    }

    func testSSHPrivateKeyConnectionOpensTunnelWithKeyPath() async throws {
        var pull = request()
        pull.sourceConnection.usesSSH = true
        pull.sourceConnection.sshHost = "bastion.example"
        pull.sourceConnection.sshUser = "jump"
        pull.sourceConnection.sshAuthMethod = .privateKey
        pull.sourceConnection.sshKeyPath = "/Users/me/keys/prod.pem"

        _ = try await engine.run(engine.confirm(pull))

        XCTAssertEqual(tunnels.openedFor.count, 1)
        XCTAssertEqual(tunnels.openedFor[0].sshAuthMethod, .privateKey)
        XCTAssertEqual(tunnels.openedFor[0].sshKeyPath, "/Users/me/keys/prod.pem")
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testEmptySettingsUsePathClientNames() async throws {
        settings.save(.usingPath)

        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        XCTAssertEqual(processes.invocations.first { $0.tool == .mysqldump }?.executable, "mysqldump")
        XCTAssertEqual(processes.invocations.last { $0.tool == .mysql }?.executable, "mysql")
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

        XCTAssertEqual(processes.invocations.first { $0.tool == .mysqldump }?.executable, "/opt/homebrew/bin/mysqldump")
        XCTAssertEqual(processes.invocations.last { $0.tool == .mysql }?.executable, "/opt/homebrew/bin/mysql")
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

    func testPullAppendAlsoCapsHistoryAt100() async throws {
        for n in 1...100 {
            history.append(
                HistoryEntry(
                    id: UUID(),
                    when: Date(timeIntervalSince1970: TimeInterval(n)),
                    source: "old / db",
                    destination: "old / dest",
                    succeeded: true
                )
            )
        }

        let summary = engine.confirm(request())
        _ = try await engine.run(summary)

        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.entries.first?.source, "old / db")
        XCTAssertEqual(history.entries.first?.when, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(history.entries.last?.source, "Prod / shop")
    }

    func testSuccessfulPullWithRecipeIdStillRecordsHistoryOnly() async throws {
        let recipeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var pull = request()
        pull.recipeId = recipeId

        _ = try await engine.run(engine.confirm(pull))

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, true)
        XCTAssertEqual(history.entries[0].source, "Prod / shop")
    }

    func testFailedPullWithRecipeIdStillRecordsFailedHistoryOnly() async {
        let recipeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var pull = request()
        pull.recipeId = recipeId
        processes.failDump = true

        do {
            _ = try await engine.run(engine.confirm(pull))
            XCTFail("expected dump failure")
        } catch PullError.dumpFailed(_) {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].succeeded, false)
    }

    func testListDatabasesRunsShowDatabasesWithSecretsAndClosesTunnel() async throws {
        processes.tablesByDatabase["mysql"] = []
        processes.tablesByDatabase["information_schema"] = []
        var connection = source
        connection.usesSSH = true
        connection.sshHost = "bastion.example"
        connection.sshUser = "jump"

        let names = try await engine.listDatabases(on: connection)

        XCTAssertEqual(names, ["information_schema", "local_shop", "mysql", "shop"])
        XCTAssertTrue(history.entries.isEmpty)

        let listing = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.contains("SHOW DATABASES")
        }
        XCTAssertEqual(listing?.executable, "mysql")
        XCTAssertEqual(listing?.environment["MYSQL_PWD"], "src-secret")
        XCTAssertEqual(tunnels.openedFor, [connection])
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListDatabasesUsesConfiguredMysqlPath() async throws {
        settings.save(
            ClientSettings(
                mysqldumpPath: "/opt/homebrew/bin/mysqldump",
                mysqlPath: "/opt/homebrew/bin/mysql"
            )
        )

        _ = try await engine.listDatabases(on: source)

        let listing = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.contains("SHOW DATABASES")
        }
        XCTAssertEqual(listing?.executable, "/opt/homebrew/bin/mysql")
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListDatabasesFailureClosesTunnelAndDoesNotWriteHistory() async {
        processes.failShowDatabases = true
        var connection = source
        connection.usesSSH = true
        connection.sshHost = "bastion.example"
        connection.sshUser = "jump"

        do {
            _ = try await engine.listDatabases(on: connection)
            XCTFail("expected listing failure")
        } catch PullError.listingFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(tunnels.openedFor.count, 1)
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListDatabasesIsRefusedWhileAPullIsRunning() async throws {
        processes.holdDump = true
        let summary = engine.confirm(request())
        let first = Task {
            try await engine.run(summary)
        }
        await processes.waitUntilDumpIsHeld()
        let invocationsBeforeListing = processes.invocations.count

        do {
            _ = try await engine.listDatabases(on: source)
            XCTFail("listing should be refused")
        } catch PullError.alreadyRunning {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(processes.invocations.count, invocationsBeforeListing)
        XCTAssertTrue(history.entries.isEmpty)

        processes.releaseDump()
        _ = try await first.value
    }

    func testListTablesRunsShowTablesWithSecretsAndClosesTunnel() async throws {
        processes.tablesByDatabase["shop"] = ["users", "orders", "active_users"]
        var connection = source
        connection.usesSSH = true
        connection.sshHost = "bastion.example"
        connection.sshUser = "jump"

        let names = try await engine.listTables(on: connection, database: "shop")

        XCTAssertEqual(names, ["active_users", "orders", "users"])
        XCTAssertTrue(history.entries.isEmpty)

        let listing = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.contains("SHOW TABLES")
        }
        XCTAssertEqual(listing?.executable, "mysql")
        XCTAssertEqual(listing?.environment["MYSQL_PWD"], "src-secret")
        XCTAssertTrue(listing?.arguments.contains("shop") == true)
        XCTAssertEqual(tunnels.openedFor, [connection])
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListTablesUsesConfiguredMysqlPath() async throws {
        settings.save(
            ClientSettings(
                mysqldumpPath: "/opt/homebrew/bin/mysqldump",
                mysqlPath: "/opt/homebrew/bin/mysql"
            )
        )

        _ = try await engine.listTables(on: source, database: "shop")

        let listing = processes.invocations.first { command in
            command.tool == .mysql && command.arguments.contains("SHOW TABLES")
        }
        XCTAssertEqual(listing?.executable, "/opt/homebrew/bin/mysql")
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListTablesFailureClosesTunnelAndDoesNotWriteHistory() async {
        processes.failShowTables = true
        var connection = source
        connection.usesSSH = true
        connection.sshHost = "bastion.example"
        connection.sshUser = "jump"

        do {
            _ = try await engine.listTables(on: connection, database: "shop")
            XCTFail("expected listing failure")
        } catch PullError.listingFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(tunnels.openedFor.count, 1)
        XCTAssertEqual(tunnels.closeCount, 1)
    }

    func testListTablesIsRefusedWhileAPullIsRunning() async throws {
        processes.holdDump = true
        let summary = engine.confirm(request())
        let first = Task {
            try await engine.run(summary)
        }
        await processes.waitUntilDumpIsHeld()
        let invocationsBeforeListing = processes.invocations.count

        do {
            _ = try await engine.listTables(on: source, database: "shop")
            XCTFail("listing should be refused")
        } catch PullError.alreadyRunning {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }

        XCTAssertEqual(processes.invocations.count, invocationsBeforeListing)
        XCTAssertTrue(history.entries.isEmpty)

        processes.releaseDump()
        _ = try await first.value
    }

    func testSystemDatabasesStayHiddenUnlessShown() {
        let names = ["shop", "mysql", "information_schema", "performance_schema", "sys", "local_shop"]

        XCTAssertEqual(
            SystemDatabases.visible(names, showSystem: false),
            ["shop", "local_shop"]
        )
        XCTAssertEqual(SystemDatabases.visible(names, showSystem: true), names)
    }

    func testListingSequenceIsSourceThenDestination() {
        let ordered = DatabaseListingSequence.ordered(source: source, destination: destination)

        XCTAssertEqual(ordered.map(\.id), [source.id, destination.id])
    }

    func testListingSequenceDoesNotListTheSameConnectionTwice() {
        let ordered = DatabaseListingSequence.ordered(source: source, destination: source)

        XCTAssertEqual(ordered.map(\.id), [source.id])
    }

    func testDatabasePickerKeepsAMissingNameSelectableAndMarkedAbsent() {
        let options = DatabasePickerOptions.menu(
            liveNames: ["shop", "mysql"],
            selected: "gone",
            showSystem: false
        )

        XCTAssertEqual(options.map(\.id), ["", "shop", "gone"])
        XCTAssertEqual(options.map(\.title), ["Choose a Database", "shop", "gone (absent)"])
    }

    func testTableChecklistKeepsMissingRecipeNamesCheckedAndMarkedAbsent() {
        let options = TablePickerOptions.checklist(
            liveNames: ["users", "orders"],
            keptNames: ["users", "gone"]
        )

        XCTAssertEqual(options.map(\.id), ["users", "orders", "gone"])
        XCTAssertEqual(options.map(\.title), ["users", "orders", "gone (absent)"])
    }

    func testStartDumpNeedsADestinationDatabaseWhenStrategyUsesAnExistingOne() {
        XCTAssertFalse(
            PullForm.canStartDump(
                sourceDatabase: "shop",
                strategy: .replace,
                destinationDatabase: "",
                newDatabaseName: "shop_fresh"
            )
        )
        XCTAssertTrue(
            PullForm.canStartDump(
                sourceDatabase: "shop",
                strategy: .replace,
                destinationDatabase: "local_shop",
                newDatabaseName: ""
            )
        )
        XCTAssertTrue(
            PullForm.canStartDump(
                sourceDatabase: "shop",
                strategy: .createNew,
                destinationDatabase: "",
                newDatabaseName: "shop_fresh"
            )
        )
        XCTAssertFalse(
            PullForm.canStartDump(
                sourceDatabase: "shop",
                strategy: .createNew,
                destinationDatabase: "local_shop",
                newDatabaseName: ""
            )
        )
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
    func testDuplicatedConnectionGetsNewIdCopySuffixAndSameReachabilityFields() {
        let original = Connection(
            id: UUID(),
            name: "Prod",
            host: "prod.example",
            port: 3307,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .privateKey,
            sshKeyPath: "/Users/me/keys/prod.pem"
        )

        let copy = original.duplicated()

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "Prod (copy)")
        XCTAssertEqual(copy.host, original.host)
        XCTAssertEqual(copy.port, original.port)
        XCTAssertEqual(copy.user, original.user)
        XCTAssertEqual(copy.usesSSH, original.usesSSH)
        XCTAssertEqual(copy.sshHost, original.sshHost)
        XCTAssertEqual(copy.sshPort, original.sshPort)
        XCTAssertEqual(copy.sshUser, original.sshUser)
        XCTAssertEqual(copy.sshAuthMethod, original.sshAuthMethod)
        XCTAssertEqual(copy.sshKeyPath, original.sshKeyPath)
    }

    func testDuplicatingAConnectionAppendsCopyWithSecretsAndLeavesRecipesAndHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let disk = DiskStore(folder: folder)
        let history = DiskHistoryStore(disk: disk)

        let other = Connection(id: UUID(), name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")
        let source = Connection(
            id: UUID(),
            name: "Prod",
            host: "prod.example",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion.example",
            sshPort: 22,
            sshUser: "jump",
            sshAuthMethod: .password
        )
        disk.saveConnection(other)
        disk.saveConnection(source)
        secrets.setPassword("prod-pass", forConnectionId: source.id)
        secrets.setSSHPassword("ssh-pass", forConnectionId: source.id)
        secrets.setPassword("local-pass", forConnectionId: other.id)

        let recipe = Recipe(
            id: UUID(),
            title: "Prod daily",
            sourceConnectionId: source.id,
            sourceDatabase: "shop",
            destinationConnectionId: other.id,
            destinationDatabase: "local_shop",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
        disk.saveRecipe(recipe)
        history.append(
            HistoryEntry(
                id: UUID(),
                when: Date(timeIntervalSince1970: 1),
                source: "Prod / shop",
                destination: "Localhost / local_shop",
                succeeded: true
            )
        )

        let copy = try XCTUnwrap(disk.duplicateConnection(id: source.id, secrets: secrets))

        XCTAssertEqual(copy.name, "Prod (copy)")
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(disk.loadConnections().map(\.id), [other.id, source.id, copy.id])
        XCTAssertEqual(secrets.password(forConnectionId: copy.id), "prod-pass")
        XCTAssertEqual(secrets.sshPassword(forConnectionId: copy.id), "ssh-pass")
        XCTAssertEqual(secrets.password(forConnectionId: source.id), "prod-pass")
        XCTAssertEqual(secrets.sshPassword(forConnectionId: source.id), "ssh-pass")
        XCTAssertEqual(disk.loadRecipes(), [recipe])
        XCTAssertEqual(history.entries.count, 1)

        disk.deleteConnection(id: source.id, secrets: secrets)
        XCTAssertEqual(disk.loadConnections().map(\.id), [other.id, copy.id])
        XCTAssertEqual(secrets.password(forConnectionId: copy.id), "prod-pass")
        XCTAssertEqual(secrets.sshPassword(forConnectionId: copy.id), "ssh-pass")
        XCTAssertNil(secrets.password(forConnectionId: source.id))
    }

    func testDuplicatingPrivateKeyConnectionCopiesSSHPassphrase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let disk = DiskStore(folder: folder)

        let source = Connection(
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
        disk.saveConnection(source)
        secrets.setPassword("mysql-secret", forConnectionId: source.id)
        secrets.setSSHPassphrase("pem-phrase", forConnectionId: source.id)

        let copy = try XCTUnwrap(disk.duplicateConnection(id: source.id, secrets: secrets))

        XCTAssertEqual(copy.sshAuthMethod, .privateKey)
        XCTAssertEqual(copy.sshKeyPath, "/Users/me/keys/prod.pem")
        XCTAssertEqual(secrets.password(forConnectionId: copy.id), "mysql-secret")
        XCTAssertEqual(secrets.sshPassphrase(forConnectionId: copy.id), "pem-phrase")
        XCTAssertEqual(secrets.sshPassphrase(forConnectionId: source.id), "pem-phrase")
    }

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

    func testDeletingAConnectionRemovesItSecretsAndSourceRecipesButLeavesHistoryAndDestinationRecipes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let disk = DiskStore(folder: folder)
        let history = DiskHistoryStore(disk: disk)

        let source = Connection(id: UUID(), name: "Prod", host: "prod.example", port: 3306, user: "dump")
        let other = Connection(id: UUID(), name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")
        disk.saveConnection(source)
        disk.saveConnection(other)
        secrets.setPassword("prod-pass", forConnectionId: source.id)
        secrets.setSSHPassword("ssh-pass", forConnectionId: source.id)
        secrets.setSSHPassphrase("key-phrase", forConnectionId: source.id)
        secrets.setPassword("local-pass", forConnectionId: other.id)

        let sourceRecipe = Recipe(
            id: UUID(),
            title: "Prod daily",
            sourceConnectionId: source.id,
            sourceDatabase: "shop",
            destinationConnectionId: other.id,
            destinationDatabase: "local_shop",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
        let destinationOnlyRecipe = Recipe(
            id: UUID(),
            title: "Local daily",
            sourceConnectionId: other.id,
            sourceDatabase: "local_shop",
            destinationConnectionId: source.id,
            destinationDatabase: "shop_copy",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
        disk.saveRecipe(sourceRecipe)
        disk.saveRecipe(destinationOnlyRecipe)

        let historyRow = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1_000_000),
            source: "Prod / shop",
            destination: "Localhost / local_shop",
            succeeded: true
        )
        history.append(historyRow)

        disk.deleteConnection(id: source.id, secrets: secrets)

        XCTAssertEqual(disk.loadConnections().map(\.id), [other.id])
        XCTAssertNil(secrets.password(forConnectionId: source.id))
        XCTAssertNil(secrets.sshPassword(forConnectionId: source.id))
        XCTAssertNil(secrets.sshPassphrase(forConnectionId: source.id))
        XCTAssertEqual(secrets.password(forConnectionId: other.id), "local-pass")
        XCTAssertEqual(disk.loadRecipes(), [destinationOnlyRecipe])
        XCTAssertEqual(history.entries, [historyRow])
        XCTAssertEqual(disk.loadHistory(), [historyRow])
    }

    func testSavedConnectionOrderIsKeptAndNewConnectionIsAppended() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = DiskStore(folder: folder)

        let first = Connection(id: UUID(), name: "Prod", host: "prod.example", port: 3306, user: "dump")
        let second = Connection(id: UUID(), name: "Staging", host: "staging.example", port: 3306, user: "dump")
        let third = Connection(id: UUID(), name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")
        store.saveConnection(first)
        store.saveConnection(second)
        store.saveConnection(third)

        store.saveConnections([third, first, second])
        XCTAssertEqual(store.loadConnections().map(\.id), [third.id, first.id, second.id])

        let appended = Connection(id: UUID(), name: "New box", host: "new.example", port: 3306, user: "dump")
        store.saveConnection(appended)
        XCTAssertEqual(store.loadConnections().map(\.id), [third.id, first.id, second.id, appended.id])
    }

    func testUpdatingConnectionKeepsPasswordWhenEditPasswordIsBlank() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let store = DiskStore(folder: folder)

        let original = Connection(
            id: UUID(),
            name: "Prod",
            host: "prod.example",
            port: 3306,
            user: "dump"
        )
        store.saveConnection(original)
        secrets.setPassword("hunter2", forConnectionId: original.id)

        let edited = Connection(
            id: original.id,
            name: "Prod renamed",
            host: "prod-new.example",
            port: 3307,
            user: "reader"
        )
        store.updateConnection(
            edited,
            secrets: secrets,
            password: "",
            sshPassword: "",
            sshPassphrase: ""
        )

        XCTAssertEqual(store.loadConnections(), [edited])
        XCTAssertEqual(secrets.password(forConnectionId: original.id), "hunter2")
    }

    func testUpdatingConnectionReplacesPasswordWhenEditPasswordIsSet() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let store = DiskStore(folder: folder)

        let original = Connection(
            id: UUID(),
            name: "Prod",
            host: "prod.example",
            port: 3306,
            user: "dump"
        )
        store.saveConnection(original)
        secrets.setPassword("hunter2", forConnectionId: original.id)

        let edited = Connection(
            id: original.id,
            name: "Prod",
            host: "prod.example",
            port: 3306,
            user: "dump"
        )
        store.updateConnection(
            edited,
            secrets: secrets,
            password: "new-secret",
            sshPassword: "",
            sshPassphrase: ""
        )

        XCTAssertEqual(store.loadConnections(), [edited])
        XCTAssertEqual(secrets.password(forConnectionId: original.id), "new-secret")
    }

    func testUpdatingSSHConnectionKeepsOrReplacesSecretsByBlankOrFilledFields() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let secrets = MemorySecretStore()
        let store = DiskStore(folder: folder)

        let original = Connection(
            id: UUID(),
            name: "Prod SSH",
            host: "10.0.0.8",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .password,
            sshKeyPath: ""
        )
        store.saveConnection(original)
        secrets.setPassword("mysql-secret", forConnectionId: original.id)
        secrets.setSSHPassword("ssh-secret", forConnectionId: original.id)

        let hostOnly = Connection(
            id: original.id,
            name: "Prod SSH",
            host: "10.0.0.9",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion2.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .password,
            sshKeyPath: ""
        )
        store.updateConnection(
            hostOnly,
            secrets: secrets,
            password: "",
            sshPassword: "",
            sshPassphrase: ""
        )
        XCTAssertEqual(secrets.password(forConnectionId: original.id), "mysql-secret")
        XCTAssertEqual(secrets.sshPassword(forConnectionId: original.id), "ssh-secret")

        let withNewSSHPassword = Connection(
            id: original.id,
            name: "Prod SSH",
            host: "10.0.0.9",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion2.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .password,
            sshKeyPath: ""
        )
        store.updateConnection(
            withNewSSHPassword,
            secrets: secrets,
            password: "",
            sshPassword: "ssh-new",
            sshPassphrase: ""
        )
        XCTAssertEqual(secrets.password(forConnectionId: original.id), "mysql-secret")
        XCTAssertEqual(secrets.sshPassword(forConnectionId: original.id), "ssh-new")

        let keyAuth = Connection(
            id: original.id,
            name: "Prod SSH",
            host: "10.0.0.9",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion2.example",
            sshPort: 2222,
            sshUser: "jump",
            sshAuthMethod: .privateKey,
            sshKeyPath: "/Users/me/keys/prod.pem"
        )
        secrets.setSSHPassphrase("old-phrase", forConnectionId: original.id)
        store.updateConnection(
            keyAuth,
            secrets: secrets,
            password: "",
            sshPassword: "",
            sshPassphrase: ""
        )
        XCTAssertEqual(secrets.sshPassphrase(forConnectionId: original.id), "old-phrase")

        store.updateConnection(
            keyAuth,
            secrets: secrets,
            password: "",
            sshPassword: "",
            sshPassphrase: "new-phrase"
        )
        XCTAssertEqual(secrets.sshPassphrase(forConnectionId: original.id), "new-phrase")
    }
}

final class RecipeStoreTests: XCTestCase {
    private let sourceId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let otherSourceId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let destId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func dailyRecipe() -> Recipe {
        Recipe(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Welcome daily",
            sourceConnectionId: sourceId,
            sourceDatabase: "shop",
            destinationConnectionId: destId,
            destinationDatabase: "local_shop",
            strategy: .backupThenReplace,
            replaceMode: .importInPlace,
            tables: []
        )
    }

    func testSavedRecipeRoundTripsWithoutBeingChangedByAPull() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)

        let recipe = dailyRecipe()
        disk.saveRecipe(recipe)

        let secrets = MemorySecretStore()
        let processes = FakeProcessRunner()
        processes.tablesByDatabase["shop"] = ["users"]
        processes.tablesByDatabase["other_shop"] = []
        secrets.setPassword("src", forConnectionId: sourceId)
        secrets.setPassword("dst", forConnectionId: destId)

        let source = Connection(id: sourceId, name: "Prod", host: "prod.example", port: 3306, user: "dump")
        let destination = Connection(id: destId, name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")

        var pull = recipe.pullRequest(source: source, destination: destination)
        pull.destinationDatabase = "other_shop"
        pull.strategy = .replace
        pull.replaceMode = .dropDatabase

        let history = MemoryHistoryStore()
        let engine = PullEngine(
            secrets: secrets,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000_000)),
            processes: processes,
            history: history,
            tunnels: FakeSSHTunnel(),
            settings: MemorySettingsStore(),
            paths: FakePathChecker()
        )
        _ = try await engine.run(engine.confirm(pull))

        let loaded = disk.loadRecipes()
        XCTAssertEqual(loaded, [recipe])
        XCTAssertEqual(loaded[0].destinationDatabase, "local_shop")
        XCTAssertEqual(loaded[0].strategy, .backupThenReplace)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertNil(Mirror(reflecting: history.entries[0]).children.first { $0.label == "request" })
    }

    func testSaveWritesTheCurrentFormIntoTheRecipe() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)

        var recipe = dailyRecipe()
        disk.saveRecipe(recipe)

        recipe.destinationDatabase = "welcome_test"
        recipe.strategy = .replace
        recipe.replaceMode = .dropDatabase
        recipe.tables = ["users", "orders"]
        disk.saveRecipe(recipe)

        let loaded = disk.loadRecipes()
        XCTAssertEqual(loaded[0].destinationDatabase, "welcome_test")
        XCTAssertEqual(loaded[0].strategy, .replace)
        XCTAssertEqual(loaded[0].replaceMode, .dropDatabase)
        XCTAssertEqual(loaded[0].tables, ["users", "orders"])
    }

    func testPickerOnlyListsRecipesForTheSidebarSource() {
        let daily = dailyRecipe()
        let other = Recipe(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Voilà daily",
            sourceConnectionId: otherSourceId,
            sourceDatabase: "voila",
            destinationConnectionId: destId,
            destinationDatabase: "voila",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )

        let listed = Recipe.forSource(connectionId: sourceId, in: [daily, other])
        XCTAssertEqual(listed.map(\.title), ["Welcome daily"])
    }

    func testPullWithRecipeIdDoesNotPersistLastRecipesOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)
        let recipe = dailyRecipe()
        var recipeForPull = recipe
        recipeForPull.strategy = .replace
        disk.saveRecipe(recipe)

        let secrets = MemorySecretStore()
        let processes = FakeProcessRunner()
        processes.tablesByDatabase["shop"] = ["users"]
        processes.tablesByDatabase["local_shop"] = []
        secrets.setPassword("src", forConnectionId: sourceId)
        secrets.setPassword("dst", forConnectionId: destId)

        let source = Connection(id: sourceId, name: "Prod", host: "prod.example", port: 3306, user: "dump")
        let destination = Connection(id: destId, name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")

        let engine = PullEngine(
            secrets: secrets,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000_000)),
            processes: processes,
            history: MemoryHistoryStore(),
            tunnels: FakeSSHTunnel(),
            settings: MemorySettingsStore(),
            paths: FakePathChecker()
        )

        let recipePull = recipeForPull.pullRequest(source: source, destination: destination)
        XCTAssertEqual(recipePull.recipeId, recipe.id)
        _ = try await engine.run(engine.confirm(recipePull))

        let lastRecipesPath = folder.appendingPathComponent("last-recipes.json").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: lastRecipesPath))
        XCTAssertEqual(disk.loadRecipes(), [recipe])
    }

    func testEmptyTablesMeansEntireDatabaseAndNamedListIsSelectedTables() {
        let source = Connection(id: sourceId, name: "Prod", host: "prod.example", port: 3306, user: "dump")
        let destination = Connection(id: destId, name: "Localhost", host: "127.0.0.1", port: 3306, user: "root")

        let whole = dailyRecipe().pullRequest(source: source, destination: destination)
        XCTAssertEqual(whole.tables, [])

        var subset = dailyRecipe()
        subset.tables = ["users"]
        XCTAssertEqual(subset.pullRequest(source: source, destination: destination).tables, ["users"])
    }

    func testDuplicateKeepsACopyWithSuffixAndDeleteRemovesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)

        let recipe = dailyRecipe()
        disk.saveRecipe(recipe)

        let copy = recipe.duplicated()
        XCTAssertEqual(copy.title, "Welcome daily (copy)")
        XCTAssertNotEqual(copy.id, recipe.id)
        XCTAssertEqual(copy.sourceDatabase, recipe.sourceDatabase)
        disk.saveRecipe(copy)
        XCTAssertEqual(disk.loadRecipes().count, 2)

        disk.deleteRecipe(id: copy.id)
        XCTAssertEqual(disk.loadRecipes(), [recipe])
    }
}

final class HistoryDisplayTests: XCTestCase {
    func testDefaultOrderIsWhenDescending() {
        let older = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1),
            source: "Prod / shop",
            destination: "Localhost / local_shop",
            succeeded: true
        )
        let newer = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 2),
            source: "Staging / shop",
            destination: "Localhost / local_shop",
            succeeded: false
        )

        let displayed = HistoryDisplay.sorted(
            [older, newer],
            by: HistoryDisplay.defaultSortOrder
        )

        XCTAssertEqual(displayed.map(\.when), [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 1)
        ])
    }

    func testSortedUsesThePassedSortOrderNotOnlyTheDefault() {
        let beta = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1),
            source: "Beta / shop",
            destination: "Localhost / a",
            succeeded: true
        )
        let alpha = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 2),
            source: "Alpha / shop",
            destination: "Localhost / b",
            succeeded: false
        )

        let bySource = HistoryDisplay.sorted(
            [beta, alpha],
            by: [KeyPathComparator(\HistoryEntry.source, order: .forward)]
        )

        XCTAssertEqual(bySource.map(\.source), ["Alpha / shop", "Beta / shop"])
    }

    func testSortBySourceAscending() {
        let beta = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1),
            source: "Beta / shop",
            destination: "Localhost / a",
            succeeded: true
        )
        let alpha = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 2),
            source: "Alpha / shop",
            destination: "Localhost / b",
            succeeded: false
        )

        let displayed = [beta, alpha].sorted(
            using: [KeyPathComparator(\HistoryEntry.source, order: .forward)]
        )

        XCTAssertEqual(displayed.map(\.source), ["Alpha / shop", "Beta / shop"])
    }

    func testSortByDestinationAscending() {
        let second = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1),
            source: "Prod / shop",
            destination: "Localhost / b",
            succeeded: true
        )
        let first = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 2),
            source: "Prod / shop",
            destination: "Localhost / a",
            succeeded: false
        )

        let displayed = [second, first].sorted(
            using: [KeyPathComparator(\HistoryEntry.destination, order: .forward)]
        )

        XCTAssertEqual(displayed.map(\.destination), ["Localhost / a", "Localhost / b"])
    }

    func testSortByResultAscendingPutsFailedBeforeOk() {
        let ok = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 1),
            source: "Prod / shop",
            destination: "Localhost / local_shop",
            succeeded: true
        )
        let failed = HistoryEntry(
            id: UUID(),
            when: Date(timeIntervalSince1970: 2),
            source: "Prod / shop",
            destination: "Localhost / local_shop",
            succeeded: false
        )

        let displayed = [ok, failed].sorted(
            using: [KeyPathComparator(\HistoryEntry.resultLabel, order: .forward)]
        )

        XCTAssertEqual(displayed.map(\.resultLabel), ["Failed", "OK"])
    }
}

final class HistoryStoreTests: XCTestCase {
    func testHistoryAppendKeepsOnlyTheNewest100Rows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)
        let history = DiskHistoryStore(disk: disk)

        for n in 1...101 {
            history.append(
                HistoryEntry(
                    id: UUID(),
                    when: Date(timeIntervalSince1970: TimeInterval(n)),
                    source: "Prod / shop",
                    destination: "Localhost / local_shop",
                    succeeded: true
                )
            )
        }

        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.entries.first?.when, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(history.entries.last?.when, Date(timeIntervalSince1970: 101))
        XCTAssertEqual(disk.loadHistory().count, 100)
        XCTAssertEqual(disk.loadHistory().first?.when, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(disk.loadHistory().last?.when, Date(timeIntervalSince1970: 101))
    }

    func testClearHistoryEmptiesTheLogAndDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let disk = DiskStore(folder: folder)
        let history = DiskHistoryStore(disk: disk)
        history.append(
            HistoryEntry(
                id: UUID(),
                when: Date(timeIntervalSince1970: 1),
                source: "Prod / shop",
                destination: "Localhost / local_shop",
                succeeded: true
            )
        )

        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(disk.loadHistory().isEmpty)
    }
}

final class AppVersionTests: XCTestCase {
    func testMarketingVersionComesFromShortVersionString() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "2",
            "CFBundleDisplayName": "UmpaDumpa"
        ]

        XCTAssertEqual(AppVersion.marketingVersion(from: info), "1.0.0")
    }

    func testBuildNumberComesFromBundleVersion() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "2"
        ]

        XCTAssertEqual(AppVersion.buildNumber(from: info), "2")
    }

    func testDisplayNamePrefersDisplayNameThenBundleName() {
        XCTAssertEqual(
            AppVersion.displayName(from: [
                "CFBundleDisplayName": "UmpaDumpa",
                "CFBundleName": "umpadumpa"
            ]),
            "UmpaDumpa"
        )
        XCTAssertEqual(
            AppVersion.displayName(from: [
                "CFBundleName": "UmpaDumpa"
            ]),
            "UmpaDumpa"
        )
    }

    func testAboutMenuTitleUsesDisplayName() {
        let info: [String: Any] = ["CFBundleDisplayName": "UmpaDumpa"]

        XCTAssertEqual(AppVersion.aboutMenuTitle(from: info), "About UmpaDumpa")
    }

    func testMissingKeysAreEmptyStringsNotHardCodedVersions() {
        XCTAssertEqual(AppVersion.marketingVersion(from: [:]), "")
        XCTAssertEqual(AppVersion.buildNumber(from: [:]), "")
    }
}
