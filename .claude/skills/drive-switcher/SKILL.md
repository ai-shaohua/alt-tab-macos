---
name: drive-switcher
description: Drive AltTab's running switcher yourself to reproduce, inspect, and verify runtime bugs — no user hand-operation. Invoke the switcher, read the model-truth JSON (--qa-state), click the real UI via screenshot+cliclick, and diff "filtered out" vs "rendered off-screen". Use whenever a bug is about what the switcher shows/selects/lays out at runtime, when verifying a UI fix in the real app, or when a report says "windows disappear / wrong tiles / nothing happens".
---

# /drive-switcher — self-driven AltTab switcher debugging

## Goal

Reproduce and verify AltTab runtime/UI bugs **yourself**. Never ask the user to invoke the
switcher, click a menu, or describe what they see — the whole flow is scriptable. See the
`self-drive-app-debugging` and `alttab-qa-introspection-debugging` memories for why.

This skill is for **runtime behavior**: what the switcher shows, selects, filters, or lays out.
For building/installing see `ai/build.sh` + `ai/install.sh`; for the generic app-launch fallback
use the built-in `run` skill.

## The one rule that saves the most time

**Query the model before guessing the logic.** `--qa-state` returns the switcher's full model as
JSON. It tells apart the two failures that look identical to a user:

- **Filtered out** → window absent from `windows`, or `shown:false`. Bug is in filter/selection.
- **Rendered off-screen** → `shown:true`, a tile exists, but `tile.y` ≥ `layout.thumbnailsHeight`.
  Bug is in **layout/rendering**, not the filter.

Do this comparison first. It redirected the 2026-10 "pick Cursor → 5 windows become 3" bug from
`AppFilter` (wrong) to the multi-screen column layout (right) in one step.

## Setup

```bash
cd <repo>
APP=DerivedData/Build/Products/Debug/AltTab.app/Contents/MacOS/AltTab   # after ai/build.sh
# ...or the installed one:
# APP=/Applications/AltTab.app/Contents/MacOS/AltTab
command -v cliclick || brew install cliclick    # for clicking the real UI
```

Launch with logging to a file so you can grep the per-show tile dump:

```bash
pkill -f "AltTab.*--logs" 2>/dev/null; sleep 1
rm -f /tmp/alttab.log
"$APP" --logs=debug > /tmp/alttab.log 2>&1 &
sleep 4        # let discovery settle
```

`--logs=error` is quieter when you only need `--qa-state`. There is exactly ONE log channel
(gated by `minLevel`), so `--logs=debug` is required for `logTileDump`.

## CLI surface (CFMessagePort, from `src/events/CliEvents.swift`)

| Command | Effect |
|---|---|
| `"$APP" --show=<i>` | Open the switcher for shortcut index `i` (usually `0`) WITHOUT activating AltTab |
| `"$APP" --hide` | Close the switcher (reliable; a synthetic Esc is not) |
| `"$APP" --qa-state` | Full model as JSON — the oracle (see below) |
| `"$APP" --list` / `--detailed-list` | Window list (lighter than qa-state) |
| `"$APP" --focus=<wid>` | Focus a window by CGWindowID |

`--qa-state` key fields:
- `windows[]`: `wid, pid, app, bundleId, shown, tabbed, groupId, isGroupRepresentative,
  spaceIndexes, screenId, minimized/fullscreen/hidden/windowless, position, size`
- `tiles[]`: what is actually laid out — `index, wid, app, title, x, y, w, h, row, pointerTarget`
- `layout`: `thumbnailsWidth, thumbnailsHeight, rowCount, labelHeight`
- `screens[]`, `currentSpaceId`, `selectedIndex`, `switcherVisible`

## Triage recipe

```bash
"$APP" --show=0 2>/dev/null; sleep 0.8
"$APP" --qa-state 2>/dev/null > /tmp/qa.json
python3 - <<'PY'
import json
d=json.load(open('/tmp/qa.json'))
vh=d['layout']['thumbnailsHeight']; t=d['tiles']
shown=[w for w in d['windows'] if w['shown']]
print(f"switcherVisible={d['switcherVisible']} shown={len(shown)} tilesRendered={len(t)} viewportH={vh}")
off=[x for x in t if x['y']>=vh]
print("OFF-SCREEN tiles:", [(x['index'],x['title'][:20],int(x['y'])) for x in off] or "none")
# group a suspect app by pid to catch multi-pid / tab-group splits
PY
"$APP" --hide 2>/dev/null
```

- `shown` count ≠ `tilesRendered`, or off-screen list non-empty → **layout/rendering bug**.
- window missing / `shown:false` → **filter/selection bug** (`AppFilter`, `Windows.shouldDisplay`,
  `shouldShowTheUser`).

## Clicking the real UI (when a bug only triggers through interaction, e.g. the app-filter picker)

`screencapture` + `cliclick`, with Retina coordinate scaling (screenshot px ÷ scale = click pts):

```bash
"$APP" --show=0 2>/dev/null; sleep 0.8
screencapture -x /tmp/s.png            # Read this image to find the control
# displayed WxH vs original — divide original px by the scale shown in the Read tool, then:
cliclick c:<x_pts>,<y_pts>             # e.g. the "All apps" button
sleep 0.5; screencapture -x /tmp/s2.png
cliclick c:<row_x>,<row_y>             # e.g. a row in the dropdown
sleep 1.0
"$APP" --qa-state 2>/dev/null > /tmp/qa2.json   # verify the result in the model
```

Read the screenshot with the Read tool (it reports "original WxH, displayed at wxh, multiply by N")
— map clicks as `original_px / N`.

## Per-show tile dump (deeper tracing)

With `--logs=debug`, every show emits `logTileDump` (`Windows.swift`). Grep `show[`:

```bash
grep -E "show\[" /tmp/alttab.log | tail -3
```

Per tile: `*`=selected, `+`shown/`-`hidden, `app#wid`, flags (`t`abbed `p`hantom `f`ullscreen
`h`eld `w`indowless `F`ocused), size, `sp[spaceIds]`. `surface accepted (pid:… bundle)` lines map
each wid→pid — use them to catch an app whose windows span multiple pids or tab groups.

## Verifying a fix end-to-end

After `ai/build.sh`, run the debug binary, reproduce the exact gesture, and assert in the model —
don't eyeball only:

```bash
python3 -c "import json;d=json.load(open('/tmp/qa2.json'));vh=d['layout']['thumbnailsHeight'];t=d['tiles'];
assert all(x['y']<vh for x in t), 'tiles still off-screen';print('PASS',len(t),'tiles all on-screen')"
```

Then `ai/install.sh` to promote the fix to `/Applications`.

## Cleanup

```bash
rm -f /tmp/alttab.log /tmp/qa*.json /tmp/s*.png
pkill -f "AltTab.*--logs" 2>/dev/null
```
