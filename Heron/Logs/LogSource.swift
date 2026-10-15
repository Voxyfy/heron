import Foundation

/// Where a tab's logs live: the project's storage/logs on this Mac, or the same folder on its server.
enum LogSource {
    case local(URL)
    case remote(RemoteConnection, Credential)

    /// Reads at most this much from the end of a file; older records are left in the file.
    static let tailBytes = 4_000_000

    var folderDescription: String {
        switch self {
        case .local(let url): (url.appending(path: "storage/logs").path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        case .remote(let connection, _): "\(connection.username)@\(connection.host):\(connection.remotePath)/storage/logs"
        }
    }

    /// Log file names, newest first.
    func files() async throws -> [String] {
        switch self {
        case .local(let project):
            let folder = project.appending(path: "storage/logs")
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return urls.filter { $0.pathExtension == "log" }
                .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
                .map(\.lastPathComponent)
        case .remote(let connection, let credential):
            let folder = RemoteRunner.shellQuote(connection.remotePath + "/storage/logs")
            let listing = try await RemoteRunner.output(of: "ls -1 \(folder) 2>/dev/null", on: connection, credential: credential)
            return listing.split(separator: "\n").map(String.init).filter { $0.hasSuffix(".log") }.sorted(by: >)
        }
    }

    func read(_ file: String) async throws -> String {
        switch self {
        case .local(let project):
            let url = project.appending(path: "storage/logs").appending(path: file)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
            try handle.seek(toOffset: start)
            let data = handle.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        case .remote(let connection, let credential):
            let path = RemoteRunner.shellQuote(connection.remotePath + "/storage/logs/" + file)
            return try await RemoteRunner.output(of: "tail -c \(Self.tailBytes) \(path)", on: connection, credential: credential)
        }
    }
}
