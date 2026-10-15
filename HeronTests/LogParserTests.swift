import XCTest
@testable import Heron

final class LogParserTests: XCTestCase {
    private let sample = """
    [2026-10-15 10:00:01] local.INFO: A new user created an account {"id":5}
    [2026-10-15 10:02:30] local.ERROR: Call to a member function name() on null {"exception":"[object] (Error(code: 0): Call to a member function name() on null at /app/app/Http/Controllers/HomeController.php:12)
    [stacktrace]
    #0 /app/vendor/laravel/framework/src/Illuminate/Routing/Controller.php(54): App\\\\Http\\\\Controllers\\\\HomeController->index()
    #1 {main}
    "}
    [2026-10-15 10:03:00] production.DEBUG: tick []
    """

    func testRecordsAreNewestFirstWithTheirTrace() {
        let entries = LogParser.parse(sample)
        XCTAssertEqual(entries.map(\.level), ["DEBUG", "ERROR", "INFO"])
        XCTAssertEqual(entries[0].environment, "production")
        XCTAssertEqual(entries[0].summary, "tick")
        let error = entries[1]
        XCTAssertEqual(error.time, "2026-10-15 10:02:30")
        XCTAssertEqual(error.summary, "Call to a member function name() on null")
        XCTAssertTrue(error.body.contains("#1 {main}"))
        XCTAssertEqual(entries[2].summary, "A new user created an account")
    }

    func testEmptyAndForeignTextGiveNothing() {
        XCTAssertTrue(LogParser.parse("").isEmpty)
        XCTAssertTrue(LogParser.parse("just a line\nanother").isEmpty)
    }
}
