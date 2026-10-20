# ScreenColumnLayout — Specs

## Summary

When two or more displays are connected and the shortcut shows windows from all screens, the switcher
lays tiles out in one column per display instead of a single grid. Columns run left to right in the
same order as the displays on the desk. Each column has the screen's name in a header and that
screen's windows underneath, most recently used first.

A press that stays within 5 points is a click and focuses the window. A press that moves farther is
a drag: releasing over another column moves the window onto that screen. Releasing over the same
column, or outside the columns, puts the tile back.

`ScreenColumnLayout` is that placement and the drop hit-test as arithmetic. `TilesView` measures
tiles, assigns frames, and draws the headers (`ScreenColumnChrome`). `WindowScreenMove` decides the
on-screen frame and the Accessibility steps; `Window.moveToScreen` performs them.

### Names

The header is `NSScreen.localizedName`, drawn in a band above that column's thumbnails, and read from the displays attached when the switcher is shown.
Two displays that share a name are numbered in column order (`DELL 1`, `DELL 2`). A display with an
empty name uses the localized fallback "Screen". Column order follows `CGDisplayBounds`, the
displays' current place on the desk.

### Coordinates

The document view is flipped, so y grows downward. Column frames include the header and stretch to
the height of the tallest column, so the empty area under a short column is still a drop target.

## Behavior & edge cases

- **Columns are off for a single display, and off when the shortcut shows only the screen AltTab is
  on.** There is nowhere to drag to, and windows from the other screens are not in the list.
- **Unknown-screen tiles join the first column.** A window with no resolved screen stays visible and
  draggable.
- **A tile wider than its column is narrowed to fit on the first row.** `TileGridLayout` wraps a
  first tile that is wider than the grid onto the next row and leaves `maxX` at 0; a column sized
  from that would collapse. `TileView.screenColumnWidthCap` narrows the cell before it is measured,
  and the layout clamps again so the two agree.
- **An empty column keeps its width and header.** A screen with no windows is still a drop target.
- **A drop inside a column hits that column.** A drop in the gap hits the nearest column. A drop
  outside the columns' bounding box is not a drop.
- **Rows for the arrow keys are horizontal bands of equal y**, so up and down stay on the tile
  closest in x on the next band.
- **Results join back to tiles by position, not by window index.** `compute` keys its origins, widths
  and rows by the positions it was handed (`ColumnInput.tileIndexes`), which are positions into the
  laid-out tile array. The caller resolves them back through the tiles' window indices in the same
  order. These two index spaces are equal only when nothing is filtered; an app or search filter makes
  them diverge, and joining on window index then places nothing — tiles keep stale origins and render
  off-screen.

---

## Test scenarios

Mirrors `ScreenColumnLayoutTests.swift` 1:1.

### A. When columns are used
- **testColumnsNeedTwoScreensShowingAll** — one screen, or a shortcut that shows only AltTab's screen, stays a single grid. Two or more screens showing all windows use columns.
- **testColumnWidthSplitsThePanelAndDropsTheGap** — each column's width is the panel width minus the gaps, split evenly, rounded down.

### B. Order and names
- **testScreensOrderLeftToRightThenTopToBottom** — equal x orders the higher Cocoa y (the upper display) first.
- **testDuplicateNamesAreNumbered** — a repeated name gains a trailing number; unique names are unchanged.

### C. Assignment
- **testTilesKeepTheirOrderInsideTheMatchingColumn** — tiles stay in list order inside their screen. A missing or unknown screen id joins the first column.

### D. Placement
- **testTilesSitUnderTheHeaderAndTheSecondColumnStartsAfterTheGap** — a tile is centered in its column, below the header. The next column starts one gap past the first. Both columns are as tall as the taller one. The two tiles share a keyboard row.
- **testATileWiderThanTheColumnIsNarrowedOntoTheFirstRow** — a 200-point tile in a 100-point column is placed at 90 points wide on the first row.
- **testAnEmptyColumnStillOccupiesItsWidth** — a column with no tiles still has a frame and a header.

### E. Drag
- **testFivePointsIsADragAndLessIsAClick** — a 3-4-5 move crosses the threshold; a 2-2 move does not.
- **testDropHitsTheColumnTheGapAndNothingOutside** — inside a column, in the gap (nearest), and outside the bounding box.

### F. Joining results back to window indices
- **testPlacementsJoinByPositionNotWindowIndex** — positions (0,1,2,3) resolve to their window indices (13,14,15,20), each at the origin computed for its position; joining on window index would miss.
- **testRowsMapPositionsToWindowIndices** — position-keyed keyboard rows become window-index rows in the same order.
