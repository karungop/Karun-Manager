import XCTest

/// Drives the real app in the simulator: add (with a category prefix and a queue), complete by tapping
/// and by swiping, undo, and delete. Runs against a throwaway store (`--in-memory`).
@MainActor
final class KarunManagerMobileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--in-memory"]
        app.launch()
    }

    func testStartsEmpty() {
        XCTAssertTrue(app.staticTexts["All clear"].waitForExistence(timeout: 5))
    }

    func testAddUsesPrefixCategoryAndChosenQueue() {
        app.buttons["Urgent"].tap()
        add("buy: oat milk")
        XCTAssertTrue(app.staticTexts["oat milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["#things-to-buy"].exists, "the buy: prefix picks Things to buy")
        XCTAssertTrue(app.staticTexts["Up next"].exists, "the only open task is up next")
        XCTAssertFalse(app.staticTexts["All clear"].exists)
    }

    func testCompleteWithCheckboxThenUndo() {
        add("Renew passport")
        XCTAssertTrue(app.staticTexts["Renew passport"].waitForExistence(timeout: 5))
        app.buttons["Complete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Renew passport"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Completed “Renew passport”"].exists)

        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Renew passport"].waitForExistence(timeout: 5))
    }

    func testSwipeRightCompletesAndSwipeLeftDeletes() {
        add("Call Mom")
        add("Water plants")
        let call = app.staticTexts["Call Mom"]
        XCTAssertTrue(call.waitForExistence(timeout: 5))

        // A short swipe reveals the action button; a long one triggers it. Handle both.
        call.swipeRight()
        let done = app.collectionViews.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(call.waitForNonExistence(timeout: 5))

        let plants = app.staticTexts["Water plants"]
        plants.swipeLeft()
        let delete = app.collectionViews.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        XCTAssertTrue(plants.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deleted “Water plants”"].exists)

        app.buttons["Undo"].tap()
        XCTAssertTrue(plants.waitForExistence(timeout: 5))
    }

    private func add(_ text: String) {
        let field = app.textFields["Add a task…"]
        if !field.hasKeyboardFocus { field.tap() }
        field.typeText(text + "\n")
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}
