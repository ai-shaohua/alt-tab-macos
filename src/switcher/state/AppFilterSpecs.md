# AppFilter — Specs

## Summary

The switcher's app picker narrows the window list to one application. `AppFilter` decides which
windows that selection leaves visible, and which rows the picker shows while the user types an
app name. `TilesView` draws the control. Text search is a separate filter: a window is drawn only
when it passes both.

## Behavior & edge cases

- **No selection** shows every app. A selected pid shows only windows of that pid.
- **One row per pid.** Later windows of the same pid do not add another row. Cursor, iTerm2,
  Google Chrome, ChatGPT, and Sublime Text stay in that order ahead of every other row. The rest
  sort case-insensitively, and a preferred name matches case-insensitively and exactly (so
  "Google Chrome Canary" stays with the alphabetical rows). A blank name uses the caller's unnamed
  label. A repeated title gets a `" (2)"` suffix, because the popup identifies rows by title.
- **A selection whose app has left** (no remaining row with that pid) resolves to no selection.
- **Empty or whitespace query** lists every app, with All first.
- **A query** keeps rows whose titles contain it, case- and diacritic-insensitive. All stays only
  when its own title matches the query.

## Test scenarios

Mirrors `AppFilterTests.swift` 1:1.

### A. Matching a window
- **testNilSelectionShowsEveryApp** — a nil pid matches every window.
- **testSelectedPidShowsOnlyThatApp** — the selected pid matches itself and rejects another.

### B. Building the menu
- **testChoicesDedupeSortAndSuffixRepeatedNames** — one row per pid, case-insensitive sort, blank name replaced, repeated title suffixed.
- **testPreferredAppsSortAheadOfTheAlphabeticalRest** — Cursor, iTerm2, Google Chrome, ChatGPT, and Sublime Text lead, in that order; a missing preferred app leaves no gap; "cursor" still pins; "Google Chrome Canary" stays alphabetical.
- **testResolvedSelectionDropsAnAppThatLeft** — a pid still in the list is kept; a missing pid and nil become no selection.

### C. Filtering the menu by name
- **testEmptyQueryListsAllAppsFirst** — whitespace is an empty query: All, then every app.
- **testQueryKeepsNamesThatContainIt** — a substring keeps Chrome and drops Safari.
- **testQueryMatchesTheAllAppsTitleAndIgnoresDiacritics** — "all" matches the All row; "cafe" matches "Café".
