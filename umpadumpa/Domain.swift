import Foundation

enum SSHAuthMethod: String, Codable, Equatable {
    case password
    case privateKey = "private-key"
}

struct Connection: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    var usesSSH: Bool = false
    var sshHost: String = ""
    var sshPort: Int = 22
    var sshUser: String = ""
    var sshAuthMethod: SSHAuthMethod = .password
    var sshKeyPath: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, user
        case usesSSH, sshHost, sshPort, sshUser, sshAuthMethod, sshKeyPath
    }

    init(
        id: UUID,
        name: String,
        host: String,
        port: Int,
        user: String,
        usesSSH: Bool = false,
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        sshAuthMethod: SSHAuthMethod = .password,
        sshKeyPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.usesSSH = usesSSH
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshAuthMethod = sshAuthMethod
        self.sshKeyPath = sshKeyPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        user = try container.decode(String.self, forKey: .user)
        usesSSH = try container.decodeIfPresent(Bool.self, forKey: .usesSSH) ?? false
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshAuthMethod = try container.decodeIfPresent(SSHAuthMethod.self, forKey: .sshAuthMethod) ?? .password
        sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
    }

    var detail: String {
        if usesSSH {
            return "\(host):\(port) · SSH"
        }
        return "\(host):\(port)"
    }

    func duplicated() -> Connection {
        var copy = self
        copy.id = UUID()
        copy.name = name + " (copy)"
        return copy
    }
}

struct OpenTunnel: Equatable {
    var localHost: String
    var localPort: Int
}

enum Strategy: String, Codable, Equatable {
    case replace
    case backupThenReplace = "backup-then-replace"
    case createNew = "create-new"
}

enum ReplaceMode: String, Codable, Equatable {
    case importInPlace = "import-in-place"
    case dropDatabase = "drop-database"
}

struct Recipe: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var sourceConnectionId: UUID
    var sourceDatabase: String
    var destinationConnectionId: UUID
    var destinationDatabase: String
    var strategy: Strategy
    var replaceMode: ReplaceMode
    var tables: [String]

    func pullRequest(source: Connection, destination: Connection) -> PullRequest {
        PullRequest(
            sourceConnection: source,
            sourceDatabase: sourceDatabase,
            destinationConnection: destination,
            destinationDatabase: destinationDatabase,
            strategy: strategy,
            replaceMode: replaceMode,
            tables: tables,
            recipeId: id
        )
    }

    func duplicated() -> Recipe {
        var copy = self
        copy.id = UUID()
        copy.title = title + " (copy)"
        return copy
    }

    static func forSource(connectionId: UUID, in recipes: [Recipe]) -> [Recipe] {
        recipes.filter { $0.sourceConnectionId == connectionId }
    }
}

struct PullRequest: Equatable {
    var sourceConnection: Connection
    var sourceDatabase: String
    var destinationConnection: Connection
    var destinationDatabase: String
    var strategy: Strategy
    var replaceMode: ReplaceMode
    var tables: [String]
    var backupName: String = ""
    var recipeId: UUID? = nil
}

struct ConfirmSummary: Equatable {
    var sourceLabel: String
    var destinationLabel: String
    var strategyLabel: String
    var replaceModeLabel: String
    var tablesLabel: String
    var backupNameLabel: String
    var request: PullRequest
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var when: Date
    var source: String
    var destination: String
    var succeeded: Bool

    var resultLabel: String {
        succeeded ? "OK" : "Failed"
    }
}

enum HistoryDisplay {
    static let defaultSortOrder = [
        KeyPathComparator(\HistoryEntry.when, order: .reverse)
    ]

    /// Rows as the History table should show them for the current header sort.
    /// SwiftUI Table updates `sortOrder` from clicks but does not re-order the
    /// collection itself — callers must pass this sorted list into `Table`.
    static func sorted(
        _ entries: [HistoryEntry],
        by sortOrder: [KeyPathComparator<HistoryEntry>]
    ) -> [HistoryEntry] {
        entries.sorted(using: sortOrder)
    }
}

enum AppVersion {
    static func marketingVersion(from info: [String: Any]) -> String {
        (info["CFBundleShortVersionString"] as? String) ?? ""
    }

    static func buildNumber(from info: [String: Any]) -> String {
        (info["CFBundleVersion"] as? String) ?? ""
    }

    static func displayName(from info: [String: Any]) -> String {
        if let name = info["CFBundleDisplayName"] as? String, !name.isEmpty {
            return name
        }
        if let name = info["CFBundleName"] as? String, !name.isEmpty {
            return name
        }
        return ""
    }

    static func aboutMenuTitle(from info: [String: Any]) -> String {
        let name = displayName(from: info)
        if name.isEmpty {
            return "About"
        }
        return "About \(name)"
    }
}

enum PullError: Error, Equatable {
    case alreadyRunning
    case dumpFailed(String)
    case importFailed
    case tunnelFailed
    case missingClient(ClientTool)
    case nameAlreadyExists
    case listingFailed
}

enum PullPhase: Equatable {
    case idle
    case dumpingSource
    case creatingBackup
    case importingDestination
    case succeeded
    case failed
}

struct PullProgress: Equatable {
    var phase: PullPhase
    var tablesReached: Int
    var tablesTotal: Int
    var dumpFileMegabytes: Int?
}

enum ClientTool: Equatable {
    case mysqldump
    case mysql
}

struct ClientSettings: Equatable, Codable {
    var mysqldumpPath: String
    var mysqlPath: String
    var firstOpenSheetFinished: Bool

