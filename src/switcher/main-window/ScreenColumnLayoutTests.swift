import XCTest

/// Pins the per-screen column arithmetic: which displays become columns, which tiles land in each,
/// where a tile sits under its header, and which column a drop hits. Pure numbers in, numbers out.
///
/// Groups: A when columns are used · B order and names · C assignment · D placement · E drag.
final class ScreenColumnLayoutTests: XCTestCase {
    private func screen(_ id: String, _ name: String, _ x: CGFloat, _ y: CGFloat) -> ScreenColumnLayout.Screen {
        ScreenColumnLayout.Screen(id: id, name: name, originX: x, originY: y)
    }

    private func layout(_ columns: [ScreenColumnLayout.ColumnInput], columnWidth: CGFloat = 100,
                        header: CGFloat = 20, gap: CGFloat = 10) -> ScreenColumnLayout.Result {
        ScreenColumnLayout.compute(ScreenColumnLayout.Input(columns: columns, tileHeight: 50, padding: 5,
            headerHeight: header, columnGap: gap, columnWidthMax: columnWidth))
    }

    // MARK: - A. When columns are used

    func testColumnsNeedTwoScreensShowingAll() {
        XCTAssertFalse(ScreenColumnLayout.usesColumns(screenCount: 1, showsAllScreens: true))
        XCTAssertFalse(ScreenColumnLayout.usesColumns(screenCount: 2, showsAllScreens: false))
        XCTAssertTrue(ScreenColumnLayout.usesColumns(screenCount: 2, showsAllScreens: true))
        XCTAssertTrue(ScreenColumnLayout.usesColumns(screenCount: 3, showsAllScreens: true))
    }

    func testColumnWidthSplitsThePanelAndDropsTheGap() {
        XCTAssertEqual(ScreenColumnLayout.columnWidthMax(panelWidthMax: 320, columnCount: 2, columnGap: 8), 156)
        XCTAssertEqual(ScreenColumnLayout.columnWidthMax(panelWidthMax: 100, columnCount: 3, columnGap: 8), 28)
    }

    // MARK: - B. Order and names

    func testScreensOrderLeftToRightThenTopToBottom() {
        let ordered = ScreenColumnLayout.ordered([
            screen("right", "Right", 100, 0),
            screen("low", "Low", 0, 0),
            screen("high", "High", 0, 500),
        ])
        XCTAssertEqual(ordered.map { $0.id }, ["high", "low", "right"])
    }

    func testDuplicateNamesAreNumbered() {
        XCTAssertEqual(ScreenColumnLayout.displayNames(["DELL", "LG", "DELL"]), ["DELL 1", "LG", "DELL 2"])
        XCTAssertEqual(ScreenColumnLayout.displayNames(["Built-in", "LG"]), ["Built-in", "LG"])
    }

    // MARK: - C. Assignment

    func testTilesKeepTheirOrderInsideTheMatchingColumn() {
        let screens = [screen("a", "A", 0, 0), screen("b", "B", 100, 0)]
        let groups = ScreenColumnLayout.groups(tileScreenIds: ["b", nil, "a", "missing"], screens: screens)
        XCTAssertEqual(groups, [[1, 2, 3], [0]])
    }

    // MARK: - D. Placement

