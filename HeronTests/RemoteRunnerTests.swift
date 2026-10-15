import XCTest
@testable import Heron

/// The SSH runner: how the command is built and its output read back, plus a real round trip
/// against a local test server when one is listening (see README: docker heron-sshd on 2224,
/// user heron, password heron-test).
final class RemoteRunnerTests: XCTestCase {
    private var connection: RemoteConnection {
        var c = RemoteConnection()
        c.name = "Test"
        c.host = "127.0.0.1"
        c.port = 2224
        c.username = "heron"
        c.auth = .password
        c.remotePath = "/config/app"
        return c
    }

    func testCommandCarriesFilesAsBase64AndQuotesTheFolder() {
        var c = connection
        c.remotePath = "/srv/it's here"
        let command = RemoteRunner.command(code: "echo 1;", runner: "<?php", connection: c)
        XCTAssertTrue(command.contains(Data("echo 1;".utf8).base64EncodedString()))
        XCTAssertTrue(command.contains("cd '/srv/it'\\''s here'"))
        XCTAssertTrue(command.contains(RemoteRunner.marker))
        XCTAssertTrue(command.contains("rm -rf \"$T\""))
    }

    func testParseSplitsOutputFromResult() throws {
        let json = #"{"kind":"php","php":"8.3.0","items":[],"warnings":[]}"#
        let result = try RemoteRunner.parse(stdout: "hello\n" + RemoteRunner.marker + "\n" + json + "\n", stderr: " warn ")
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(result.php, "8.3.0")
        XCTAssertEqual(result.stderr, "warn")
    }

    func testParseWithoutMarkerReportsStderr() {
        XCTAssertThrowsError(try RemoteRunner.parse(stdout: "", stderr: "php: not found")) { error in
            XCTAssertEqual(error.localizedDescription, "php: not found")
        }
    }

    func testRunsOnTheTestServer() async throws {
        let c = connection
        guard await Self.listening(host: c.host, port: c.port) else { throw XCTSkip("No test sshd on 2224") }
        let credential = Credential.password("heron-test")
        HostKeys.forget(host: c.host, port: c.port)
        // First contact: the key isn't trusted yet, then it is.
        do {
            _ = try await RemoteRunner.test(c, credential: credential)
            XCTFail("An unknown host key should be refused")
        } catch let error as HostKeyError {
            XCTAssertFalse(error.changed)
            HostKeys.trust(error.presentedKey, host: c.host, port: c.port)
        }
        let version = try await RemoteRunner.test(c, credential: credential)
        XCTAssertTrue(version.hasPrefix("8."), version)

        let result = try await RemoteRunner.run("echo getcwd();\n$x = require 'config.php';\n$x['name']", on: c, credential: credential)
        XCTAssertEqual(result.output, "/config/app")
        XCTAssertEqual(result.value?.summary, "Heron remote")
        XCTAssertNil(result.error)

        let failed = try await RemoteRunner.run("throw new RuntimeException('boom');", on: c, credential: credential)
        XCTAssertEqual(failed.error?.message, "boom")
        XCTAssertEqual(failed.error?.line, 1)
        HostKeys.forget(host: c.host, port: c.port)
    }

    private static func listening(host: String, port: Int) async -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/nc")
        process.arguments = ["-z", "-w", "1", host, String(port)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
