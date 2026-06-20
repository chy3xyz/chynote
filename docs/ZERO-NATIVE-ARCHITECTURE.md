# zero-native Architecture

Chynote is built on [zero-native](https://github.com/chy3xyz/zero-native)
(the `zero-native/` submodule). This document explains the architectural
shape and how Chynote uses it.

## What zero-native provides

zero-native is a native shell that hosts a system WebView and exposes a
Zig API for:

- **Window & event loop** (`platform`): a single owner thread runs the
  native event loop, frame scheduling, and bridge dispatch.
- **Bridge** (`bridge`): a typed request/response channel between the
  native backend and the WebView JS. Two flavors: sync `Handler` (returns
  a JSON-serialized result) and `AsyncHandler` (responds to a
  `AsyncResponder` over multiple chunks).
- **Manifest** (`app_manifest` / `tooling/manifest`): validates the
  `app.zon` schema and produces a typed `Metadata` struct.
- **Tooling** (`tooling/package`): produces a real `.app` bundle from
  `Metadata` + a binary + frontend dist, including ad-hoc or identity
  signing.
- **Asset server** (`assets`): serves `frontend/dist` to the WebView at
  runtime (the binary does not embed the frontend).
- **Window state** (`window_state`): persists per-window geometry to disk
  so the next launch restores it.
- **Automation** (`automation`): an out-of-process server that drives the
  app for tests (start app, run a sequence of invocations, snapshot DOM).
- **Extensions** (`extensions`): a lifecycle module registry (start/stop
  hooks for native services).
- **Security** (`security`): navigation policy (allowed origins, external
  link action), per-command origin allowlist.
- **Emebed / frontend / debug**: the loader/embedder, frontend source
  discovery, and runtime diagnostics.

## High-level shape

```
   ┌─────────────────────────────────────────────┐
   │              Chynote (Zig)                  │
   │  src/main.zig → Runner → platform.run(...)  │
   │      │                                      │
   │      ├─ bridge.BridgePolicy(commands)        │
   │      │      ↑                               │
   │      │  parsed from app.zon at build time   │
   │      │                                      │
   │      ├─ handler functions (vault, git, ...)  │
   │      │                                      │
   │      └─ runtime.Runtime.init(...)            │
   │             ├─ window loop                  │
   │             ├─ asset server                 │
   │             ├─ automation server             │
   │             └─ bridge dispatcher             │
   └──────────────────┬──────────────────────────┘
                      │ IPC (JSON over WebView message channel)
   ┌──────────────────▼──────────────────────────┐
   │       zero-native WebView (system)          │
   │  ┌─────────────────────────────────────┐    │
   │  │  React + TypeScript (frontend/)      │    │
   │  │  calls window.zero.invoke<T>(cmd, args)│    │
   │  │  listens to events via @zero-apps/api │    │
   │  └─────────────────────────────────────┘    │
   └─────────────────────────────────────────────┘
```

The native process owns one thread. It runs the OS event loop, the asset
server, the automation server, and the bridge dispatcher all in that
thread. The WebView runs the JS in its own thread. Calls flow:

1. JS calls `window.zero.invoke('vault.list_vault', {})`.
2. zero-native serializes the call and the args, posts them to the bridge
   dispatcher.
3. The dispatcher looks up the registered `Handler` for the command and
   calls it on the native thread.
4. The handler returns a `[]u8` slice. zero-native serializes it back to
   the WebView and resolves the JS promise.

The same flow works for `AsyncHandler` (multiple chunks via
`AsyncResponder`).

## The bridge surface: `app.zon`

`app.zon` is the **single source of truth** for the bridge. The frontend
command list, the Zig handler list, and the security policy all derive
from it.

```zon
.{
    .id = "com.chynote.app",
    .name = "chynote",
    .display_name = "Chynote",
    .version = "0.1.0",
    .frontend = .{
        .dist = "frontend/dist",
        .entry = "index.html",
    },
    .security = .{
        .navigation = .{
            .allowed_origins = .{ "zero://app", "zero://inline", "..." },
            .external_links = .{
                .action = "open_system_browser",
                .allowed_urls = .{ "mailto:*", "https://github.com/*" },
            },
        },
    },
    .bridge = .{
        .commands = .{
            .{ .name = "vault.list_vault", .origins = .{ "zero://app" } },
            .{ .name = "vault.get_note_content", .origins = .{ "zero://app" } },
            // ... 91 more
        },
    },
}
```

### Build-time codegen

`build.zig` parses `app.zon` at build time and emits
`src/generated/app_manifest_bridge.zig`:

```zig
// generated, do not edit
pub const app_command_policies = [_]@import("zero-native").bridge.CommandPolicy{
    .{ .name = "vault.list_vault", .origins = &.{ "zero://app" } },
    .{ .name = "vault.get_note_content", .origins = &.{ "zero://app" } },
    // ... 91 more
};
```

`src/main.zig` aliases `app_manifest_bridge.app_command_policies` to
`command_policies` and passes it to the dispatcher. So adding a new
command is **3 files**: `app.zon`, the handler in `src/*.zig`, and a
new handler entry in `src/main.zig`. See `docs/BRIDGE-COMMANDS.md` for
the step-by-step.

### CI guard

`scripts/check-bridge.zig` (run via `zig build check-bridge`) cross-
references `app.zon.bridge.commands` with the `Handler` arrays in
`src/main.zig`. The build fails if a handler is missing in either
direction. Run this in CI before any other build step.

## Asset flow

The native binary does not embed the frontend. At runtime it serves
`frontend/dist` to the WebView via the zero-native asset server. This
means:

- `zig build` re-runs `pnpm --dir frontend run build` before compiling
  the Zig binary. If `frontend/` changed, the dist is fresh.
- In dev mode, `zig build dev` runs `pnpm dev` (Vite dev server on
  `http://127.0.0.1:5173/`) and the WebView loads from there via
  `ZERO_NATIVE_FRONTEND_URL`. Hot reload works.

## Security model

`security.navigation.allowed_origins` is the **allowlist** of origins
that can call the bridge. `zero://app` is the WebView itself. `zero://local`
is the asset server. `http://127.0.0.1:5173` is the Vite dev server.

Per-command `.origins` adds a second layer. If a command is listed in
`app.zon.bridge.commands` without an `.origins` allowlist, **any** origin
can call it. If `.origins` is set, only those origins can. Always set
`.origins` for sensitive commands.

`security.navigation.external_links` controls what happens to
`window.open(...)` calls. The default is `deny` (the link is suppressed).
We use `open_system_browser` with an allowlist of `mailto:` and a few
`https://` patterns.

## The run path

`src/main.zig → runner.zig` is the entry point. `runner.runWithOptions`
constructs `RunOptions` (bundle id, icon, security policy, bridge
dispatcher) and dispatches to a platform runner (`runMacos`, `runLinux`,
`runWindows`). Each runner:

1. Creates a `zero_native.App`.
2. Calls `app.setFrontendSource(...)` with a callback that returns
   `WEBVIEW_SOURCE_DIST` (production) or `WEBVIEW_SOURCE_URL` (dev).
3. Calls `app.setBridgeDispatcher(...)` with our `BridgeDispatcher`.
4. Calls `runtime = Runtime.init(allocator, io, .{.platform=..., .extensions=options.extensions, ...})`.
5. `runtime.run(handlers)`.

## deferred A3 / A4 / A5

The refactor plan called out three items that were intentionally
deferred. See [`docs/PACKAGING.md`](PACKAGING.md) for status:

- **A3** (extensions modules): the field is plumbed but no modules use
  it yet. Add a module by writing it, then listing it in `RunOptions.extensions`.
- **A4** (async streaming): the streaming handlers are sync stubs that
  emit a `Done` event. The frontend can use them but real chunked
  content requires converting to `AsyncHandler` and spawning the CLI
  process.
- **A5** (runner dedup + frontend map): pure code quality, deferred.

## Useful files to read first

- `zero-native/src/root.zig` — public API surface.
- `zero-native/src/bridge/root.zig` — bridge types, dispatcher.
- `zero-native/src/runtime/root.zig` — runtime lifecycle, event loop.
- `zero-native/src/tooling/manifest.zig` — `app.zon` schema, `readMetadata`.
- `zero-native/src/tooling/package.zig` — `.app` bundling.
- `src/main.zig` — handler registration, dispatcher setup.
- `src/runner.zig` — run path.
- `app.zon` — bridge manifest.
- `frontend/src/@zero-apps/api/core/index.ts` — `invoke`, `bridgeCall`,
  `convertFileSrc`, `isZeroNative` (the JS API surface).
