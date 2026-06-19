# Chynote packaging

Chynote is a Zig 0.17 + React 19 desktop app that builds into a real macOS
`.app` bundle via [zero-native](https://github.com/chy3xyz/zero-native)'s
`tooling.package` module. The bundle is **ad-hoc signed** by default; for
distribution outside the build machine you need an Apple Developer ID.

This document covers the local build path, CI, and the deferred items that
matter for production distribution.

## Build steps

| Command                | What it does                                                |
|------------------------|-------------------------------------------------------------|
| `zig build`            | Compile `chynote-zn` and rebuild `frontend/dist`            |
| `zig build test`       | Run Zig unit tests                                          |
| `zig build check-bridge` | Verify `src/main.zig` handlers match `app.zon`             |
| `zig build package`    | Produce a macOS `.app` bundle at `zig-out/package/`         |
| `zig build run`        | Run the bare binary (no bundle)                             |
| `zig build dev`        | Run the Vite dev server and a native shell (hot reload)     |
| `scripts/check-submodule.sh` | Verify the `zero-native` submodule SHA matches          |

The `check-bridge` step is a guard against drift between `app.zon`'s
`bridge.commands` list and the `Handler` arrays in `src/main.zig`. CI must
run it before `zig build`.

## Producing a `.app` bundle

`zig build package` invokes the `zero-native` CLI to assemble the bundle:

1. Loads `app.zon` and validates the schema.
2. Copies the compiled `chynote-zn` executable into
   `Contents/MacOS/chynote`.
3. Copies `frontend/dist/` into `Contents/Resources/frontend/`.
4. Copies `assets/icon.icns` into `Contents/Resources/`.
5. Generates `Contents/Info.plist` from `app.zon` (`id`, `display_name`,
   `version`, `LSMinimumSystemVersion`, `CFBundleIconFile`, `CFBundlePackageType`).
6. Ad-hoc signs the bundle with `codesign --sign -`.
7. Writes `Contents/Resources/package-manifest.zon` and
   `Contents/Resources/signing-plan.txt` for traceability.

The artifact lands at:

```
zig-out/package/chynote-zn-0.1.0-macos-Debug.app
```

(append `-Doptimize=ReleaseSafe` for a release build, or `-Doptimize=ReleaseFast`).

To launch: `open zig-out/package/chynote-zn-0.1.0-macos-Debug.app`.

### Verifying the bundle

```bash
codesign -dv zig-out/package/chynote-zn-0.1.0-macos-Debug.app
lipo -info zig-out/package/chynote-zn-0.1.0-macos-Debug.app/Contents/MacOS/chynote
ls -la zig-out/package/chynote-zn-0.1.0-macos-Debug.app/Contents/{MacOS,Resources}
```

Expected:
- `Signature=adhoc` for local builds.
- `Non-fat file: ... is architecture: arm64` (or `x86_64` on Intel).
- `Resources/frontend/` exists with `index.html` and `assets/`.

## Identity signing (distribution)

The current `package` step in `build.zig` calls
`zero-native package --signing none` (ad-hoc). For notarized distribution:

1. Add a `package-identity` step to `build.zig` that reads these env vars:
   - `CHYNOTE_CODESIGN_IDENTITY` — `Developer ID Application: ... (-)`
   - `CHYNOTE_CODESIGN_TEAM_ID` — e.g. `ABCDE12345`
2. Forward them via `--signing identity --identity "$CHYNOTE_CODESIGN_IDENTITY" --team-id "$CHYNOTE_CODESIGN_TEAM_ID"` to the `zero-native package` CLI.
3. Add a notarization step (`xcrun notarytool submit ...` + `xcrun stapler staple`).

This is **not implemented yet**; the plan for it lives in
[`docs/adr/0006-zero-native-pin.md`](adr/0006-zero-native-pin.md) (placeholder)
and the original A5 of the refactor plan.

## Submodule pin

`zero-native/` is a forked submodule pinned to a specific SHA. The SHA is
recorded in `zero-native/EXPECTED_SHA` and verified by
`scripts/check-submodule.sh`. CI must run this before any build step:

```bash
scripts/check-submodule.sh
zig build check-bridge
zig build package
```

To bump the fork:

```bash
git submodule update --remote zero-native
git -C zero-native rev-parse HEAD
# paste the new SHA into zero-native/EXPECTED_SHA
git add zero-native/EXPECTED_SHA && git commit
```

## Deferred items

The original refactor plan called out three items that were deferred after
investigation found them to be over-scoped. They are still on the backlog:

| Plan step | Reason for deferring |
|-----------|----------------------|
| A3: extensions registry | `zero-native.extensions.ModuleHooks.command_fn` is internal, not a bridge path. None of our long-lived services genuinely need lifecycle hooks today. The field is plumbed through `RunOptions`/`RuntimeOptions` so it's ready to use. |
| A4: async streaming | `system.stream_claude_chat` and `system.stream_ai_agent` are currently stub mocks that return a string literal. Real streaming would be a new feature, not a refactor. See comment in `src/system.zig:741`. |
| A5: dedupe runner.zig | The four `runXxx` functions are 90% copy-pasted but each has a slightly different platform init (`try` vs not, `defer` etc.). Dedupe is high-value but invasive; left for a follow-up. |
| A5: frontend command-name map | `frontend/src/@zero-apps/api/core/index.ts:3` still maintains a camelCase → snake_case map. Dropping it requires renaming all frontend call sites; left for a follow-up. |

## Test status (as of 2026-06-19)

`pnpm --dir frontend test --run` was at 195 failing tests across 26 files
at the start of the cleanup pass. The cleanup reduced that to 50 failures
across 16 files.

### What the cleanup pass fixed

- Deleted pure-Tauri dead tests that asserted behavior against removed
  `src-tauri/` configs and Tauri plugins:
  `src/utils/tauriCsp.test.ts`, `src/utils/tauriDragDropConfig.test.ts`,
  `src/utils/tauriWindowControlPermissions.test.ts`,
  `src/hooks/useDragRegion.test.tsx` (the hook is Tauri-only).
- Fixed `src/utils/url.test.ts` to stub `isZeroNative` alongside
  `isTauri` — the local-file-action helpers gate on `isZeroNative()`,
  not `isTauri`, so the original stub never reached the code path.
- Added `src/test-utils/renderWithProviders.tsx` and switched the
  StatusBar (73 tests), SettingsPanel (50 tests), BreadcrumbBar (57
  tests), and BreadcrumbBar.visibility (5 tests) suites to use it. These
  components render Radix Tooltip children, and the tests previously
  failed with `Tooltip must be used within TooltipProvider`.
- Fixed `src/lib/aiTargets.test.ts` to expect the actual
  `api.deepseek.com` base URL (test was asserting an example URL that
  the catalog no longer matched).

### What remains (50 failures, all pre-existing component-refactor debt)

These require component-shape refactors, not test infrastructure fixes:

- `src/components/Editor.test.tsx` (25): the test mocks `BlockNoteViewRaw`
  and queries `data-testid="blocknote-view"` / `"blocknote-editable"`.
  The component now uses `SingleEditorView`, which doesn't expose those
  test-ids. Need to either add the test-ids to the new component or
  port the tests to the new architecture.
- `src/lib/blockNote*.regression.test.ts` (15): these test
  pre-existing patches (checklist, code block, popover, side menu,
  suggestion menu, table handles) that have stale assumptions about
  BlockNote internals. Real bugs in the patches, not test infrastructure.
- `src/components/editor-content/EditorContentLayout.test.tsx` (1): test
  queries `data-testid="single-editor-view"` which the new layout
  doesn't expose.
- `src/components/LinuxTitlebar.test.tsx` (1): the test relies on
  `useDragRegion` actually calling the bridge invoke on double-click,
  but the hook is now a no-op outside Tauri. Need to mock the hook.
- `src/App.test.tsx` (2): test expects `data-testid="blocknote-view"`
  / `"mock-editor"` in the rendered shell; the App shell now renders
  an `app-shell` div without those.
- `src/indexBootDiagnostics.test.ts` (1): expects a ResizeObserver-loop
  `event.preventDefault()` to set `defaultPrevented=true` on a manually
  constructed `ErrorEvent`. The current index.html has the script,
  but the test asserts jsdom behavior that may be subtle.
- `src/mock-zero/vault-api.test.ts` (1): tests `tryVaultApi` from a
  mock-zero module that has been removed/refactored.
- `src/utils/releaseDownloadPage.test.ts` (2): reads
  `.github/workflows/release.yml` which doesn't exist in this
  project's layout.

### CI recommendation

- Run `zig build check-bridge` and `zig build` as required gates — these
  catch A1-style manifest/handler drift.
- The frontend test suite is no longer a useful gate until the 50
  remaining component-shape refactors are done. A follow-up session
  should either (a) add the missing test-ids to the new components so
  the old tests pass, or (b) delete/port the old tests to the new
  architecture.
