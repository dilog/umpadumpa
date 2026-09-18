import Foundation

struct Connection: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String

    var detail: String {
        "\(host):\(port)"
    }
}

enum Strategy: String, Equatable {
    case replace
}

enum ReplaceMode: String, Equatable {
    case importInPlace
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

protocol HistoryStoring: AnyObject {
    var entries: [HistoryEntry] { get }
    func append(_ entry: HistoryEntry)
}
