import Citadel
import Foundation
import NIOCore
import NIOSSH

/// Runs a snippet on a server over SSH. One command does everything: it writes runner.php and
/// the snippet to a temporary folder, runs php from the project folder, prints the result file
/// after a marker, and cleans up. Nothing of the server's project is changed.
enum RemoteRunner {
    static let marker = "__HERON_RESULT_7f3a__"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Opens the connection, checking the server's key against what was trusted before.
    static func connect(_ connection: RemoteConnection, credential: Credential) async throws -> SSHClient {
        let validator = HostKeyValidator(host: connection.host, port: connection.port)
        let method: SSHAuthenticationMethod
        switch credential {
        case .password(let password):
            method = .passwordBased(username: connection.username, password: password)
        case .key(let key, let passphrase):
            method = try SSHKey.authentication(username: connection.username, key: key, passphrase: passphrase)
        }
        let auth = Unchecked(method)
        var settings = SSHClientSettings(
            host: connection.host.trimmingCharacters(in: .whitespaces),
            port: connection.port,
            authenticationMethod: { auth.value },
            hostKeyValidator: .custom(validator)
        )
        settings.connectTimeout = .seconds(15)
        var algorithms = SSHAlgorithms()
        algorithms.transportProtectionSchemes = .add([AES128CTR.self])
        algorithms.keyExchangeAlgorithms = .add([DiffieHellmanGroup14Sha256.self])
        settings.algorithms = algorithms
        do {
            return try await SSHClient.connect(to: settings)
        } catch {
            if let rejection = validator.rejection { throw rejection }
            if case SSHClientError.allAuthenticationOptionsFailed = error,
               case .key(let key, _) = credential, SSHKey.isRSA(key) {
                throw SSHKey.Problem.rsaRefused
            }
            throw error
        }
    }

    /// The shell command that runs a snippet; the files travel inside it as base64, so no SFTP.
    static func command(code: String, runner: String, connection: RemoteConnection) -> String {
        let folder = connection.remotePath.trimmingCharacters(in: .whitespaces)
        let quotedFolder = shellQuote(folder.isEmpty ? "." : folder)
        let php = shellQuote(connection.phpPath.isEmpty ? "php" : connection.phpPath)
        return """
        T=$(mktemp -d /tmp/heron.XXXXXX) && \
        printf '%s' '\(Data(runner.utf8).base64EncodedString())' | base64 -d > "$T/runner.php" && \
        printf '%s' '\(Data(code.utf8).base64EncodedString())' | base64 -d > "$T/snippet.php" && \
        cd \(quotedFolder) 2>/dev/null; \
        \(php) -d display_errors=stderr -d memory_limit=1G "$T/runner.php" "$T/snippet.php" "$T/result.json" \(quotedFolder); \
        printf '\\n%s\\n' '\(marker)'; cat "$T/result.json" 2>/dev/null; rm -rf "$T"
        """
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func run(_ code: String, on connection: RemoteConnection, credential: Credential) async throws -> RunResult {
        guard let runnerURL = Bundle.main.url(forResource: "runner", withExtension: "php"),
              let runner = try? String(contentsOf: runnerURL, encoding: .utf8) else {
            throw Failure(message: "runner.php is missing from the app.")
        }
        let client = try await connect(connection, credential: credential)
        let (stdout, stderr): (String, String)
        do {
            (stdout, stderr) = try await execute(command(code: code, runner: runner, connection: connection), on: client)
        } catch {
            try? await client.close()
            throw error
        }
        try? await client.close()
        return try parse(stdout: stdout, stderr: stderr)
    }

    /// Signs in and asks the server's php for its version: the connection form's Test button.
    static func test(_ connection: RemoteConnection, credential: Credential) async throws -> String {
        let client = try await connect(connection, credential: credential)
        let php = shellQuote(connection.phpPath.isEmpty ? "php" : connection.phpPath)
        let folder = connection.remotePath.trimmingCharacters(in: .whitespaces)
        var command = "\(php) -r 'echo PHP_VERSION;' 2>&1"
        if !folder.isEmpty { command = "cd \(shellQuote(folder)) && " + command }
        let (stdout, stderr): (String, String)
        do {
            (stdout, stderr) = try await execute(command, on: client)
        } catch {
            try? await client.close()
            throw error
        }
        try? await client.close()
        let version = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.first?.isNumber == true else {
            throw Failure(message: stderr.isEmpty ? version : stderr)
        }
        return version
    }

    /// Runs one command on an exec channel (the login shell interprets it, no pty, so nothing is
    /// echoed back) and collects what it printed; a non-zero exit is not an error here.
    private static func execute(_ command: String, on client: SSHClient) async throws -> (String, String) {
        var out = Data(), err = Data()
        do {
            let stream = try await client.executeCommandStream(command, inShell: false)
            for try await chunk in stream {
                switch chunk {
                case .stdout(var buffer): out.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
                case .stderr(var buffer): err.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
                }
            }
        } catch is SSHClient.CommandFailed {
            // php exits 1 on a fatal error; the result file still says what happened.
        }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    /// Splits the printed output from the result JSON that follows the marker.
    static func parse(stdout: String, stderr: String) throws -> RunResult {
        guard let range = stdout.range(of: "\n" + marker + "\n") ?? stdout.range(of: marker + "\n") else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty
                          ? String(localized: "The server didn't return a result. Is php installed there?")
                          : message)
        }
        let output = String(stdout[..<range.lowerBound])
        let json = String(stdout[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8), var result = try? JSONDecoder().decode(RunResult.self, from: data) else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty ? String(localized: "PHP stopped without a result.") : message)
        }
        result.output = output
        result.stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
