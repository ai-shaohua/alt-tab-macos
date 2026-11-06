# Limitation: dragging a native-fullscreen window onto a display mounted *above* the main one

Status: known macOS limitation, **no reliable fix found**. This note records the investigation so it
is not re-done from scratch. Related code: `WindowScreenMove.swift` (geometry + steps) and
`Window.moveToScreen` / `moveAxWindow` / `scheduleAxStep` / `joinDisplaySpace` (the shell that writes
the move through Accessibility). Behavior spec: `WindowScreenMoveSpecs.md`.

## Symptom

Dropping a tile on another screen's column moves that window to that display. This **intermittently
fails** for one specific combination:

- the window is in **native macOS fullscreen** (e.g. Chrome's real fullscreen — *not* a merely
  maximized window like VS Code / Cursor), **and**
- the target display is mounted **above** the main display in the arrangement.

The same drag sometimes works and sometimes does nothing — **including on the very first attempt**.
The tile appears to move in the panel (optimistic UI), but the real window stays on the source
display.

## What works vs. what doesn't

| Case | Result |
|---|---|
| any window → the **main** display (e.g. secondary→built-in) | ✅ reliable |
| **maximized** / non-native-fullscreen window, any direction | ✅ reliable |
| **native-fullscreen** window → secondary display **above** the main | ❌ intermittent |

## Why only this combination

Moving a fullscreen window runs three Accessibility steps:
`exitFullscreen → setPosition → enterFullscreen` (see `WindowScreenMove.steps`). The `setPosition`
step is where it breaks.

- A display mounted **above** the main one occupies **negative Quartz Y** (any point above the main
  display's top edge is negative; the main display's top-left is the origin `(0,0)`, Y grows down).
- A move onto the **main** display is a **positive**-Y write and is never refused — that is why the
  secondary→main direction always works.
- A **maximized** window never runs exit/enter, so its position write is never issued in the fragile
  post-fullscreen moment — that is why Cursor-style windows always work.

## What "clamp" means (the actual failure)

AltTab asks macOS to set the window's top-left to, e.g., `(x=747, y=-958)` (on the display above).
The window server may **override that coordinate to keep the window in what it considers a valid
area** — it keeps the `x` (747) but forces the `y` back to ~`33`, which is on the source (built-in)
display. So the window lands at `(747, 33)` — still on the source — instead of `(747, -958)` on the
target. That override is the "clamp". `enterFullscreen` then re-captures the source screen, and the
move silently does nothing. When the write is *not* clamped, the window lands on the target and the
move succeeds.

AltTab issues the **identical** call every time; the difference is entirely in how macOS responds to
it — accept the negative Y (success) or clamp it (failure). Re-issuing the same call within one move
does not flip the decision.

## What was ruled out — it is NOT a Spaces problem

An earlier version of this writeup blamed the window being stranded on the primary Space (`id 1`),
which `SLSMoveWindowsToManagedSpace` refuses to relocate. **That was wrong.** A single measured trace
disproves it:

```
MOVE SUCCEEDED → window on target display [747, -958]
postExitSpaces=[1]   afterJoin=[1]      # window was on Space 1; the Space-join FAILED
```

The window was on Space 1, the Space-join failed (it stayed on Space 1), **and the move still
succeeded**. The failing moves *also* had the window on Space 1. So:

- joining the target display's Space is **neither required** (a move succeeded without it) **nor
  sufficient**, and
- Space 1 is **not** the differentiator.

The only thing that varied between success and failure was whether the negative-Y position write
stuck.

## The honest unknown: why it's intermittent

There is **no proven mechanism** for the intermittency, and this note deliberately does not invent a
third confident theory after the Spaces one was wrong. What the data supports:

- It only occurs in the brief period right after a fullscreen exit (hence native-fullscreen-only).
- The natural hypothesis "the exit animation hasn't finished — a timing race" does **not** fully fit:
  retrying the write repeatedly over ~4 seconds kept it clamped, long after any animation should be
  done. So "wait longer / retry" is not a fix.
- Whatever state macOS establishes at each `exitFullscreen` appears to decide whether that **entire**
  attempt is clampable, and it is fixed for that attempt; a fresh drag does a fresh exit and
  effectively rolls the dice again (so a later drag can succeed where the previous failed, and vice
  versa).

What exactly differs between a "good" exit and a "bad" one could not be determined from the
Accessibility / window-server APIs available.

## Approaches tried (none reliable)

- **Verify-and-retry** the position write — once a move's write is clamped it stays clamped for that
  attempt; retrying within the move does not recover.
- **Join / hop / force the target Space**, and **dismiss the switcher first** (so it stops holding
  its Space current) — irrelevant, because the Space is not the cause.
- **Synthesize a native title-bar drag** (the OS's own move path) — too fragile: the draggable
  title-bar region differs per app (e.g. Chrome's top is tabs, not a grab-anywhere title bar), and
  the window must be visible first.

Also note: Chrome's `CGWindowID` **changes across fullscreen toggles**, so nothing can cache the id
across the exit→enter sequence.

## If revisited

The only lever that could make this *predictable* (not reliable) would be a product-level fallback:
detect that a fullscreen move did not land on the target display and surface it (leave the window
fullscreen where it is + beep) instead of silently doing nothing. That changes behavior and was not
implemented. If a future macOS stops clamping the negative-Y write (or exposes a supported
"move window to display" API), revisit the fullscreen steps in `Window.scheduleAxStep`.
