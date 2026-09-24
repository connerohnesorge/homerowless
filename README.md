# homerowless

Keyboard-driven macOS UI navigation, open source. Press a hotkey, every clickable element gets a label, type the label to click it. A maintained replacement for the archived Vimac and the closed-source Homerow.

- **Cmd-Shift-F** click mode: hints on every actionable element in the front window. Hold Shift/Cmd/Option while typing the label for a modifier click.
- **Cmd-J** scroll mode: `hjkl` scroll, `d`/`u` half page, `gg`/`G` top/bottom, Esc exits.

## Privacy

homerowless needs only **Accessibility**. All geometry comes from the Accessibility API; the app never captures the screen or reads pixels, and it consumes keystrokes only while hints are visible. Input Monitoring is not required.

## Install

Download `homerowless-<version>.zip` from the [latest release](https://github.com/connerohnesorge/homerowless/releases/latest), unzip, and move `homerowless.app` to `/Applications`. Releases are signed with a self-signed certificate, not an Apple Developer ID, so Gatekeeper blocks the first launch. Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/homerowless.app
open /Applications/homerowless.app   # grant Accessibility when prompted
```

Config lives at `~/.config/homerowless/config.json`, written fully populated on first run and hot-reloaded.

### Updates

The app checks the GitHub release feed daily with [Sparkle](https://sparkle-project.org) and offers new versions. Use **Check for Updates…** in the menu bar to check now. Updates are verified with an EdDSA signature and must carry the same code signature as the installed app, so the Accessibility grant survives updates.

### Build from source

```sh
git clone https://github.com/connerohnesorge/homerowless && cd homerowless
scripts/build-app.sh            # dist/homerowless.app, ad-hoc signed
```

## Releasing

Push a `vX.Y.Z` tag. `.github/workflows/release.yml` runs the tests, builds a universal app, signs it with the `homerowless Release` certificate, generates the Sparkle `appcast.xml`, and publishes both to a GitHub release. Required repository secrets: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`.

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
