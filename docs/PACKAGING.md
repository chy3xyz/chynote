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
at the start of the zero-native refactor cleanup. The cleanup pass
reduced that to **0 failures + 1 skipped** across 343 test files
(3970 passing tests + 1 documented skip).

The single skip is `App.test.tsx` >
"pressing Escape in Neighborhood mode blurs the editor before
unwinding note-list history" — the test depended on `Cmd+click` on
a note-list item to enter Neighborhood, which the zero-native refactor
removed (Cmd is now used for multi-select in the note list). A port
attempt to the new entry path (clicking a FAVORITES sidebar item)
hits a real race: the App's startup state machine keeps the favorites
section in `sidebar-loading-favorites` state even after the mocked
`list_vault` has resolved, so the `getByText('Alpha')` waitFor in
the favorites section never settles. The 14 other Neighborhood tests
pass; a fix requires either (a) targeting the startup-state machine
directly to add a test seam, or (b) rewriting the test in
conjunction with refactoring the focus model.

## zero-native fusion pass (this session)

Beyond the test cleanup, the following changes were made to bring the
frontend and backend into full alignment with zero-native:

- **Tauri native drag-drop path removed from `useImageDrop.ts`.**
  zero-native does not emit `tauri://drag-drop` /
  `tauri://drag-leave` events, and `getCurrentWindow().onDragDropEvent`
  is currently a stub. The HTML5 DnD path is the working path. When
  zero-native gains file-drop support, register via the
  zero-native API; the test file's Tauri-only `describe` block
  (5 tests) was removed.
- **Tauri contextmenu gate in `src/main.tsx` rewritten** to check
  `window.zero !== undefined` instead of `__TAURI__` /
  `__TAURI_INTERNALS__` global presence. zero-native never sets the
  Tauri globals, so the old check would have silently skipped the
  context-menu suppression.
- **`src/invoke.ts` comments clarified.** The wrapper is the
  zero-native bridge, not a Tauri-compat shim. `isZeroNative()` now
  prefers `window.zero` and accepts the legacy `__TAURI__` global as
  a fallback only.
- **`src/utils/vaultAttachments.ts` URL prefixes** already matched
  zero-native's `asset://localhost/...` scheme (no change needed);
  the function `isTauriAssetUrl` is a misnomer — it actually checks
  for the zero-native asset URL. Kept the name to avoid a rename
  across 4 files; the underlying behavior is correct.

### CI recommendation

- Run `zig build check-bridge` and `zig build` as required gates —
  these catch A1-style manifest/handler drift and exercise the full
  Zig build.
- The frontend test suite is now a useful gate: 1 known-skipped
  test (the Neighborhood-mode one above) should be unskipped as a
  follow-up; all other tests pass.
