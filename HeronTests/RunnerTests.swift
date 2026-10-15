import XCTest
@testable import Heron

/// Runs snippets with the PHP found on this Mac. Skipped when there's none.
final class RunnerTests: XCTestCase {
    private var php: URL!

    override func setUp() async throws {
        guard let php = PHPBinary.find() else { throw XCTSkip("No PHP on this Mac") }
        self.php = php
    }

    private func run(_ code: String, in project: URL? = nil) async throws -> RunResult {
        try await PHPRunner.run(code, in: project, php: php)
    }

    func testLastExpressionIsTheValue() async throws {
        let result = try await run("$a = [1, 2, 3];\narray_sum($a)")
        XCTAssertEqual(result.value?.summary, "6")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.kind, .php)
    }

    func testTrailingCommentAndSemicolon() async throws {
        let result = try await run("$d = 2 * 21; // answer\n$d; // done")
        XCTAssertEqual(result.value?.summary, "42")
    }

    func testStatementsAreNotReturned() async throws {
        let result = try await run("foreach ([1, 2] as $n) { echo $n; }")
        XCTAssertEqual(result.output, "12")
        XCTAssertNil(result.value)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testArraysAndObjectsBecomeTrees() async throws {
        let result = try await run("""
            class Point { public $x = 1; protected $y = [2]; private $z = 'z'; }
            ['p' => new Point, 'n' => null]
            """)
        let point = try XCTUnwrap(result.value?.children?.first { $0.key == "p" }?.value)
        XCTAssertEqual(point.class, "Point")
        XCTAssertEqual(point.children?.map(\.key), ["x", "y", "z"])
        XCTAssertEqual(point.children?.map(\.kind), ["public", "protected", "private"])
    }

    func testEveryStatementValueIsListedInOrder() async throws {
        let result = try await run("$a = 1;\n$b = $a + 1;\necho 'x';\nfunction f() { return 3; }\nf();\n$b")
        var lines: [Int] = [], values: [String] = []
        for case .value(let line, let node) in result.items {
            lines.append(line)
            values.append(node.summary)
        }
        XCTAssertEqual(lines, [1, 2, 5, 6])
        XCTAssertEqual(values, ["1", "2", "3", "2"])
        XCTAssertEqual(result.valueLine, 6)
    }

    func testErrorPointsAtItsLine() async throws {
        let result = try await run("$a = 1;\n$b = 2;\nthrow new RuntimeException('boom');")
        XCTAssertEqual(result.error?.class, "RuntimeException")
        XCTAssertEqual(result.error?.message, "boom")
        XCTAssertEqual(result.error?.line, 3)
    }

    func testErrorInsideAFunctionPointsAtTheCall() async throws {
        let result = try await run("$x = 1;\nstr_repeat('a', -1);")
        XCTAssertEqual(result.error?.line, 2)
    }

    func testWarningsKeepTheirLine() async throws {
        let result = try await run("$a = 1;\n$b = $missing + 1;\n$b")
        XCTAssertEqual(result.value?.summary, "1")
        XCTAssertEqual(result.warnings.first?.line, 2)
        XCTAssertTrue(result.warnings.first?.message.contains("missing") == true)
    }

    func testSyntaxErrorHasALine() async throws {
        let result = try await run("$a = 1;\n$b = ;")
        XCTAssertEqual(result.error?.class, "ParseError")
        XCTAssertEqual(result.error?.line, 2)
    }

    func testExitStillReportsOutput() async throws {
        let result = try await run("echo 'bye'; exit;")
        XCTAssertEqual(result.output, "bye")
    }

    func testStopEndsALongRun() async throws {
        let php = self.php!
        let task = Task { try await PHPRunner.run("sleep(30);", in: nil, php: php) }
        try await Task.sleep(for: .milliseconds(400))
        let started = ContinuousClock.now
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    /// Set HERON_LARAVEL_PROJECT (TEST_RUNNER_HERON_LARAVEL_PROJECT for xcodebuild) to a
    /// Laravel app with vendor/ installed.
    func testLaravelProjectBoots() async throws {
        guard let path = ProcessInfo.processInfo.environment["HERON_LARAVEL_PROJECT"] else {
            throw XCTSkip("HERON_LARAVEL_PROJECT not set")
        }
        let project = URL(filePath: path)
        let result = try await run("collect([1, 2, 3])->map(fn ($n) => $n * 2)", in: project)
        XCTAssertEqual(result.kind, .laravel)
        XCTAssertNotNil(result.framework)
        XCTAssertEqual(result.value?.class, "Illuminate\\Support\\Collection")
        XCTAssertEqual(result.value?.children?.map(\.value.summary), ["2", "4", "6"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "/result.json"))
    }
}

final class FormatterTests: XCTestCase {
    private var php: URL!

    override func setUp() async throws {
        guard let php = PHPBinary.find() else { throw XCTSkip("No PHP on this Mac") }
        self.php = php
    }

    func testTidiesIndentationAndSpacing() async {
        let messy = "$users=collect([1,2,3]);\nforeach($users as $u){\nif($u>1){\necho $u;\n}else{\n          echo 'small';\n}\n}\n$users"
        let tidy = await PHPRunner.format(messy, indent: "    ", php: php)
        XCTAssertEqual(tidy, """
            $users = collect([1, 2, 3]);
            foreach ($users as $u) {
                if ($u > 1) {
                    echo $u;
                } else {
                    echo 'small';
                }
            }
            $users
            """)
        let again = await PHPRunner.format(tidy, indent: "    ", php: php)
        XCTAssertEqual(again, tidy, "Tidying twice changes nothing")
    }

    func testLeavesStringsAndCommentsAlone() async {
        let code = "$s=\"a=b,c {$x}\"; // a=b,c\n$t='if(x){'"
        let tidy = await PHPRunner.format(code, indent: "    ", php: php)
        XCTAssertEqual(tidy, "$s = \"a=b,c {$x}\"; // a=b,c\n$t = 'if(x){'")
    }

    func testTabsAndNegativeNumbers() async {
        let tidy = await PHPRunner.format("if($a){\nreturn -1;\n}", indent: "\t", php: php)
        XCTAssertEqual(tidy, "if ($a) {\n\treturn -1;\n}")
    }

    func testUnbalancedCodeIsLeftAsIs() async {
        let code = "if ($a) {\n  echo 1;"
        let tidy = await PHPRunner.format(code, indent: "    ", php: php)
        XCTAssertEqual(tidy, code)
    }
}
