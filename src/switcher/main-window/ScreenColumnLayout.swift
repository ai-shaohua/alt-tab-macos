import Foundation

/// The switcher's per-screen columns, as arithmetic. One column per display, left to right as the
/// displays sit on the desk, each column a grid of that screen's tiles under a header. `TilesView`
/// measures tiles and assigns frames; this decides which column a tile belongs to, where it sits,
/// and which column a drop lands on.
enum ScreenColumnLayout {
    static let headerHeight = CGFloat(26)
    static let columnGap = CGFloat(8)
    /// A press that moves less than this stays a click (focus the window). Past it, the press is a
    /// drag onto another screen's column.
    static let dragThreshold = CGFloat(5)

    struct Screen: Equatable {
        var id: String
        var name: String
        /// Cocoa coordinates: `originX` grows right, `originY` grows up.
        var originX: CGFloat
        var originY: CGFloat
    }

    struct ColumnInput {
        var name: String
        var tileIndexes: [Int]
        var tileWidths: [CGFloat]
    }

    struct Input {
        var columns: [ColumnInput]
        var tileHeight: CGFloat
        var padding: CGFloat
        var headerHeight: CGFloat
        var columnGap: CGFloat
        var columnWidthMax: CGFloat
    }

    struct PlacedColumn: Equatable {
        var name: String
        var frame: CGRect
        var headerFrame: CGRect
    }

    struct Result: Equatable {
        var origins: [Int: CGPoint]
        var widths: [Int: CGFloat]
        var columns: [PlacedColumn]
        var rows: [[Int]]
        var maxX: CGFloat
        var maxY: CGFloat
    }

    static func usesColumns(screenCount: Int, showsAllScreens: Bool) -> Bool {
        screenCount >= 2 && showsAllScreens
    }

    /// Left to right, then top to bottom. Column order follows the display arrangement, not the
    /// writing direction, so the left column is the left screen.
    static func ordered(_ screens: [Screen]) -> [Screen] {
        screens.sorted { a, b in
            if a.originX != b.originX { return a.originX < b.originX }
            return a.originY > b.originY
        }
    }

    /// Identical names get a trailing number so two displays macOS calls the same thing stay distinct.
    static func displayNames(_ names: [String]) -> [String] {
        var counts = [String: Int]()
        for name in names { counts[name, default: 0] += 1 }
        var seen = [String: Int]()
        return names.map { name in
            guard counts[name, default: 0] > 1 else { return name }
            let number = seen[name, default: 0] + 1
            seen[name] = number
            return "\(name) \(number)"
        }
    }

    /// Tiles whose screen id is missing or unknown join the first screen, so they stay on a column
    /// and can still be dragged.
    static func groups(tileScreenIds: [String?], screens: [Screen]) -> [[Int]] {
        let order = ordered(screens)
        guard !order.isEmpty else { return [Array(tileScreenIds.indices)] }
        var buckets = Array(repeating: [Int](), count: order.count)
        let indexById = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.id, $0) })
        for (index, id) in tileScreenIds.enumerated() {
            buckets[id.flatMap { indexById[$0] } ?? 0].append(index)
        }
        return buckets
    }

    static func columnWidthMax(panelWidthMax: CGFloat, columnCount: Int, columnGap: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return panelWidthMax }
        let gaps = columnGap * CGFloat(columnCount - 1)
        return max(0, ((panelWidthMax - gaps) / CGFloat(columnCount)).rounded(.down))
    }

    static func compute(_ input: Input) -> Result {
        var origins = [Int: CGPoint]()
        var widths = [Int: CGFloat]()
        var placed = [(index: Int, origin: CGPoint)]()
        var columns = [PlacedColumn]()
        var x = CGFloat(0)
        var maxY = CGFloat(0)
        for (position, column) in input.columns.enumerated() {
            let pairs = Array(zip(column.tileIndexes, column.tileWidths))
            let fitted = pairs.map { fittedWidth($0.1, input) }
            let grid = TileGridLayout.compute(TileGridLayout.Input(widths: fitted, tileHeight: input.tileHeight,
                widthMax: input.columnWidthMax, padding: input.padding, isLeftToRight: true))
            let offsets = TileGridLayout.centeringOffsets(rowWidths: grid.rows.map { row in row.map { fitted[$0] } },
                padding: input.padding, within: input.columnWidthMax)
            var rowOfLocal = [Int](repeating: 0, count: fitted.count)
            for (rowIndex, row) in grid.rows.enumerated() {
                for local in row { rowOfLocal[local] = rowIndex }
            }
            for (local, pair) in pairs.enumerated() {
                guard local < grid.origins.count, local < rowOfLocal.count else { continue }
                let origin = CGPoint(x: x + grid.origins[local].x + offsets[rowOfLocal[local]],
                    y: input.headerHeight + grid.origins[local].y)
                origins[pair.0] = origin
                widths[pair.0] = fitted[local]
                placed.append((pair.0, origin))
            }
            let height = input.headerHeight + grid.maxY
            columns.append(PlacedColumn(
                name: column.name,
                frame: CGRect(x: x, y: 0, width: input.columnWidthMax, height: height),
                headerFrame: CGRect(x: x, y: 0, width: input.columnWidthMax, height: input.headerHeight)))
            maxY = max(maxY, height)
            x += input.columnWidthMax
            if position < input.columns.count - 1 { x += input.columnGap }
        }
        for index in columns.indices { columns[index].frame.size.height = maxY }
        return Result(origins: origins, widths: widths, columns: columns, rows: rows(placed), maxX: x, maxY: maxY)
    }

    static func crossedDragThreshold(from down: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - down.x, current.y - down.y) >= dragThreshold
    }

    /// A point inside a column hits that column. A point in the gap between columns hits the nearest
    /// one, so a drop on the divider still lands. Outside the columns' bounding box is not a drop.
    static func dropIndex(at point: CGPoint, columns: [CGRect]) -> Int? {
        guard !columns.isEmpty else { return nil }
        if let direct = columns.firstIndex(where: { $0.contains(point) }) { return direct }
        let bounds = columns.reduce(columns[0]) { $0.union($1) }
        guard bounds.contains(point) else { return nil }
        return columns.enumerated().min { lhs, rhs in
            let left = abs(lhs.element.midX - point.x)
            let right = abs(rhs.element.midX - point.x)
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }?.offset
    }

    /// A tile wider than the column is narrowed to fit. `TileGridLayout` wraps a too-wide first tile
    /// onto the next row and leaves `maxX` at 0 (`testSingleTileWiderThanTheGrid`); a column cannot
    /// use that result to size itself.
    private static func fittedWidth(_ width: CGFloat, _ input: Input) -> CGFloat {
        let limit = input.columnWidthMax - 2 * input.padding
        guard limit > 0 else { return 0 }
        return min(max(0, width), limit)
    }

    private static func rows(_ placed: [(index: Int, origin: CGPoint)]) -> [[Int]] {
        guard !placed.isEmpty else { return [[]] }
        var bands = [CGFloat: [(CGFloat, Int)]]()
        for tile in placed { bands[tile.origin.y.rounded(), default: []].append((tile.origin.x, tile.index)) }
        return bands.keys.sorted().map { y in bands[y]!.sorted { $0.0 < $1.0 }.map { $0.1 } }
    }
}
