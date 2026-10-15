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

    func testOnlyTheLastStatementBecomesACard() async throws {
        let result = try await run("$a = 1;\n$b = $a + 1;\necho 'x';\nfunction f() { return 3; }\nf();\n$b")
        var cards: [(Int, String)] = [], marks: [Int] = []
        for item in result.items {
            switch item {
            case .value(let line, let node): cards.append((line, node.summary))
            case .mark(let line): marks.append(line)
            default: break
            }
        }
        XCTAssertEqual(cards.map(\.0), [6])
        XCTAssertEqual(cards.map(\.1), ["2"])
        XCTAssertEqual(marks, [1, 2, 5, 6], "Every expression statement marks its line")
        XCTAssertEqual(result.valueLine, 6)
    }

    func testDumpMakesACardAtItsLine() async throws {
        let result = try await run("$a = 5;\ndump($a);\ndump('x', [1]);\n$a + 1")
        var cards: [(Int, String)] = []
        for case .value(let line, let node) in result.items { cards.append((line, node.summary)) }
        XCTAssertEqual(cards.map(\.0), [2, 3, 3, 4])
        XCTAssertEqual(cards.map(\.1), ["5", "x", "array:1", "6"])
        XCTAssertTrue(result.output.isEmpty, "dump() prints nothing to the output")
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
        let all = try XCTUnwrap(result.value?.children?.first { $0.key == "all" }?.value)
        XCTAssertEqual(all.children?.map(\.value.summary), ["2", "4", "6"], "A collection shows its items under all")
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
                    echo "small";
                }
            }
            $users;
            """)
        let again = await PHPRunner.format(tidy, indent: "    ", php: php)
        XCTAssertEqual(again, tidy, "Tidying twice changes nothing")
    }

    func testLeavesStringsAndCommentsAlone() async {
        let code = "$s=\"a=b,c {$x}\"; // a=b,c\n$t='if(x){'"
        let tidy = await PHPRunner.format(code, indent: "    ", php: php)
        XCTAssertEqual(tidy, "$s = \"a=b,c {$x}\"; // a=b,c\n$t = \"if(x){\";")
    }

    func testChainedCallsAreIndentedUnderTheirStart() async {
        let tidy = await PHPRunner.format("collect(range(1,10))\n->reverse()\n->values();", indent: "    ", php: php)
        XCTAssertEqual(tidy, "collect(range(1, 10))\n    ->reverse()\n    ->values();")
        let again = await PHPRunner.format(tidy, indent: "    ", php: php)
        XCTAssertEqual(again, tidy)
    }

    func testTabsAndNegativeNumbers() async {
        let tidy = await PHPRunner.format("if($a){\nreturn -1;\n}", indent: "\t", php: php)
        XCTAssertEqual(tidy, "if ($a) {\n\treturn -1;\n}")
    }

    func testLastStatementGetsItsSemicolon() async {
        let plain = await PHPRunner.format("$a = 1;\n$a + 1", indent: "    ", php: php)
        XCTAssertEqual(plain, "$a = 1;\n$a + 1;")
        let commented = await PHPRunner.format("$a + 1 // sum", indent: "    ", php: php)
        XCTAssertEqual(commented, "$a + 1; // sum", "Before a trailing comment")
        let block = await PHPRunner.format("if ($a) {\n    echo 1;\n}", indent: "    ", php: php)
        XCTAssertEqual(block, "if ($a) {\n    echo 1;\n}", "A block needs none")
        let chain = await PHPRunner.format("collect([1])\n    ->sum()", indent: "    ", php: php)
        XCTAssertEqual(chain, "collect([1])\n    ->sum();")
    }

    func testMissingSemicolonsBetweenStatements() async {
        let two = await PHPRunner.format("dd(\"selam\")\ndd('merhaba');", indent: "    ", php: php)
        XCTAssertEqual(two, "dd(\"selam\");\ndd(\"merhaba\");", "A semicolon between statements, and plain strings in double quotes")
        let chain = await PHPRunner.format("$x = foo()\n    ->bar()\n$y = 1 // c\n$z = [\n    1,\n    2\n]", indent: "    ", php: php)
        XCTAssertEqual(chain, "$x = foo()\n    ->bar();\n$y = 1; // c\n$z = [\n    1,\n    2\n];")
        let header = await PHPRunner.format("foreach ($b as $c)\n    dd($c)", indent: "    ", php: php)
        XCTAssertEqual(header, "foreach ($b as $c)\ndd($c);", "No semicolon after a control header")
        let kept = await PHPRunner.format("$t = 'a $b'; $u = 'say \"hi\"'", indent: "    ", quotes: "double", php: php)
        XCTAssertEqual(kept, "$t = 'a $b';\n$u = 'say \"hi\"';", "Strings with variables or quotes inside keep their quotes")
        let single = await PHPRunner.format("$a = \"x\"", indent: "    ", quotes: "single", php: php)
        XCTAssertEqual(single, "$a = 'x';")
    }

    func testUnbalancedCodeIsLeftAsIs() async {
        let code = "if ($a) {\n  echo 1;"
        let tidy = await PHPRunner.format(code, indent: "    ", php: php)
        XCTAssertEqual(tidy, code)
    }
}

final class ClassCompleterTests: XCTestCase {
    func testWordBeforeCursorSkipsTheScopeOperator() {
        let text = "$x = User::" as NSString
        let found = ClassCompleter.word(before: text.length, in: text)
        XCTAssertEqual(found?.name, "User")
        XCTAssertEqual(found?.range, NSRange(location: 5, length: 4))
        XCTAssertNil(ClassCompleter.word(before: 5, in: "$user" as NSString), "Variables aren't classes")
        XCTAssertNil(ClassCompleter.word(before: 8, in: "App\\User" as NSString), "Qualified names are left alone")
    }

    func testUseLineGoesAfterExistingUses() {
        let (code, at) = ClassCompleter.adding(use: "App\\Models\\User", to: "use Illuminate\\Support\\Str;\nUser::all()")
        XCTAssertEqual(code, "use Illuminate\\Support\\Str;\nuse App\\Models\\User;\n\nUser::all()")
        XCTAssertEqual(at, "use Illuminate\\Support\\Str;\n".utf16.count)
        let (same, none) = ClassCompleter.adding(use: "App\\Models\\User", to: code)
        XCTAssertEqual(same, code)
        XCTAssertNil(none, "Nothing happens when the use line is already there")
    }

    func testProjectClassesAreIndexed() throws {
        let project = FileManager.default.temporaryDirectory.appending(path: "heron-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project.appending(path: "app/Models"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appending(path: "app/Services"), withIntermediateDirectories: true)
        try "<?php".write(to: project.appending(path: "app/Models/User.php"), atomically: true, encoding: .utf8)
        try "<?php".write(to: project.appending(path: "app/Services/UserSync.php"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: project) }
        let completer = ClassCompleter.index(project: project)
        XCTAssertEqual(completer.matches(for: "User").map(\.fullName), ["App\\Models\\User", "App\\Services\\UserSync"])
        XCTAssertEqual(completer.matches(for: "DB").first?.fullName, "Illuminate\\Support\\Facades\\DB")
    }
}

@MainActor
final class EditorCompletionTests: XCTestCase {
    /// Members come from PHP by reflection; needs a Laravel project (HERON_LARAVEL_PROJECT).
    func testChainFromModelToMembers() async throws {
        guard let path = ProcessInfo.processInfo.environment["HERON_LARAVEL_PROJECT"] else {
            throw XCTSkip("HERON_LARAVEL_PROJECT not set")
        }
        let engine = CompletionEngine(project: URL(filePath: path))
        let text = "use App\\Models\\User;\n$u = User::where('x', 1)->first();\n$u->" as NSString
        var result = engine.suggestions(in: text, cursor: text.length)
        for _ in 0..<40 where result == nil {   // the first calls fetch members in the background
            try await Task.sleep(for: .milliseconds(250))
            result = engine.suggestions(in: text, cursor: text.length)
        }
        let labels = try XCTUnwrap(result?.items.map(\.label))
        XCTAssertTrue(labels.contains("email"), "A User's columns are offered: \(labels.prefix(20))")
        XCTAssertTrue(labels.contains("save"), "And its methods")
        let staticText = "use App\\Models\\User;\nUser::wh" as NSString
        var statics = engine.suggestions(in: staticText, cursor: staticText.length)
        for _ in 0..<40 where statics == nil {
            try await Task.sleep(for: .milliseconds(250))
            statics = engine.suggestions(in: staticText, cursor: staticText.length)
        }
        XCTAssertTrue(statics?.items.prefix(3).map(\.label).contains("where") == true, "\(statics?.items.prefix(3).map(\.label) ?? [])")
    }

    private func editor(_ text: String) -> CodeTextView {
        let scroll = CodeTextView.scrollableTextView()
        let view = scroll.documentView as! CodeTextView
        view.completer = ClassCompleter(candidates: [
            ClassCompleter.Candidate(name: "User", fullName: "App\\Models\\User"),
            ClassCompleter.Candidate(name: "UserSync", fullName: "App\\Services\\UserSync"),
        ] + ClassCompleter.laravel)
        view.string = text
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        return view
    }

    func testTabAfterClassNameAddsTheUseLine() {
        let view = editor("$u = User::")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "use App\\Models\\User;\n\n$u = User::")
        XCTAssertEqual(view.selectedRange().location, view.string.utf16.count, "The caret stays after the code")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "use App\\Models\\User;\n\n$u = User::    ", "A second Tab just indents")
    }

    func testTabElsewhereIndents() {
        let view = editor("$user")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "$user    ")
    }

    func testEngineSuggestsClassesVariablesAndMembers() {
        let engine = CompletionEngine(project: nil)
        let text = "use App\\Models\\User;\n$user = 1;\n$use" as NSString
        let classes = engine.suggestions(in: "$x = St" as NSString, cursor: 7)
        XCTAssertEqual(classes?.items.first?.kind, .class)
        XCTAssertEqual(classes?.items.first?.label, "Str")
        XCTAssertEqual(classes?.range, NSRange(location: 5, length: 2))
        let variables = engine.suggestions(in: text, cursor: text.length)
        XCTAssertEqual(variables?.items.map(\.label), ["$user"])
        XCTAssertEqual(ClassCompleter.imports(in: text as String), ["User": "App\\Models\\User"])
        XCTAssertEqual(CompletionEngine.receiver(endingAt: 25, in: "$x = User::where()->get()" as NSString), "User::where()->get()")
        XCTAssertEqual(CompletionEngine.receiver(endingAt: 10, in: "$a = $user->name" as NSString), "$user")
    }
}

@MainActor
final class PlaceholderTests: XCTestCase {
    func testChosenMethodBringsItsRequiredParameters() {
        let scroll = CodeTextView.scrollableTextView()
        let view = scroll.documentView as! CodeTextView
        view.string = "$q->wh"
        view.setSelectedRange(NSRange(location: 6, length: 0))
        // Pretend the list is open on "wh" and the user picks where($column, $operator, $value).
        let item = CompletionItem(label: "where", insert: "where(", kind: .method, detail: "", use: nil, returns: nil,
                                  params: [.init(name: "column", optional: false), .init(name: "operator", optional: true),
                                           .init(name: "value", optional: false)])
        view.setValue(NSRange(location: 4, length: 2), forKey: "panelRangeForTests")
        view.choose(item)
        XCTAssertEqual(view.string, "$q->where($column, $value)")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 10, length: 7), "The first placeholder is selected")
        view.insertText("'email'", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "$q->where('email', $value)")
        view.insertTab(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 19, length: 6), "Tab selects the next placeholder")
        view.insertText("$e", replacementRange: view.selectedRange())
        view.insertTab(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 22, length: 0), "Then the caret lands after the )")
        XCTAssertEqual(view.string, "$q->where('email', $e)")
    }

    func testExpansionWithoutRequiredParameters() {
        let item = CompletionItem(label: "first", insert: "first()", kind: .method, detail: "", use: nil, returns: nil,
                                  params: [.init(name: "columns", optional: true)])
        XCTAssertEqual(item.expansion().text, "first()")
        XCTAssertTrue(item.expansion().placeholders.isEmpty)
    }
}

@MainActor
final class BracketPairTests: XCTestCase {
    private func editor(_ text: String) -> CodeTextView {
        let view = (CodeTextView.scrollableTextView().documentView as! CodeTextView)
        view.string = text
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        return view
    }

    func testOpeningBracketBringsItsCloser() {
        let view = editor("$a = ")
        view.insertText("(", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "$a = ()")
        XCTAssertEqual(view.selectedRange().location, 6)
        view.insertText(")", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "$a = ()", "A closer that is there is stepped over")
        XCTAssertEqual(view.selectedRange().location, 7)
    }

    func testQuotesPairAndApostrophesDoNot() {
        let view = editor("echo ")
        view.insertText("'", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "echo ''")
        let word = editor("$it = 'don")
        word.insertText("'", replacementRange: word.selectedRange())
        XCTAssertEqual(word.string, "$it = 'don'")
    }

    func testBackspaceInsideAnEmptyPairRemovesBoth() {
        let view = editor("f(")
        view.insertText(")", replacementRange: view.selectedRange())   // no pairing: the closer is typed plainly here
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "f")
    }

    func testSelectionGetsWrapped() {
        let view = editor("hello")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        view.insertText("\"", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "\"hello\"")
    }
}
