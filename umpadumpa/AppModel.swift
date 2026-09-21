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
    var editingConnectionId: UUID?
    var pullError: String?
    var isPulling = false
    var pullPhase: PullPhase = .idle
    var pullProgress = PullProgress(phase: .idle, tablesReached: 0, tablesTotal: 0, dumpFileMegabytes: nil)
    var databaseNamesByConnectionId: [UUID: [String]] = [:]
    var databaseListErrorByConnectionId: [UUID: String] = [:]
    var loadingDatabaseConnectionId: UUID?
    var liveTableNames: [String] = []
    var tableListError: String?
    var isLoadingTables = false
    private var listingChain: Task<Void, Never> = Task {}

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
        self.engine.onProgress = { [weak self] progress in
            Task { @MainActor in
                self?.pullProgress = progress
                self?.pullPhase = progress.phase
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

    func clearHistory() {
        historyStore.clear()
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
        clearConnectionForm()
        return connection
    }

    func beginNewConnection() {
        clearConnectionForm()
        showNewConnection = true
    }

    func beginEditConnection(_ connection: Connection) {
        editingConnectionId = connection.id
        newName = connection.name
        newHost = connection.host
        newPort = String(connection.port)
        newUser = connection.user
        newPassword = ""
        newUsesSSH = connection.usesSSH
        newSSHHost = connection.sshHost
        newSSHPort = String(connection.sshPort)
        newSSHUser = connection.sshUser
        newSSHAuth = connection.sshAuthMethod.rawValue
        newSSHKeyPath = connection.sshKeyPath
        newSSHPassword = ""
        newSSHPassphrase = ""
        showNewConnection = true
    }

    func updateConnectionFromForm() -> Connection? {
        guard let editingConnectionId else {
            return nil
        }
        let port = Int(newPort) ?? 3306
        let sshPort = Int(newSSHPort) ?? 22
        let auth = SSHAuthMethod(rawValue: newSSHAuth) ?? .password
        let connection = Connection(
            id: editingConnectionId,
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
        disk.updateConnection(
            connection,
            secrets: secrets,
            password: newPassword,
            sshPassword: newSSHPassword,
            sshPassphrase: newSSHPassphrase
        )
        connections = disk.loadConnections()
        clearConnectionForm()
        return connection
    }

    func cancelConnectionForm() {
        clearConnectionForm()
    }

    private func clearConnectionForm() {
        showNewConnection = false
        editingConnectionId = nil
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
        if editingConnectionId == id {
            clearConnectionForm()
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

    func loadDatabases(for connection: Connection, force: Bool) {
        enqueueListings(DatabaseListingSequence.ordered(source: connection, destination: nil), force: force)
    }

    func loadSourceThenDestination(source: Connection, destination: Connection?, force: Bool) {
        enqueueListings(
            DatabaseListingSequence.ordered(source: source, destination: destination),
            force: force
        )
    }

    private func enqueueListings(_ connections: [Connection], force: Bool) {
        listingChain = Task { [listingChain] in
            await listingChain.value
            for connection in connections {
                await listDatabasesNow(for: connection, force: force)
            }
        }
    }

    private func listDatabasesNow(for connection: Connection, force: Bool) async {
        if isPulling || engine.isRunning {
            return
        }
        if force == false,
           databaseNamesByConnectionId[connection.id] != nil,
           databaseListErrorByConnectionId[connection.id] == nil {
            return
        }

        await MainActor.run {
            loadingDatabaseConnectionId = connection.id
            databaseListErrorByConnectionId[connection.id] = nil
        }

        do {
            let names = try await engine.listDatabases(on: connection)
            await MainActor.run {
                databaseNamesByConnectionId[connection.id] = names
                databaseListErrorByConnectionId[connection.id] = nil
                if loadingDatabaseConnectionId == connection.id {
                    loadingDatabaseConnectionId = nil
                }
            }
        } catch {
            await MainActor.run {
                if loadingDatabaseConnectionId == connection.id {
                    loadingDatabaseConnectionId = nil
                }
                databaseListErrorByConnectionId[connection.id] = listingErrorMessage(error)
            }
        }
    }

    func loadTables(for connection: Connection, database: String) {
        if database.isEmpty {
            return
        }
        listingChain = Task { [listingChain] in
            await listingChain.value
            await listTablesNow(for: connection, database: database)
        }
    }

    private func listTablesNow(for connection: Connection, database: String) async {
        if isPulling || engine.isRunning {
            await MainActor.run {
                tableListError = "A Pull is already running."
            }
            return
        }

        await MainActor.run {
            isLoadingTables = true
            tableListError = nil
            liveTableNames = []
        }

        do {
            let names = try await engine.listTables(on: connection, database: database)
            await MainActor.run {
                liveTableNames = names
                tableListError = nil
                isLoadingTables = false
            }
        } catch {
            await MainActor.run {
                isLoadingTables = false
                liveTableNames = []
                tableListError = listingErrorMessage(error, forTables: true)
            }
        }
    }

    private func listingErrorMessage(_ error: Error, forTables: Bool = false) -> String {
        if let pullError = error as? PullError {
            if pullError == .alreadyRunning {
                return "A Pull is already running."
            }
            if pullError == .tunnelFailed {
                return "SSH tunnel failed."
            }
            if pullError == .missingClient(.mysql) {
                return "mysql was not found. Set its path in Settings."
            }
            if pullError == .listingFailed {
                return forTables ? "Could not list Tables." : "Could not list Databases."
            }
        }
        return forTables ? "Could not list Tables." : "Could not list Databases."
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
