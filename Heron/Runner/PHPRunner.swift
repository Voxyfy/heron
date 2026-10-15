import Foundation

/// Finds a PHP binary on this Mac: the one chosen in Settings, else Herd, Homebrew, the system.
enum PHPBinary {
    static let customKey = "php.path"

    static var custom: URL? {
        guard let path = UserDefaults.standard.string(forKey: customKey), !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    static var candidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/Herd/bin/php"),
            URL(filePath: "/opt/homebrew/bin/php"),
            URL(filePath: "/usr/local/bin/php"),
            URL(filePath: "/usr/bin/php"),
        ]
    }

    static func find() -> URL? {
        ([custom].compactMap { $0 } + candidates).first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }
}

enum RunnerError: LocalizedError {
    case noPHP
    case noResult(stderr: String)

    var errorDescription: String? {
        switch self {
        case .noPHP:
            String(localized: "PHP isn't installed. Install it with Laravel Herd or Homebrew (brew install php).")
        case .noResult(let stderr):
            stderr.isEmpty ? String(localized: "PHP stopped without a result.") : stderr
        }
    }
}

/// Runs a snippet with the user's PHP, inside their project when one is chosen. Each run is a
/// fresh process, so nothing leaks from one run to the next, and Stop can always end it.
enum PHPRunner {
    static func run(_ code: String, in project: URL?, php: URL) async throws -> RunResult {
        let folder = FileManager.default.temporaryDirectory.appending(path: "heron-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let codeFile = folder.appending(path: "snippet.php")
        let resultFile = folder.appending(path: "result.json")
        try code.write(to: codeFile, atomically: true, encoding: .utf8)
        guard let runner = Bundle.main.url(forResource: "runner", withExtension: "php") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let process = Process()
        process.executableURL = php
        process.arguments = ["-d", "display_errors=stderr", "-d", "memory_limit=1G", runner.path(percentEncoded: false),
                             codeFile.path(percentEncoded: false), resultFile.path(percentEncoded: false),
                             project?.path(percentEncoded: false) ?? ""]
        process.currentDirectoryURL = project ?? folder
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let (output, errors) = try await withTaskCancellationHandler {
            try await process.runCollectingOutput(stdout: stdout, stderr: stderr)
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()

        let stderrText = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? Data(contentsOf: resultFile),
              var result = try? JSONDecoder().decode(RunResult.self, from: data) else {
            throw RunnerError.noResult(stderr: stderrText)
        }
        result.output = String(decoding: output, as: UTF8.self)
        result.stderr = stderrText
        return result
    }

    /// Tidies a snippet with format.php: indentation, spaces around operators and after commas,
    /// one statement per line. Returns the snippet unchanged if anything goes wrong.
    static func format(_ code: String, indent: String, quotes: String = "double", php: URL) async -> String {
        guard let script = Bundle.main.url(forResource: "format", withExtension: "php") else { return code }
        return await Task.detached {
            let process = Process()
            process.executableURL = php
            process.arguments = [script.path(percentEncoded: false), indent == "\t" ? "tab" : String(indent.count), quotes]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return code }
            input.fileHandleForWriting.write(Data(code.utf8))
            try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else { return code }
            var tidy = String(decoding: data, as: UTF8.self)
            // Keep the snippet's own ending: format.php always ends with a newline.
            if !code.hasSuffix("\n"), tidy.hasSuffix("\n") { tidy.removeLast() }
            return tidy
        }.value
    }

    /// "8.4.23" for the given binary, or nil if it doesn't run.
    static func version(of php: URL) -> String? {
        let process = Process()
        process.executableURL = php
        process.arguments = ["-r", "echo PHP_VERSION;"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

private extension Process {
    /// Runs to completion without blocking a thread of the concurrency pool: the pipes are
    /// drained on their own queue and the exit arrives through the termination handler.
    func runCollectingOutput(stdout: Pipe, stderr: Pipe) async throws -> (Data, Data) {
        let collected = Collected()
        let group = DispatchGroup()
        for (pipe, keyPath) in [(stdout, \Collected.output), (stderr, \Collected.errors)] {
            group.enter()
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { (handle: FileHandle) in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                } else {
                    collected.append(data, to: keyPath)
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            terminationHandler = { _ in
                group.notify(queue: .global()) {
                    continuation.resume(returning: collected.values)
                }
            }
            do {
                try run()
            } catch {
                terminationHandler = nil
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    var output = Data()
    var errors = Data()

    func append(_ data: Data, to keyPath: ReferenceWritableKeyPath<Collected, Data>) {
        lock.lock(); defer { lock.unlock() }
        self[keyPath: keyPath].append(data)
    }

    var values: (Data, Data) {
        lock.lock(); defer { lock.unlock() }
        return (output, errors)
    }
}
