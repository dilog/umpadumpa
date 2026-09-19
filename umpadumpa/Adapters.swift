import Foundation
#if os(macOS)
import Security
#endif

nonisolated final class MemorySecretStore: SecretStoring {
    private var passwords: [UUID: String] = [:]
    private var sshPasswords: [UUID: String] = [:]
    private var sshPassphrases: [UUID: String] = [:]

    func setPassword(_ password: String, forConnectionId id: UUID) {
        passwords[id] = password
    }

    func password(forConnectionId id: UUID) -> String? {
        passwords[id]
    }

    func setSSHPassword(_ password: String, forConnectionId id: UUID) {
        sshPasswords[id] = password
    }

    func sshPassword(forConnectionId id: UUID) -> String? {
        sshPasswords[id]
    }

    func setSSHPassphrase(_ passphrase: String, forConnectionId id: UUID) {
        sshPassphrases[id] = passphrase
    }

    func sshPassphrase(forConnectionId id: UUID) -> String? {
        sshPassphrases[id]
    }

    func deleteSecrets(forConnectionId id: UUID) {
        passwords[id] = nil
        sshPasswords[id] = nil
        sshPassphrases[id] = nil
    }
}

struct FixedClock: Clock {
    var now: Date
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

nonisolated final class MemoryHistoryStore: HistoryStoring {
    private(set) var entries: [HistoryEntry] = []

    func append(_ entry: HistoryEntry) {
        entries.append(entry)
        if entries.count > 100 {
            entries.removeFirst(entries.count - 100)
        }
    }

    func clear() {
        entries = []
    }
}

nonisolated final class MemoryLastRecipeStore: LastRecipeStoring {
    private var ids: [UUID: UUID] = [:]

    nonisolated func record(recipeId: UUID, forSourceConnectionId connectionId: UUID) {
        ids[connectionId] = recipeId
    }

    nonisolated func lastRecipeId(forSourceConnectionId connectionId: UUID) -> UUID? {
        ids[connectionId]
    }
}

nonisolated final class MemorySettingsStore: SettingsStoring {
    private var settings = ClientSettings.usingPath

    func load() -> ClientSettings {
        settings
    }

    func save(_ settings: ClientSettings) {
        self.settings = settings
    }
}

nonisolated final class FakePathChecker: PathChecking {
    var missing: Set<String> = []

    func pathExists(_ path: String) -> Bool {
        missing.contains(path) == false
    }
}

struct FilePathChecker: PathChecking {
    func pathExists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

nonisolated final class DiskStore {
    let folder: URL

    var connectionsFile: URL {
        folder.appendingPathComponent("connections.json")
    }

    var historyFile: URL {
        folder.appendingPathComponent("history.json")
    }

    var settingsFile: URL {
        folder.appendingPathComponent("settings.json")
    }

    var recipesFile: URL {
        folder.appendingPathComponent("recipes.json")
    }

    var lastRecipesFile: URL {
        folder.appendingPathComponent("last-recipes.json")
    }

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func loadConnections() -> [Connection] {
        guard let data = try? Data(contentsOf: connectionsFile) else {
            return []
        }
        return (try? JSONDecoder().decode([Connection].self, from: data)) ?? []
    }

    func saveConnection(_ connection: Connection) {
        var all = loadConnections()
        if let index = all.firstIndex(where: { $0.id == connection.id }) {
            all[index] = connection
        } else {
            all.append(connection)
        }
        saveConnections(all)
    }

    func saveConnections(_ connections: [Connection]) {
        if let data = try? JSONEncoder().encode(connections) {
            try? data.write(to: connectionsFile)
        }
    }

    func deleteConnection(id: UUID, secrets: SecretStoring) {
        var connections = loadConnections()
        connections.removeAll { $0.id == id }
        saveConnections(connections)

        var recipes = loadRecipes()
        recipes.removeAll { $0.sourceConnectionId == id }
        saveRecipes(recipes)

        var lastRecipes = loadLastRecipes()
        lastRecipes.removeValue(forKey: id.uuidString)
        saveLastRecipes(lastRecipes)

        secrets.deleteSecrets(forConnectionId: id)
    }

    func loadHistory() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyFile) else {
            return []
        }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    func saveHistory(_ entries: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: historyFile)
        }
    }

    func loadSettings() -> ClientSettings {
        guard let data = try? Data(contentsOf: settingsFile) else {
            return .usingPath
        }
        return (try? JSONDecoder().decode(ClientSettings.self, from: data)) ?? .usingPath
    }

    func saveSettings(_ settings: ClientSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: settingsFile)
        }
    }

    func loadRecipes() -> [Recipe] {
        guard let data = try? Data(contentsOf: recipesFile) else {
            return []
        }
        return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
    }

    func saveRecipes(_ recipes: [Recipe]) {
        if let data = try? JSONEncoder().encode(recipes) {
            try? data.write(to: recipesFile)
        }
    }

    func saveRecipe(_ recipe: Recipe) {
        var all = loadRecipes()
        if let index = all.firstIndex(where: { $0.id == recipe.id }) {
            all[index] = recipe
        } else {
            all.append(recipe)
        }
        saveRecipes(all)
    }

    func deleteRecipe(id: UUID) {
        var all = loadRecipes()
        all.removeAll { $0.id == id }
        saveRecipes(all)

        var lastRecipes = loadLastRecipes()
        lastRecipes = lastRecipes.filter { $0.value != id.uuidString }
        saveLastRecipes(lastRecipes)
    }

    func loadLastRecipes() -> [String: String] {
        guard let data = try? Data(contentsOf: lastRecipesFile) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func saveLastRecipes(_ lastRecipes: [String: String]) {
        if let data = try? JSONEncoder().encode(lastRecipes) {
            try? data.write(to: lastRecipesFile)
        }
    }

    func lastRecipeId(forSourceConnectionId connectionId: UUID) -> UUID? {
        guard let raw = loadLastRecipes()[connectionId.uuidString] else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    func recordLastRecipe(id: UUID, forSourceConnectionId connectionId: UUID) {
        var lastRecipes = loadLastRecipes()
        lastRecipes[connectionId.uuidString] = id.uuidString
        saveLastRecipes(lastRecipes)
    }
}

nonisolated final class DiskHistoryStore: HistoryStoring {
    private let disk: DiskStore
    private(set) var entries: [HistoryEntry]

    init(disk: DiskStore) {
        self.disk = disk
        self.entries = disk.loadHistory()
    }

    func append(_ entry: HistoryEntry) {
        entries.append(entry)
        if entries.count > 100 {
            entries.removeFirst(entries.count - 100)
        }
        disk.saveHistory(entries)
    }

    func clear() {
        entries = []
        disk.saveHistory(entries)
    }
}

nonisolated final class DiskLastRecipeStore: LastRecipeStoring {
    private let disk: DiskStore

    init(disk: DiskStore) {
        self.disk = disk
    }

    nonisolated func record(recipeId: UUID, forSourceConnectionId connectionId: UUID) {
        disk.recordLastRecipe(id: recipeId, forSourceConnectionId: connectionId)
    }

    nonisolated func lastRecipeId(forSourceConnectionId connectionId: UUID) -> UUID? {
        disk.lastRecipeId(forSourceConnectionId: connectionId)
    }
}

nonisolated final class DiskSettingsStore: SettingsStoring {
    private let disk: DiskStore

    init(disk: DiskStore) {
        self.disk = disk
    }

    func load() -> ClientSettings {
        disk.loadSettings()
    }

    func save(_ settings: ClientSettings) {
        disk.saveSettings(settings)
    }
}

#if os(macOS)
nonisolated final class KeychainSecretStore: SecretStoring {
    private let service = "dev.umpadumpa.connection"
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    func setPassword(_ password: String, forConnectionId id: UUID) {
        setSecret(password, account: id.uuidString)
    }

    func password(forConnectionId id: UUID) -> String? {
        secret(account: id.uuidString)
    }

    func setSSHPassword(_ password: String, forConnectionId id: UUID) {
        setSecret(password, account: id.uuidString + "-ssh-password")
    }

    func sshPassword(forConnectionId id: UUID) -> String? {
        secret(account: id.uuidString + "-ssh-password")
    }

    func setSSHPassphrase(_ passphrase: String, forConnectionId id: UUID) {
        setSecret(passphrase, account: id.uuidString + "-ssh-passphrase")
    }

    func sshPassphrase(forConnectionId id: UUID) -> String? {
        secret(account: id.uuidString + "-ssh-passphrase")
    }

    func deleteSecrets(forConnectionId id: UUID) {
        deleteSecret(account: id.uuidString)
        deleteSecret(account: id.uuidString + "-ssh-password")
        deleteSecret(account: id.uuidString + "-ssh-passphrase")
    }

    private func deleteSecret(account: String) {
        lock.lock()
        cache[account] = nil
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func setSecret(_ value: String, account: String) {
        lock.lock()
        cache[account] = value
        lock.unlock()

        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func secret(account: String) -> String? {
        lock.lock()
        if let cached = cache[account] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        let value = String(data: data, encoding: .utf8)
        if let value {
            lock.lock()
            cache[account] = value
            lock.unlock()
        }
        return value
    }
}
#endif

nonisolated final class FakeSSHTunnel: SSHTunneling {
    var localHost = "127.0.0.1"
    var localPort = 61000
    var failOpen = false
    private(set) var openedFor: [Connection] = []
    private(set) var closeCount = 0

    func openTunnel(for connection: Connection) async throws -> OpenTunnel {
        openedFor.append(connection)
        if failOpen {
            throw PullError.tunnelFailed
        }
        return OpenTunnel(localHost: localHost, localPort: localPort)
    }

    func closeOpenedTunnels() {
        closeCount += 1
    }
}

nonisolated final class FakeProcessRunner: ProcessRunning {
    var tablesByDatabase: [String: Set<String>] = [:]
    private(set) var invocations: [ExternalCommand] = []
    private(set) var dumpFileWasCompleteBeforeImport = false
    private(set) var didSendDropDatabase = false
    private(set) var didSendCreateDatabase = false

    var failDump = false
    var failImport = false
    var failShowDatabases = false
    var failShowTables = false
    var holdDump = false
    private var firstDumpOutputPath: String?

    private var dumpHoldContinuation: CheckedContinuation<Void, Never>?
    private var dumpIsHeldContinuation: CheckedContinuation<Void, Never>?
    private var dumpIsHeld = false

    func waitUntilDumpIsHeld() async {
        if dumpIsHeld {
            return
        }
        await withCheckedContinuation { continuation in
            dumpIsHeldContinuation = continuation
        }
    }

    func releaseDump() {
        dumpHoldContinuation?.resume()
        dumpHoldContinuation = nil
    }

    func run(
        _ command: ExternalCommand,
        onStandardErrorLine: (@Sendable (String) -> Void)?
    ) async throws {
        invocations.append(command)

        if command.tool == .mysqldump {
            if firstDumpOutputPath == nil {
                firstDumpOutputPath = command.outputPath
            }
            if holdDump {
                dumpIsHeld = true
                dumpIsHeldContinuation?.resume()
                dumpIsHeldContinuation = nil
                await withCheckedContinuation { continuation in
                    dumpHoldContinuation = continuation
                }
            }

            if failDump {
                throw PullError.dumpFailed("dump failed")
            }

            let target = dumpTarget(from: command.arguments)
            let allTables = tablesByDatabase[target.database] ?? []
            let tables: [String]
            if target.tables.isEmpty {
                tables = allTables.sorted()
            } else {
                tables = target.tables.filter { allTables.contains($0) }
            }
            var sql = ""
            for table in tables {
                onStandardErrorLine?("-- Retrieving table structure for table \(table)...")
                sql += "DROP TABLE IF EXISTS \(table);\n"
                sql += "CREATE TABLE \(table);\n"
            }
            if let outputPath = command.outputPath {
                try sql.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
            dumpFileWasCompleteBeforeImport = true
            return
        }

        if command.tool == .mysql {
            if failImport && command.inputPath != nil && command.inputPath == firstDumpOutputPath {
                throw PullError.importFailed
            }

            if let eIndex = command.arguments.firstIndex(of: "-e"),
               eIndex + 1 < command.arguments.count {
                let sql = command.arguments[eIndex + 1]

                if sql.contains("SHOW DATABASES") {
                    if failShowDatabases {
                        throw PullError.listingFailed
                    }
                    if let outputPath = command.outputPath {
                        var lines = ["Database"]
                        lines.append(contentsOf: tablesByDatabase.keys.sorted())
                        try lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
                    }
                    return
                }

                if sql.contains("SHOW TABLES") {
                    if failShowTables {
                        throw PullError.listingFailed
                    }
                    if let outputPath = command.outputPath {
                        let database = command.arguments.last ?? ""
                        let tables = (tablesByDatabase[database] ?? []).sorted()
                        try tables.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
                    }
                    return
                }

                if let name = backtickDatabaseName(in: sql) {
                    if sql.contains("DROP DATABASE") {
                        didSendDropDatabase = true
                        tablesByDatabase[name] = []
                    }
                    if sql.contains("CREATE DATABASE") {
                        didSendCreateDatabase = true
                        if tablesByDatabase[name] == nil {
                            tablesByDatabase[name] = []
                        }
                    }
                }
                return
            }

            let database = command.arguments.last ?? ""
            guard let inputPath = command.inputPath else {
                return
            }
            let sql = (try? String(contentsOfFile: inputPath, encoding: .utf8)) ?? ""
            if sql.contains("DROP DATABASE") {
                didSendDropDatabase = true
                tablesByDatabase[database] = []
            }

            var tables = tablesByDatabase[database] ?? []
            for line in sql.split(separator: "\n") {
                let text = String(line)
                if text.hasPrefix("CREATE TABLE ") {
                    let name = text
                        .replacingOccurrences(of: "CREATE TABLE ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                    tables.insert(name)
                }
            }
            tablesByDatabase[database] = tables
        }
    }
}

private func backtickDatabaseName(in sql: String) -> String? {
    guard let start = sql.firstIndex(of: "`") else {
        return nil
    }
    let after = sql.index(after: start)
    guard let end = sql[after...].firstIndex(of: "`") else {
        return nil
    }
    return String(sql[after..<end])
}

private func dumpTarget(from arguments: [String]) -> (database: String, tables: [String]) {
    var index = 0
    var names: [String] = []
    let flagsWithValue = ["-h", "-P", "-u", "-e"]

    while index < arguments.count {
        let argument = arguments[index]
        if flagsWithValue.contains(argument) {
            index += 2
            continue
        }
        if argument.hasPrefix("-") {
            index += 1
            continue
        }
        names.append(argument)
        index += 1
    }

    let database = names.first ?? ""
    let tables = Array(names.dropFirst())
    return (database, tables)
}

nonisolated final class RealSSHTunnel: SSHTunneling {
    private let secrets: SecretStoring
    private var running: [Process] = []

    init(secrets: SecretStoring) {
        self.secrets = secrets
    }

    func openTunnel(for connection: Connection) async throws -> OpenTunnel {
        let localPort = try unusedLocalPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments = [
            "-N",
            "-L", "\(localPort):\(connection.host):\(connection.port)",
            "-p", String(connection.sshPort),
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=no"
        ]

        if connection.sshAuthMethod == .privateKey {
            arguments.append(contentsOf: ["-i", connection.sshKeyPath, "-o", "IdentitiesOnly=yes"])
        }

        arguments.append("\(connection.sshUser)@\(connection.sshHost)")
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        if connection.sshAuthMethod == .password, let password = secrets.sshPassword(forConnectionId: connection.id) {
            let askPass = try writeAskPassScript(secret: password)
            environment["SSH_ASKPASS"] = askPass
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        } else if connection.sshAuthMethod == .privateKey, let passphrase = secrets.sshPassphrase(forConnectionId: connection.id), passphrase.isEmpty == false {
            let askPass = try writeAskPassScript(secret: passphrase)
            environment["SSH_ASKPASS"] = askPass
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        }
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw PullError.tunnelFailed
        }

        try await waitUntilPortIsOpen(localPort, process: process)
        running.append(process)
        return OpenTunnel(localHost: "127.0.0.1", localPort: localPort)
    }

    func closeOpenedTunnels() {
        for process in running {
            if process.isRunning {
                process.terminate()
            }
        }
        running = []
    }

    private func unusedLocalPort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw PullError.tunnelFailed
        }
        defer { Darwin.close(socket) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socket, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw PullError.tunnelFailed
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.getsockname(socket, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            throw PullError.tunnelFailed
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func waitUntilPortIsOpen(_ port: Int, process: Process) async throws {
        for _ in 0..<50 {
            if process.isRunning == false {
                throw PullError.tunnelFailed
            }
            if canConnect(toPort: port) {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        process.terminate()
        throw PullError.tunnelFailed
    }

    private func canConnect(toPort port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            return false
        }
        defer { Darwin.close(socket) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = in_port_t(UInt16(port).bigEndian)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socket, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func writeAskPassScript(secret: String) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("umpadumpa-askpass-\(UUID().uuidString).sh")
            .path
        let escaped = secret.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\necho '\(escaped)'\n"
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
}

nonisolated final class RealProcessRunner: ProcessRunning {
    func run(
        _ command: ExternalCommand,
        onStandardErrorLine: (@Sendable (String) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.launch(command, onStandardErrorLine: onStandardErrorLine)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func launch(
        _ command: ExternalCommand,
        onStandardErrorLine: (@Sendable (String) -> Void)?
    ) throws {
        let process = Process()
        if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in command.environment {
            environment[key] = value
        }
        process.environment = environment

        if let outputPath = command.outputPath {
            FileManager.default.createFile(atPath: outputPath, contents: nil)
            process.standardOutput = FileHandle(forWritingAtPath: outputPath)
        }

        if let inputPath = command.inputPath {
            process.standardInput = FileHandle(forReadingAtPath: inputPath)
        }

        let errorPipe = Pipe()
        process.standardError = errorPipe

        var errorText = ""
        var leftover = ""
        let lock = NSLock()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else {
                return
            }
            lock.lock()
            errorText += chunk
            leftover += chunk
            let parts = leftover.split(separator: "\n", omittingEmptySubsequences: false)
            leftover = String(parts.last ?? "")
            let completeLines = parts.dropLast().map(String.init)
            lock.unlock()
            for line in completeLines {
                onStandardErrorLine?(line)
            }
        }

        try process.run()
        process.waitUntilExit()
        errorPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock()
        let remaining = leftover
        leftover = ""
        if remaining.isEmpty == false {
            errorText += remaining
        }
        let detail = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        if remaining.isEmpty == false {
            onStandardErrorLine?(remaining)
        }

        if process.terminationStatus != 0 {
            if command.tool == .mysqldump {
                throw PullError.dumpFailed(detail)
            }
            throw PullError.importFailed
        }
    }
}
