import XCTest
@testable import umpadumpa

final class WorkspaceTests: XCTestCase {
    func testExportOmitsPasswordsPassphrasesAndHistory() throws {
        let disk = makeDisk()
        let secrets = MemorySecretStore()
        let connection = sampleConnection(name: "Prod")
        disk.saveConnection(connection)
        secrets.setPassword("secret-password", forConnectionId: connection.id)
        secrets.setSSHPassphrase("secret-passphrase", forConnectionId: connection.id)
        disk.saveHistory([
            HistoryEntry(id: UUID(), when: Date(), source: "history-source-marker", destination: "dest", succeeded: true)
        ])
        disk.saveSettings(ClientSettings(mysqldumpPath: "/bin/mysqldump", mysqlPath: "/bin/mysql"))

        let data = try disk.exportWorkspaceFile()
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("secret-password"))
        XCTAssertFalse(text.contains("secret-passphrase"))
        XCTAssertFalse(text.contains("history-source-marker"))

        let file = try JSONDecoder().decode(WorkspaceFile.self, from: data)
        XCTAssertEqual(file.connections, [connection])
        XCTAssertEqual(file.connections.first?.sshKeyPath, connection.sshKeyPath)
        XCTAssertEqual(file.mysqldumpPath, "/bin/mysqldump")
        XCTAssertEqual(file.mysqlPath, "/bin/mysql")
    }

    func testImportReplacesSetKeepsIdsAndDeletesMissingConnectionSecretsAndRecipes() throws {
        let disk = makeDisk()
        let secrets = MemorySecretStore()
        let kept = sampleConnection(name: "Kept")
        let gone = sampleConnection(name: "Gone")
        disk.saveConnections([kept, gone])
        secrets.setPassword("kept-password", forConnectionId: kept.id)
        secrets.setPassword("gone-password", forConnectionId: gone.id)
        let keptRecipe = sampleRecipe(source: kept.id, title: "Keep me")
        let goneRecipe = sampleRecipe(source: gone.id, title: "Drop me")
        disk.saveRecipes([keptRecipe, goneRecipe])
        let history = [
            HistoryEntry(id: UUID(), when: Date(), source: "still-here", destination: "dest", succeeded: true)
        ]
        disk.saveHistory(history)
        disk.saveSettings(ClientSettings(mysqldumpPath: "/old/mysqldump", mysqlPath: "/old/mysql", firstOpenSheetFinished: true))

        let file = WorkspaceFile(
            connections: [kept],
            recipes: [keptRecipe, goneRecipe],
            mysqldumpPath: "",
            mysqlPath: ""
        )
        let data = try JSONEncoder().encode(file)
        try disk.importWorkspaceFile(data, secrets: secrets, pullIsRunning: false)

        XCTAssertEqual(disk.loadConnections().map(\.id), [kept.id])
        XCTAssertEqual(disk.loadRecipes(), [keptRecipe])
        XCTAssertEqual(secrets.password(forConnectionId: kept.id), "kept-password")
        XCTAssertNil(secrets.password(forConnectionId: gone.id))
        XCTAssertEqual(disk.loadHistory(), history)
        let settings = disk.loadSettings()
        XCTAssertEqual(settings.mysqldumpPath, "")
        XCTAssertEqual(settings.mysqlPath, "")
        XCTAssertTrue(settings.firstOpenSheetFinished)
    }

    func testUnreadableFileChangesNothing() throws {
        let disk = makeDisk()
        let secrets = MemorySecretStore()
        let connection = sampleConnection(name: "Prod")
        disk.saveConnection(connection)
        secrets.setPassword("secret-password", forConnectionId: connection.id)
        disk.saveRecipes([sampleRecipe(source: connection.id, title: "Daily")])
        disk.saveSettings(ClientSettings(mysqldumpPath: "/bin/mysqldump", mysqlPath: "/bin/mysql"))

        XCTAssertThrowsError(
            try disk.importWorkspaceFile(Data("not json".utf8), secrets: secrets, pullIsRunning: false)
        ) { error in
            XCTAssertEqual(error as? WorkspaceImportError, .unreadable)
        }

        XCTAssertEqual(disk.loadConnections(), [connection])
        XCTAssertEqual(disk.loadRecipes().count, 1)
        XCTAssertEqual(disk.loadSettings().mysqldumpPath, "/bin/mysqldump")
        XCTAssertEqual(secrets.password(forConnectionId: connection.id), "secret-password")
    }

    func testImportIsRefusedWhileAPullIsRunning() throws {
        let disk = makeDisk()
        let secrets = MemorySecretStore()
        let connection = sampleConnection(name: "Prod")
        disk.saveConnection(connection)
        let file = WorkspaceFile(connections: [], recipes: [], mysqldumpPath: "/other/dump", mysqlPath: "/other/mysql")
        let data = try JSONEncoder().encode(file)

        XCTAssertThrowsError(
            try disk.importWorkspaceFile(data, secrets: secrets, pullIsRunning: true)
        ) { error in
            XCTAssertEqual(error as? WorkspaceImportError, .pullRunning)
        }

        XCTAssertEqual(disk.loadConnections(), [connection])
        XCTAssertEqual(disk.loadSettings().mysqldumpPath, "")
        let exported = try disk.exportWorkspaceFile()
        XCTAssertTrue(String(decoding: exported, as: UTF8.self).contains("Prod"))
    }

    private func makeDisk() -> DiskStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DiskStore(folder: folder)
    }

    private func sampleConnection(name: String) -> Connection {
        Connection(
            id: UUID(),
            name: name,
            host: "db.example",
            port: 3306,
            user: "dump",
            usesSSH: true,
            sshHost: "bastion.example",
            sshPort: 22,
            sshUser: "jump",
            sshAuthMethod: .privateKey,
            sshKeyPath: "/Users/me/.ssh/\(name).pem"
        )
    }

    private func sampleRecipe(source: UUID, title: String) -> Recipe {
        Recipe(
            id: UUID(),
            title: title,
            sourceConnectionId: source,
            sourceDatabase: "app",
            destinationConnectionId: UUID(),
            destinationDatabase: "app",
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
    }
}
