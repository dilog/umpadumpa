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

enum Strategy: String, Equatable {
    case replace
    case createNew = "create-new"
}

enum ReplaceMode: String, Equatable {
    case importInPlace = "import-in-place"
    case dropDatabase = "drop-database"
}

struct PullRequest: Equatable {
    var sourceConnection: Connection
    var sourceDatabase: String
    var destinationConnection: Connection
    var destinationDatabase: String
    var strategy: Strategy
    var replaceMode: ReplaceMode
    var tables: [String]
}

struct ConfirmSummary: Equatable {
    var sourceLabel: String
    var destinationLabel: String
    var strategyLabel: String
    var replaceModeLabel: String
    var tablesLabel: String
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
}

enum ClientTool: Equatable {
    case mysqldump
    case mysql
}

struct ExternalCommand: Equatable {
    var tool: ClientTool
    var arguments: [String]
    var environment: [String: String]
    var outputPath: String?
    var inputPath: String?
}

protocol SecretStoring: AnyObject {
    func setPassword(_ password: String, forConnectionId id: UUID)
    func password(forConnectionId id: UUID) -> String?
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