    func testTilesSitUnderTheHeaderAndTheSecondColumnStartsAfterTheGap() {
        let result = layout([
            ScreenColumnLayout.ColumnInput(name: "Left", tileIndexes: [0], tileWidths: [40]),
            ScreenColumnLayout.ColumnInput(name: "Right", tileIndexes: [3], tileWidths: [40]),
        ])
        XCTAssertEqual(result.origins[0], CGPoint(x: 30, y: 25))
        XCTAssertEqual(result.origins[3], CGPoint(x: 140, y: 25))
        XCTAssertEqual(result.widths[0], 40)
        XCTAssertEqual(result.columns.map { $0.frame }, [
            CGRect(x: 0, y: 0, width: 100, height: 80),
            CGRect(x: 110, y: 0, width: 100, height: 80),
        ])
        XCTAssertEqual(result.columns.map { $0.headerFrame }, [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 110, y: 0, width: 100, height: 20),
        ])
        XCTAssertEqual(result.rows, [[0, 3]])
        XCTAssertEqual(result.maxX, 210)
        XCTAssertEqual(result.maxY, 80)
    }

    func testATileWiderThanTheColumnIsNarrowedOntoTheFirstRow() {
        let result = layout([ScreenColumnLayout.ColumnInput(name: "Only", tileIndexes: [0], tileWidths: [200])])
        XCTAssertEqual(result.widths[0], 90)
        XCTAssertEqual(result.origins[0], CGPoint(x: 5, y: 25))
        XCTAssertEqual(result.maxX, 100)
    }

    func testAnEmptyColumnStillOccupiesItsWidth() {
        let result = layout([
            ScreenColumnLayout.ColumnInput(name: "Full", tileIndexes: [0], tileWidths: [40]),
            ScreenColumnLayout.ColumnInput(name: "Empty", tileIndexes: [], tileWidths: []),
        ])
        XCTAssertEqual(result.columns[1].name, "Empty")
        XCTAssertEqual(result.columns[1].frame, CGRect(x: 110, y: 0, width: 100, height: 80))
        XCTAssertEqual(result.rows, [[0]])
    }

    // MARK: - F. Joining results back to window indices

    func testPlacementsJoinByPositionNotWindowIndex() {
        // Two displays, tiles whose window indices (13,14,15 and 20) are nothing like their positions
        // (0,1,2 and 3) — the shape a filter produces. Placements must come back keyed to the window
        // indices, each at the origin computed for its position.
        let result = layout([
            ScreenColumnLayout.ColumnInput(name: "Left", tileIndexes: [0, 1, 2], tileWidths: [40, 40, 40]),
            ScreenColumnLayout.ColumnInput(name: "Right", tileIndexes: [3], tileWidths: [40]),
        ])
        let placements = ScreenColumnLayout.placements(result, windowIndexByPosition: [13, 14, 15, 20])
        XCTAssertEqual(placements.map { $0.windowIndex }, [13, 14, 15, 20])
        XCTAssertEqual(placements.map { $0.origin }, [0, 1, 2, 3].map { result.origins[$0] })
        XCTAssertEqual(placements.map { $0.width }, [40, 40, 40, 40])
    }

    func testRowsMapPositionsToWindowIndices() {
        // A narrow column wraps its second tile onto a new band; the other screen's tile shares the first.
        let result = layout([
            ScreenColumnLayout.ColumnInput(name: "Left", tileIndexes: [0, 1], tileWidths: [80, 80]),
            ScreenColumnLayout.ColumnInput(name: "Right", tileIndexes: [2], tileWidths: [80]),
        ])
        // Position rows → window-index rows, order preserved.
        XCTAssertEqual(result.rows, [[0, 2], [1]])
        XCTAssertEqual(ScreenColumnLayout.rowsByWindowIndex(result, windowIndexByPosition: [13, 14, 20]), [[13, 20], [14]])
    }

    // MARK: - E. Drag

    func testFivePointsIsADragAndLessIsAClick() {
        XCTAssertTrue(ScreenColumnLayout.crossedDragThreshold(from: .zero, to: CGPoint(x: 3, y: 4)))
        XCTAssertFalse(ScreenColumnLayout.crossedDragThreshold(from: .zero, to: CGPoint(x: 2, y: 2)))
    }

    func testDropHitsTheColumnTheGapAndNothingOutside() {
        let columns = [CGRect(x: 0, y: 0, width: 100, height: 80), CGRect(x: 110, y: 0, width: 100, height: 80)]
        XCTAssertEqual(ScreenColumnLayout.dropIndex(at: CGPoint(x: 10, y: 10), columns: columns), 0)
        XCTAssertEqual(ScreenColumnLayout.dropIndex(at: CGPoint(x: 150, y: 10), columns: columns), 1)
        XCTAssertEqual(ScreenColumnLayout.dropIndex(at: CGPoint(x: 108, y: 10), columns: columns), 1)
        XCTAssertNil(ScreenColumnLayout.dropIndex(at: CGPoint(x: 400, y: 10), columns: columns))
        XCTAssertNil(ScreenColumnLayout.dropIndex(at: CGPoint(x: 10, y: 200), columns: columns))
    }
}
