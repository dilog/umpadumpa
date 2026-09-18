import Foundation
#if os(macOS)
import Security
#endif

nonisolated final class MemorySecretStore: SecretStoring {
    private var passwords: [UUID: String] = [:]

    func setPassword(_ password: String, forConnectionId id: UUID) {
        passwords[id] = password
    }

    func password(forConnectionId id: UUID) -> String? {
        passwords[id]
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
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: connectionsFile)
        }
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
        disk.saveHistory(entries)
    }
}

#if os(macOS)
nonisolated final class KeychainSecretStore: SecretStoring {
    private let service = "dev.umpadumpa.connection"

    func setPassword(_ password: String, forConnectionId id: UUID) {
        let account = id.uuidString
        let passwordData = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = passwordData
        SecItemAdd(add as CFDictionary, nil)
    }

    func password(forConnectionId id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
#endif

nonisolated final class FakeSSHTunnel: SSHTunneling {
    var localHost = "127.0.0.1"
    var localPort = 61000
    var failOpen = false
    private(set) var openedFor: [Connection] = []

    func openTunnel(for connection: Connection) async throws -> OpenTunnel {
        openedFor.append(connection)
        if failOpen {
            throw PullError.tunnelFailed
        }
        return OpenTunnel(localHost: localHost, localPort: localPort)
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
    var holdDump = false

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

    func run(_ command: ExternalCommand) async throws {
        invocations.append(command)

        if command.tool == .mysqldump {
            if holdDump {
                dumpIsHeld = true
                dumpIsHeldContinuation?.resume()
                dumpIsHeldContinuation = nil
                await withCheckedContinuation { continuation in
                    dumpHoldContinuation = continuation
                }
            }

            if failDump {
                throw PullError.dumpFailed
            }

            let database = command.arguments.last ?? ""
            let tables = tablesByDatabase[database] ?? []
            var sql = ""
            for table in tables.sorted() {
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
            if failImport {
                throw PullError.importFailed
            }

            if let eIndex = command.arguments.firstIndex(of: "-e"),
               eIndex + 1 < command.arguments.count {
                let sql = command.arguments[eIndex + 1]
                let names = Array(tablesByDatabase.keys)
                for name in names {
                    if sql.contains(name) == false {
                        continue
                    }
                    if sql.contains("DROP DATABASE") {
                        didSendDropDatabase = true
                        tablesByDatabase[name] = []
                    }
                    if sql.contains("CREATE DATABASE") {
                        didSendCreateDatabase = true
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

nonisolated final class RealSSHTunnel: SSHTunneling {
    func openTunnel(for connection: Connection) async throws -> OpenTunnel {
        throw PullError.tunnelFailed
    }
}

nonisolated final class RealProcessRunner: ProcessRunning {
    func run(_ command: ExternalCommand) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.launch(command)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func launch(_ command: ExternalCommand) throws {
        let process = Process()
        if command.tool == .mysqldump {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["mysqldump"] + command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["mysql"] + command.arguments
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

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            if command.tool == .mysqldump {
                throw PullError.dumpFailed
            }
            throw PullError.importFailed
        }
    }
}
