import Foundation
import SwiftUI

@Observable
final class AppModel {
    private let disk: DiskStore
    private let secrets: SecretStoring
    private let historyStore: HistoryStoring
    private let settingsStore: SettingsStoring
    let engine: PullEngine

    var connections: [Connection] = []
    var recipes: [Recipe] = []
    var history: [HistoryEntry] = []

    var selectedNav: String = ""
    var sourceDatabase: String = ""
    var destinationConnectionId: UUID?
    var destinationDatabase: String = ""
    var showConfirm = false
    var showNewConnection = false
    var pullError: String?
    var isPulling = false
    var pullPhase: PullPhase = .idle

    var newName = ""
    var newHost = ""
    var newPort = "3306"
    var newUser = ""
    var newPassword = ""
    var newUsesSSH = false
    var newSSHHost = ""
    var newSSHPort = "22"
    var newSSHUser = ""
    var newSSHAuth = SSHAuthMethod.password.rawValue
    var newSSHKeyPath = ""
    var newSSHPassword = ""
    var newSSHPassphrase = ""
    var mysqldumpPath = ""
    var mysqlPath = ""

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
        let settingsStore = DiskSettingsStore(disk: disk)
        self.disk = disk
        self.secrets = secrets
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.engine = PullEngine(
            secrets: secrets,
            clock: SystemClock(),
            processes: RealProcessRunner(),
            history: historyStore,
            tunnels: RealSSHTunnel(secrets: secrets),
            settings: settingsStore,
            paths: FilePathChecker()
        )
        self.engine.onPhase = { [weak self] phase in
            Task { @MainActor in
                self?.pullPhase = phase
            }
        }
        self.connections = disk.loadConnections()
        self.recipes = disk.loadRecipes()
        self.history = historyStore.entries
        let loadedSettings = settingsStore.load()
        self.mysqldumpPath = loadedSettings.mysqldumpPath
        self.mysqlPath = loadedSettings.mysqlPath
        if let first = connections.first {
            selectedNav = first.id.uuidString
            sourceDatabase = ""
            destinationConnectionId = connections.first { $0.name.lowercased() == "localhost" }?.id ?? first.id
        }
    }

    func saveClientSettings() {
        settingsStore.save(
            ClientSettings(
                mysqldumpPath: mysqldumpPath,
                mysqlPath: mysqlPath
            )
        )
    }

    func refreshHistory() {
        history = historyStore.entries
    }

    func saveRecipe(_ recipe: Recipe) {
        disk.saveRecipe(recipe)
        recipes = disk.loadRecipes()
    }

    func deleteRecipe(id: UUID) {
        disk.deleteRecipe(id: id)
        recipes = disk.loadRecipes()
    }

    var selectedConnection: Connection? {
        connections.first { $0.id.uuidString == selectedNav }
    }

    var destinationConnection: Connection? {
        connections.first { $0.id == destinationConnectionId }
    }

    func addConnection() -> Connection {
        let port = Int(newPort) ?? 3306
        let sshPort = Int(newSSHPort) ?? 22
        let auth = SSHAuthMethod(rawValue: newSSHAuth) ?? .password
        let connection = Connection(
            id: UUID(),
            name: newName,
            host: newHost,
            port: port,
            user: newUser,
            usesSSH: newUsesSSH,
            sshHost: newSSHHost,
            sshPort: sshPort,
            sshUser: newSSHUser,
            sshAuthMethod: auth,
            sshKeyPath: newSSHKeyPath
        )
        disk.saveConnection(connection)
        secrets.setPassword(newPassword, forConnectionId: connection.id)
        if newUsesSSH {
            if auth == .password {
                secrets.setSSHPassword(newSSHPassword, forConnectionId: connection.id)
            } else {
                secrets.setSSHPassphrase(newSSHPassphrase, forConnectionId: connection.id)
            }
        }
        connections = disk.loadConnections()
        selectedNav = connection.id.uuidString
        showNewConnection = false
        newName = ""
        newHost = ""
        newPort = "3306"
        newUser = ""
        newPassword = ""
        newUsesSSH = false
        newSSHHost = ""
        newSSHPort = "22"
        newSSHUser = ""
        newSSHAuth = SSHAuthMethod.password.rawValue
        newSSHKeyPath = ""
        newSSHPassword = ""
        newSSHPassphrase = ""
        return connection
    }

    func deleteConnection(id: UUID) {
        disk.deleteConnection(id: id, secrets: secrets)
        connections = disk.loadConnections()
        recipes = disk.loadRecipes()
        if selectedConnection == nil {
            selectedNav = connections.first?.id.uuidString ?? ""
        }
        if destinationConnectionId == id {
            destinationConnectionId = connections.first { $0.name.lowercased() == "localhost" }?.id
                ?? connections.first?.id
        }
    }

    func moveConnections(fromOffsets: IndexSet, toOffset: Int) {
        connections.move(fromOffsets: fromOffsets, toOffset: toOffset)
        disk.saveConnections(connections)
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
            } catch let PullError.dumpFailed(detail) {
                let extra = detail.isEmpty ? "" : " \(detail)"
                pullError = "Dump failed. Destination was not changed.\(extra)"
                refreshHistory()
            } catch PullError.tunnelFailed {
                pullError = "SSH tunnel failed. Destination was not changed."
                refreshHistory()
            } catch PullError.missingClient(.mysqldump) {
                pullError = "mysqldump was not found. Set its path in Settings."
                refreshHistory()
            } catch PullError.missingClient(.mysql) {
                pullError = "mysql was not found. Set its path in Settings."
                refreshHistory()
            } catch PullError.nameAlreadyExists {
                pullError = "That name already exists. The destination was not changed."
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
