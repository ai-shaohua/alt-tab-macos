# WindowScreenMove — Specs

## Summary

Dropping a tile on another screen's column moves that window onto the target display. The landing
position keeps the window's relative place on its old screen, clamped so it stays inside the
target's visible frame. The shell writes that position through Accessibility.

A normal window is one position write. A minimized window is restored first, because it has no
on-screen frame. A native-fullscreen window is a Space of its own: a position write does not move
that Space, so the steps are leave fullscreen, move, enter fullscreen on the screen that now holds
the window. Each animated step waits one second before the next, the same gap `Window.minDemin`
uses before minimizing a window that is leaving fullscreen. AX ignores a position write and a
fullscreen enter during that animation.

## Behavior & edge cases

- **Quartz y is flipped against the primary display's Cocoa top.** AX position is the window's
  top-left with y growing down. `cocoaOrigin` is the inverse, for AltTab's own `NSWindow`s.
- **No source frame pins the window to the target's top-left.** A window larger than the target on
  one axis pins to the target's origin on that axis.
- **The shell joins the target display's current Space before writing the position.** A position
  write stays on the display that owns the window's Space, so the move puts the window on that
  Space first. The target rect is the display's current bounds when the `NSScreen` still describes
  a previous arrangement.
- **Minimized and fullscreen compose.** A minimized fullscreen window is restored, leaves
  fullscreen, moves, then enters fullscreen.

## Known limitation — native-fullscreen onto a non-main display mounted above the main one

A **native-fullscreen** window (e.g. Chrome in real macOS fullscreen — not a merely maximized window
like VS Code/Cursor) **intermittently** fails to drag onto a secondary display mounted **above** the
main one: right after the fullscreen exit, the window server sometimes clamps the negative-Quartz-y
position write back onto the source display. It is a macOS behavior, not fixable from here, and it is
**not** a Spaces issue. Full investigation, measurements, and the approaches tried (and why the
earlier "Space 1" explanation was wrong) are in `FullscreenCrossDisplayMoveLimitation.md`.

---

## Test scenarios

Mirrors `WindowScreenMoveTests.swift` 1:1.

### A. Coordinates
- **testQuartzFrameFlipsYAgainstThePrimaryTop** — a screen at Cocoa `(1920, 0, 800×600)` with a primary top of 1080 has Quartz origin `(1920, 480)`.
- **testCocoaOriginIsTheInverseOfTheQuartzTopLeft** — converting that Quartz top-left back, for a 600-point-tall window, returns Cocoa `(1920, 0)`.

### B. Landing position
- **testRelativePositionIsKeptOnADifferentlySizedScreen** — a window a quarter across and a quarter down lands a quarter across and a quarter down the target.
- **testAWindowWiderThanTheTargetPinsToItsTopLeft** — a window wider than the target keeps its y and pins x to the target origin.
- **testNoSourceFramePinsToTheTargetOrigin** — a nil origin and a nil source frame land on the target's origin.

### C. Steps
- **testAnOrdinaryWindowIsOnlyRepositioned**
- **testAMinimizedWindowIsRestoredBeforeTheMove**
- **testAFullscreenWindowLeavesMovesAndReenters**
- **testAMinimizedFullscreenWindowRestoresThenLeaves**
- **testAnimatedStepsWaitAndTheLastFullscreenEnterDoesNot** — deminiaturize, exit fullscreen, and the position write each pause one second. Entering fullscreen is the last step and does not.
