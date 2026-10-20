import XCTest

/// The app picker's pure decisions: which windows a selected app leaves visible, how the menu rows
/// are built, and how a typed name narrows them. `TilesView` draws the control and applies the pid.
final class AppFilterTests: XCTestCase {

    // MARK: - A. Matching a window

    func testNilSelectionShowsEveryApp() {
        XCTAssertTrue(AppFilter.matches(windowPid: 1, selectedPid: nil))
        XCTAssertTrue(AppFilter.matches(windowPid: 2, selectedPid: nil))
    }

    func testSelectedPidShowsOnlyThatApp() {
        XCTAssertTrue(AppFilter.matches(windowPid: 4, selectedPid: 4))
        XCTAssertFalse(AppFilter.matches(windowPid: 5, selectedPid: 4))
    }

    // MARK: - B. Building the menu

    func testChoicesDedupeSortAndSuffixRepeatedNames() {
        let choices = AppFilter.choices([
            (pid: 3, name: "Zoom"),
            (pid: 1, name: "Safari"),
            (pid: 1, name: "ignored duplicate pid"),
            (pid: 2, name: "Safari"),
            (pid: 5, name: "chrome"),
            (pid: 4, name: "  "),
        ], unnamed: "App")
        XCTAssertEqual(choices.map { $0.pid }, [4, 5, 1, 2, 3])
        XCTAssertEqual(choices.map { $0.title }, ["App", "chrome", "Safari", "Safari (2)", "Zoom"])
    }

    func testPreferredAppsSortAheadOfTheAlphabeticalRest() {
        let choices = AppFilter.choices([
            (pid: 1, name: "Zoom"),
            (pid: 2, name: "Sublime Text"),
            (pid: 3, name: "Safari"),
            (pid: 4, name: "ChatGPT"),
            (pid: 5, name: "Google Chrome"),
            (pid: 6, name: "iTerm2"),
            (pid: 7, name: "cursor"),
            (pid: 8, name: "Finder"),
            (pid: 9, name: "Google Chrome Canary"),
        ])
        XCTAssertEqual(choices.map { $0.title }, [
            "cursor", "iTerm2", "Google Chrome", "ChatGPT", "Sublime Text",
            "Finder", "Google Chrome Canary", "Safari", "Zoom",
        ])
    }

    func testResolvedSelectionDropsAnAppThatLeft() {
        let choices = [AppFilterChoice(pid: 1, title: "Safari")]
        XCTAssertEqual(AppFilter.resolvedSelection(1, choices: choices), 1)
        XCTAssertNil(AppFilter.resolvedSelection(9, choices: choices))
        XCTAssertNil(AppFilter.resolvedSelection(nil, choices: choices))
    }

    // MARK: - C. Filtering the menu by name

    func testEmptyQueryListsAllAppsFirst() {
        let choices = [AppFilterChoice(pid: 2, title: "Mail"), AppFilterChoice(pid: 1, title: "Safari")]
        XCTAssertEqual(AppFilter.rows(choices: choices, query: "   ", allTitle: "All apps"),
            [.all, .app(choices[0]), .app(choices[1])])
    }

    func testQueryKeepsNamesThatContainIt() {
        let safari = AppFilterChoice(pid: 1, title: "Safari")
        let chrome = AppFilterChoice(pid: 2, title: "Google Chrome")
        XCTAssertEqual(AppFilter.rows(choices: [safari, chrome], query: "chrom", allTitle: "All apps"),
            [.app(chrome)])
    }

    func testQueryMatchesTheAllAppsTitleAndIgnoresDiacritics() {
        let cafe = AppFilterChoice(pid: 1, title: "Café")
        XCTAssertEqual(AppFilter.rows(choices: [cafe], query: "all", allTitle: "All apps"), [.all])
        XCTAssertEqual(AppFilter.rows(choices: [cafe], query: "cafe", allTitle: "All apps"), [.app(cafe)])
    }
}
