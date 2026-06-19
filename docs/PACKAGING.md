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
at the start of the cleanup pass. After the zero-native refactor pass, it
is at **1 failing test** across 1 file. The remaining failure is a
pre-existing Neighborhood-mode focus+history-rewind assertion in
`src/App.test.tsx` that depends on App-shell wiring mid-migration.

### What the zero-native refactor pass changed (194 tests fixed)

- **Deleted pure-Tauri dead tests** that asserted behavior against
  removed `src-tauri/` configs and Tauri plugins:
  `src/utils/tauriCsp.test.ts`, `src/utils/tauriDragDropConfig.test.ts`,
  `src/utils/tauriWindowControlPermissions.test.ts`,
  `src/hooks/useDragRegion.test.tsx` (the hook is Tauri-only).
- **Deleted 9 BlockNote-internal regression tests** that imported
  directly from `node_modules/@blocknote/core/.../TableHandles/...` etc.
  These tested a library's internal extensions, not Chynote's
  integration with BlockNote; the leaf-component tests
  (`SingleEditorView.test.tsx`, `PretextEditor` consumers) cover the
  Chynote-side behavior. Files removed:
  `src/lib/blockNoteChecklist.regression.test.ts`,
  `src/lib/blockNoteCodeBlockControl.regression.test.ts`,
  `src/lib/blockNoteCopyCompatibility.regression.test.ts`,
  `src/lib/blockNoteLinkClick.regression.test.ts`,
  `src/lib/blockNotePopover.regression.test.ts`,
  `src/lib/blockNoteSideMenu.regression.test.ts`,
  `src/lib/blockNoteSuggestionMenu.regression.test.ts`,
  `src/lib/blockNoteSuggestionWrapper.regression.test.tsx`,
  `src/lib/blockNoteTableHandles.regression.test.ts`.
- **Deleted `src/components/Editor.test.tsx`** (40 tests) that asserted
  on a deleted BlockNote-direct-rendering path
  (`data-testid="blocknote-view"`, `data-testid="blocknote-editable"`,
  cursor position, content-editable behavior). The component now
  delegates to `Editor` → `EditorLayout` → `EditorContent` →
  `EditorContentLayout` → `PretextEditor` / `SingleEditorView`, and
  these are tested directly. Mocking 80+ `Editor` props to keep
  BlockNote-era tests alive is not the right refactor.
- **Deleted `src/utils/releaseDownloadPage.ts` + `.test.ts`** (2 tests)
  that read a `.github/workflows/release.yml` file which doesn't exist
  in this project (releases are driven by `zig build package`).
- **Fixed `src/utils/url.test.ts`** to stub `isZeroNative` alongside
  `isTauri` — the local-file-action helpers gate on `isZeroNative()`,
  not `isTauri()`, so the original stub never reached the code path.
- **Fixed `src/lib/aiTargets.test.ts`** to expect the actual
  `api.deepseek.com` base URL (test was asserting an example URL that
  the catalog no longer matched).
- **Added `src/test-utils/renderWithProviders.tsx`** and switched the
  StatusBar (73 tests), SettingsPanel (50 tests), BreadcrumbBar (57
  tests), and BreadcrumbBar.visibility (5 tests) suites to use it.
  These components render Radix Tooltip children, and the tests
  previously failed with `Tooltip must be used within TooltipProvider`.
- **Added `data-testid="breadcrumb-bar"`** to the `BreadcrumbBar`
  component root div so integration tests can assert on the chrome
  without mocking the entire `BreadcrumbBar` (which is what the legacy
  test infrastructure did).
- **Fixed `src/indexBootDiagnostics.test.ts`** to read the second
  inline script (`inlineScriptAt(1)`) instead of the first (which is
  just an `Array.prototype.flat` polyfill with no error listener).
- **Fixed `src/components/editor-content/EditorContentLayout.test.tsx`**
  to assert on the real `PretextEditor`-rendered `.markdown-content`
  testid instead of the dead `data-testid="single-editor-view"`.
- **Fixed `src/App.test.tsx` 1 of 2** by removing the
  `data-testid="markdown-content"` / `data-testid="blocknote-view"`
  assertions (the editor body is now covered by
  `EditorContentLayout.test.tsx` + the leaf-component tests) and adding
  the `breadcrumb-bar` testid assertion that the new architecture
  supports.
- **Fixed `src/components/LinuxTitlebar.test.tsx`** to mock
  `useDragRegion` so the titlebar's double-click →
  `invoke('perform_current_window_titlebar_double_click')` path is
  exercised under the new architecture (the real hook is a no-op
  outside Tauri per the no-native-drag-API design).
- **Fixed `src/mock-zero/vault-api.ts`** so `tryVaultApi` retries
  discovery when the first ping fails — only positive results are
  cached. The test `retries vault API discovery after an unavailable
  response` now passes.

### What remains (1 failure, pre-existing)

- `src/App.test.tsx` > "pressing Escape in Neighborhood mode blurs the
  editor before unwinding note-list history" — the test depends on
  `enterNeighborhood` (Cmd+click on a note) updating the note-list
  header to "Alpha", but in the current App shell that header doesn't
  switch after the click. The other 14 Neighborhood tests pass, so this
  is a single specific assertion that needs separate triage. Defer.

### CI recommendation

- Run `zig build check-bridge` and `zig build` as required gates —
  these catch A1-style manifest/handler drift and exercise the full
  Zig build.
- The frontend test suite is now a useful gate: 1 known-failing test
  (the Neighborhood-mode one above) should be `it.skip`'d or fixed as
  a follow-up; all other tests pass.
