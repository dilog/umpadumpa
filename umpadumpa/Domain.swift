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
            tables: tables
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
}

enum PullError: Error, Equatable {
    case alreadyRunning
    case dumpFailed
    case importFailed
    case tunnelFailed
    case missingClient(ClientTool)
    case nameAlreadyExists
}

enum ClientTool: Equatable {
    case mysqldump
    case mysql
}

struct ClientSettings: Equatable, Codable {
    var mysqldumpPath: String
    var mysqlPath: String

    static let usingPath = ClientSettings(mysqldumpPath: "", mysqlPath: "")
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
}

protocol Clock {
    var now: Date { get }
}

protocol ProcessRunning: AnyObject {
    func run(_ command: ExternalCommand) async throws
}

protocol SSHTunneling: AnyObject {
    func openTunnel(for connection: Connection) async throws -> OpenTunnel
}

protocol HistoryStoring: AnyObject {
    var entries: [HistoryEntry] { get }
    func append(_ entry: HistoryEntry)
}

protocol SettingsStoring: AnyObject {
    func load() -> ClientSettings
    func save(_ settings: ClientSettings)
}

protocol PathChecking {
    func pathExists(_ path: String) -> Bool
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
