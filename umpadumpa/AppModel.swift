import Foundation
import SwiftUI

@Observable
final class AppModel {
    private let disk: DiskStore
    private let secrets: SecretStoring
    private let historyStore: HistoryStoring
    let engine: PullEngine

    var connections: [Connection] = []
    var history: [HistoryEntry] = []

    var selectedNav: String = ""
    var sourceDatabase: String = ""
    var destinationConnectionId: UUID?
    var destinationDatabase: String = ""
    var showConfirm = false
    var showNewConnection = false
    var pullError: String?
    var isPulling = false

    var newName = ""
    var newHost = ""
    var newPort = "3306"
    var newUser = ""
    var newPassword = ""

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("umpadumpa", isDirectory: true)
        let disk = DiskStore(folder: folder)
        let secrets: SecretStoring
        #if os(macOS)
        secrets = KeychainSecretStore()
        #else
        secrets = MemorySecretStore()
        #endif
        let historyStore = DiskHistoryStore(disk: disk)
        self.disk = disk
        self.secrets = secrets
        self.historyStore = historyStore
        self.engine = PullEngine(
            secrets: secrets,
            clock: SystemClock(),
            processes: RealProcessRunner(),
            history: historyStore
        )
        self.connections = disk.loadConnections()
        self.history = historyStore.entries
        if let first = connections.first {
            selectedNav = first.id.uuidString
            sourceDatabase = ""
            destinationConnectionId = connections.first { $0.name.lowercased() == "localhost" }?.id ?? first.id
        }
    }

    func refreshHistory() {
        history = historyStore.entries
    }

    var selectedConnection: Connection? {
        connections.first { $0.id.uuidString == selectedNav }
    }

    var destinationConnection: Connection? {
        connections.first { $0.id == destinationConnectionId }
    }

    func addConnection() -> Connection {
        let port = Int(newPort) ?? 3306
        let connection = Connection(
            id: UUID(),
            name: newName,
            host: newHost,
            port: port,
            user: newUser
        )
        disk.saveConnection(connection)
        secrets.setPassword(newPassword, forConnectionId: connection.id)
        connections = disk.loadConnections()
        selectedNav = connection.id.uuidString
        showNewConnection = false
        newName = ""
        newHost = ""
        newPort = "3306"
        newUser = ""
        newPassword = ""
        return connection
    }

    func selectConnection(_ id: String) {
        selectedNav = id
        if let connection = selectedConnection {
            sourceDatabase = ""
            if destinationConnectionId == nil {
                destinationConnectionId = connections.first { $0.name.lowercased() == "localhost" }?.id
            }
        }
    }

    func currentRequest() -> PullRequest? {
        guard let source = selectedConnection,
              let dest = destinationConnection,
              sourceDatabase.isEmpty == false,
              destinationDatabase.isEmpty == false
        else {
            return nil
        }

        return PullRequest(
            sourceConnection: source,
            sourceDatabase: sourceDatabase,
            destinationConnection: dest,
            destinationDatabase: destinationDatabase,
            strategy: .replace,
            replaceMode: .importInPlace,
            tables: []
        )
    }

    func confirmSummary() -> ConfirmSummary? {
        guard let request = currentRequest() else {
            return nil
        }
        return engine.confirm(request)
    }

    func runConfirmedPull() {
        guard let summary = confirmSummary() else {
            return
        }
        showConfirm = false
        isPulling = true
        Task {
            defer { isPulling = false }
            do {
                _ = try await engine.run(summary)
                pullError = nil
                refreshHistory()
            } catch PullError.alreadyRunning {
                pullError = "A Pull is already running."
                refreshHistory()
            } catch PullError.dumpFailed {
                pullError = "Dump failed. Destination was not changed."
                refreshHistory()
            } catch PullError.importFailed {
                pullError = "Import failed."
                refreshHistory()
            } catch {
                pullError = "Pull failed."
                refreshHistory()
            }
        }
    }
}
