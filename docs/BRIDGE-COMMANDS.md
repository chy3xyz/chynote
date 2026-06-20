# Bridge Commands: How to Add a New One

This is the end-to-end guide for adding a new command to the
JS ↔ native bridge. We'll add a fictional `system.get_app_uptime` as
the running example.

## What the bridge looks like

A bridge command is a (name, args, result) tuple. The JS side calls
`window.zero.invoke<T>(name, args)`, the native side looks up the
registered `Handler` by name, calls it, and returns a JSON-serialized
result. `app.zon` is the single source of truth for which commands
exist. See [`ZERO-NATIVE-ARCHITECTURE.md`](ZERO-NATIVE-ARCHITECTURE.md)
for the bigger picture.

## The 3-step recipe

### Step 1 — Add to `app.zon`

Open `app.zon` and add an entry to `.bridge.commands`. Pick a clear
namespace, the origin allowlist (use `"zero://app"` for app-internal
commands), and put it in the right alphabetical position.

```zon
.bridge = .{
    .commands = .{
        // ... existing commands ...
        .{ .name = "system.get_app_uptime", .origins = .{ "zero://app" } },
    },
},
```

If your command is genuinely available to any origin (e.g. a public
metadata read), leave `.origins` empty. Always set it for anything
that writes, reads user data, or spawns processes.

### Step 2 — Write the handler in `src/`

Add a `pub fn` to the appropriate file in `src/`. The signature is
fixed:

```zig
pub fn handleGetAppUptime(
    context: *anyopaque,
    invocation: zero_native.bridge.Invocation,
    output: []u8,
) anyerror![]u8 {
    const ctx: *BridgeContext = @ptrCast(@alignCast(context));
    const io = ctx.io.*;
    _ = io;

    // Read args from invocation.request.payload (it's a JSON string slice).
    // The system.get_app_uptime example takes no args, so skip parsing.

    // Compute the result.
    const uptime_ms: u64 = @intCast(std.time.milliTimestamp() - ctx.start_time);

    // Serialize to JSON. The convention is to write into `output` and
    // return the slice you actually filled (zero-native uses the length
    // to size the response).
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.heap.page_allocator);

    const w = buf.writer(std.heap.page_allocator);
    try w.print("{{\"uptime_ms\":{}}}", .{uptime_ms});
    const len = @min(buf.items.len, output.len);
    @memcpy(output[0..len], buf.items[0..len]);
    return output[0..len];
}
```

Patterns to follow:

- **Read the file for the module**: handlers live alongside the code
  that does the work. `vault.*` handlers in `src/vault.zig`,
  `git.*` handlers in `src/git.zig`, `system.*` handlers in
  `src/system.zig`.
- **Read args via `extractJsonField(payload, "\"path\"")`** (Zig 0.17
  has no built-in JSON parser; `src/parsing.zig` provides helpers).
- **Write JSON into `output`** and return the slice you filled. The
  buffer must outlive the call; use `std.heap.page_allocator` or scope
  it in the caller.
- **Errors**: return `anyerror!` and let the JS side see a rejected
  promise. Map domain errors to `error{X}Reason` and add the error set
  to the signature if you want type-checked error matching in JS.
- **Large results**: if the JSON exceeds a few KB, write to a temp
  buffer and return its path; the JS side calls `convertFileSrc` to
  read it.

### Step 3 — Register the handler in `src/main.zig`

Open `src/main.zig` and add the handler to the right array. Commands
are grouped by namespace:

```zig
const system_handlers = [_]zero_native.bridge.Handler{
    .{ .name = "system.copy_text_to_clipboard", .context = &bridge_ctx, .invoke_fn = system.handleCopyTextToClipboard },
    .{ .name = "system.check_claude_cli", .context = &bridge_ctx, .invoke_fn = system.handleCheckClaudeCli },
    // ... existing ...
    .{ .name = "system.get_app_uptime", .context = &bridge_ctx, .invoke_fn = system.handleGetAppUptime },
};
```

Three things to get right:

- **`.name`** must match the `app.zon` entry exactly.
- **`.context`** is the pointer passed to the handler. For most
  handlers it's `&bridge_ctx`. If your handler is stateless, you can
  pass `undefined`.
- **`.invoke_fn`** is the function. Make sure the function is
  `pub` so the type system can find it.

### Step 4 — Call it from the frontend

The frontend's `@zero-apps/api/core` exposes `invoke<T>(cmd, args)` and
`bridgeCall<T>(cmd, args)`. Use `invoke` for typed calls; `bridgeCall`
for the `get_note_content` shape that needs response normalization.

```ts
import { invoke } from "@zero-apps/api/core";

const uptime = await invoke<{ uptime_ms: number }>("system.get_app_uptime", {});
console.log(`App has been running for ${uptime.uptime_ms}ms`);
```

For browser tests, mock the command in `mockCommandResults`:

```ts
import { mockCommandResults } from "@/mock-zero";
mockCommandResults.system_get_app_uptime = { uptime_ms: 0 };
```

(In the mock, dotted names become `_<name>`; see `src/mock-zero/mock-handlers.ts`.)

### Step 5 — Verify

Run the build-time check to confirm `app.zon` and the handlers agree:

```sh
zig build check-bridge
```

Expected output:

```
ok: 94 bridge commands match app.zon
```

(The exact number depends on how many commands you added; the important
thing is "ok".)

Then run the full build + tests:

```sh
zig build
pnpm --dir frontend test --run
```

## Common mistakes

- **Forget to add to `app.zon`.** `zig build check-bridge` catches this
  with a clear "drift" message. Always run it.
- **Handler name doesn't match the manifest.** Same check catches it.
- **JSON result exceeds the output buffer.** The default output buffer
  is 4 KB (the size of the WebView message channel frame). For larger
  results, use a temp file and return a path + a `file://` URL.
- **Args are not a string.** `invocation.request.payload` is a JSON
  string slice. If the JS side passes a number, the handler will see
  a number literal (not a string). Parse accordingly.
- **Forgetting `.origins`.** A command without `.origins` accepts
  calls from any origin. For app-internal commands, set
  `.origins = .{ "zero://app" }`.
- **Side effects in the handler.** Handlers run on the native event
  loop thread. Don't block; spawn subprocesses with
  `std.process.run` and don't await from the handler synchronously.

## Async handlers (deferred A4)

Most commands are sync: the handler returns a single result. For
streaming or long-running work, use `AsyncHandler` instead:

```zig
const async_handlers = [_]zero_native.bridge.AsyncHandler{
    .{ .name = "system.stream_ai_agent", .context = &bridge_ctx, .invoke_fn = system.handleStreamAiAgent },
};
```

The `AsyncHandlerFn` signature is
`fn (*anyopaque, Invocation, *AsyncResponder) anyerror!void` and uses
`responder.respond(chunk)`, `responder.success()`, `responder.fail(err)`
to send multiple chunks. The JS side uses
`@zero-apps/api/window`'s `onEvent` or `@zero-apps/api/core`'s `listen`
to receive them.

The current code uses `AsyncHandler` only for the AI streaming stubs
(`handleStreamClaudeChat`, `handleStreamAiAgent`). See
[`src/system.zig:741`](src/system.zig) for the pattern.

## Where to put new handlers

The convention is one module per bridge namespace:

- `src/vault.zig` — `vault.*` commands
- `src/git.zig` — `git.*` commands
- `src/system.zig` — `system.*` commands
- `src/globals.zig` — shared state, event emitters (not a handler module)

If a new namespace is needed (e.g. `preferences.*`), create a new
`src/preferences.zig` and a matching `preferences_handlers` array in
`src/main.zig`.
