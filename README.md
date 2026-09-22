# homerowless

Keyboard-driven macOS UI navigation, open source. Press a hotkey, every clickable element gets a label, type the label to click it. A maintained replacement for the archived Vimac and the closed-source Homerow.

- **Cmd-Shift-F** click mode: hints on every actionable element in the front window. Hold Shift/Cmd/Option while typing the label for a modifier click.
- **Cmd-J** scroll mode: `hjkl` scroll, `d`/`u` half page, `gg`/`G` top/bottom, Esc exits.

## Privacy

homerowless needs only **Accessibility**. All geometry comes from the Accessibility API; the app never captures the screen or reads pixels, and it consumes keystrokes only while hints are visible. Input Monitoring is not required.

## Install

```sh
git clone https://github.com/connerohnesorge/homerowless && cd homerowless
scripts/build-app.sh            # dist/homerowless.app, ad-hoc signed
open dist/homerowless.app       # grant Accessibility when prompted
```

Config lives at `~/.config/homerowless/config.json`, written fully populated on first run and hot-reloaded.

## Developing

Rebuilding an ad-hoc signed app changes its code hash and macOS silently revokes the Accessibility grant. Create a stable dev identity once (`scripts/make-signing-cert.sh`) and build with:

```sh
CODESIGN_IDENTITY=HomerowlessDev scripts/build-app.sh
```

`axprobe` is the dev loop. It runs from Terminal with the terminal's Accessibility grant and links no UI:

```sh
swift run axprobe dump  --app Finder --depth 4
swift run axprobe scan  --app Safari --repeat 20
swift run axprobe bench --apps Finder,Safari,Slack,Code
swift run axprobe compat --app "Google Chrome"
swift run axprobe scrolls --app Safari
```

`swift test` covers geometry conversion, hint label prefix-freeness, the classifier, source-quality routing, and the mode state machine. Diagnostics append to `~/Library/Logs/homerowless.log`.

## Known limitations (v1)

- If "Blocked by secure input" appears, some process holds Secure Keyboard Entry. Password fields do this legitimately; a stale `loginwindow` holder clears when you lock and unlock the screen.
- Java/Swing apps (JetBrains IDEs) expose no usable accessibility tree. Use the grid fallback (auto-selected when the tree is unusable, or force it per app in config).
- Chromium/Electron apps get `AXManualAccessibility` set automatically; the first activation after launch may take an extra ~150ms while Chromium builds its tree.

## Layout

`Sources/AXCore` (AX wrappers, batching, paging) · `Geometry` (AX vs AppKit coordinate types) · `Discovery` (classifier, pruned BFS scanner, scroll areas, app compat) · `Routing` (AX/grid source selection) · `Hints` (labels, assignment, filtering) · `Overlay` (per-screen click-through panels, single-view canvas) · `Input` (Carbon hotkeys, event tap on a dedicated thread, key translation, click/scroll synthesis) · `Modes` (state machine + coordinator) · `App` (menu bar, onboarding, config).