    static let usingPath = ClientSettings(mysqldumpPath: "", mysqlPath: "", firstOpenSheetFinished: false)

    init(mysqldumpPath: String, mysqlPath: String, firstOpenSheetFinished: Bool = false) {
        self.mysqldumpPath = mysqldumpPath
        self.mysqlPath = mysqlPath
        self.firstOpenSheetFinished = firstOpenSheetFinished
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mysqldumpPath = try container.decodeIfPresent(String.self, forKey: .mysqldumpPath) ?? ""
        mysqlPath = try container.decodeIfPresent(String.self, forKey: .mysqlPath) ?? ""
        firstOpenSheetFinished = try container.decodeIfPresent(Bool.self, forKey: .firstOpenSheetFinished) ?? false
    }
}

struct FirstOpenClientSheetSession: Equatable {
    var saved: ClientSettings
    var deferredThisLaunch: Bool

    init(saved: ClientSettings, deferredThisLaunch: Bool = false) {
        self.saved = saved
        self.deferredThisLaunch = deferredThisLaunch
    }

    var isPresented: Bool {
        if deferredThisLaunch {
            return false
        }
        if saved.firstOpenSheetFinished {
            return false
        }
        let dump = saved.mysqldumpPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let mysql = saved.mysqlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return dump.isEmpty && mysql.isEmpty
    }

    mutating func continueWith(mysqldumpPath: String, mysqlPath: String) {
        saved = ClientSettings(
            mysqldumpPath: mysqldumpPath,
            mysqlPath: mysqlPath,
            firstOpenSheetFinished: true
        )
    }

    mutating func notNow() {
        deferredThisLaunch = true
    }
}

struct ExternalCommand: Equatable {
    var tool: ClientTool
    var executable: String
    var arguments: [String]
    var environment: [String: String]
    var outputPath: String?
    var inputPath: String?
}

protocol SecretStoring: AnyObject {
    func setPassword(_ password: String, forConnectionId id: UUID)
    func password(forConnectionId id: UUID) -> String?
    func setSSHPassword(_ password: String, forConnectionId id: UUID)
    func sshPassword(forConnectionId id: UUID) -> String?
    func setSSHPassphrase(_ passphrase: String, forConnectionId id: UUID)
    func sshPassphrase(forConnectionId id: UUID) -> String?
    func deleteSecrets(forConnectionId id: UUID)
}

protocol Clock {
    var now: Date { get }
}

protocol ProcessRunning: AnyObject {
    func run(
        _ command: ExternalCommand,
        onStandardErrorLine: (@Sendable (String) -> Void)?
    ) async throws
}

extension ProcessRunning {
    func run(_ command: ExternalCommand) async throws {
        try await run(command, onStandardErrorLine: nil)
    }
}

protocol SSHTunneling: AnyObject {
    func openTunnel(for connection: Connection) async throws -> OpenTunnel
    func closeOpenedTunnels()
}

protocol HistoryStoring: AnyObject {
    var entries: [HistoryEntry] { get }
    func append(_ entry: HistoryEntry)
    func clear()
}

protocol SettingsStoring: AnyObject {
    func load() -> ClientSettings
    func save(_ settings: ClientSettings)
}

protocol PathChecking {
    func pathExists(_ path: String) -> Bool
}

enum SystemDatabases {
    static let names: Set<String> = [
        "mysql",
        "information_schema",
        "performance_schema",
        "sys"
    ]

    static func visible(_ names: [String], showSystem: Bool) -> [String] {
        if showSystem {
            return names
        }
        return names.filter { Self.names.contains($0) == false }
    }
}

enum DatabaseListingSequence {
    static func ordered(source: Connection, destination: Connection?) -> [Connection] {
        if let destination, destination.id != source.id {
            return [source, destination]
        }
        return [source]
    }
}

struct DatabasePickerOption: Equatable {
    var id: String
    var title: String
}

enum DatabasePickerOptions {
    static func menu(liveNames: [String], selected: String, showSystem: Bool) -> [DatabasePickerOption] {
        let live = SystemDatabases.visible(liveNames, showSystem: showSystem)
        var options = [DatabasePickerOption(id: "", title: "Choose a Database")]
        for name in live {
            options.append(DatabasePickerOption(id: name, title: name))
        }
        if selected.isEmpty == false && live.contains(selected) == false {
            options.append(DatabasePickerOption(id: selected, title: "\(selected) (absent)"))
        }
        return options
    }
}

struct TablePickerOption: Equatable {
    var id: String
    var title: String
}

enum TablePickerOptions {
    static func checklist(liveNames: [String], keptNames: [String]) -> [TablePickerOption] {
        var seen: Set<String> = []
        var options: [TablePickerOption] = []
        for name in liveNames {
            if seen.contains(name) {
                continue
            }
            seen.insert(name)
            options.append(TablePickerOption(id: name, title: name))
        }
        for name in keptNames {
            if seen.contains(name) {
                continue
            }
            seen.insert(name)
            options.append(TablePickerOption(id: name, title: "\(name) (absent)"))
        }
        return options
    }
}

enum PullForm {
    static func canStartDump(
        sourceDatabase: String,
        strategy: Strategy,
        destinationDatabase: String,
        newDatabaseName: String
    ) -> Bool {
        if sourceDatabase.isEmpty {
            return false
        }
        if strategy == .createNew {
            return newDatabaseName.isEmpty == false
        }
        return destinationDatabase.isEmpty == false
    }
}

enum BackupName {
    static func defaultName(database: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "\(database)_backup_\(formatter.string(from: date))"
    }
}
