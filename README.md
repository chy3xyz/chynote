# Chynote Zn

A personal knowledge and life management desktop app. The vault on disk is
the source of truth; a native shell hosts a React frontend; the backend is
Zig. Built on [zero-native](https://github.com/chy3xyz/zero-native).

## What it is

Four-panel UI (sidebar → note list → editor → inspector) over a folder of
plain markdown with YAML frontmatter. Opinionated conventions, AI-agent
integration (Claude Code / Codex / Pi), git-based sync, multi-vault
support, wikilink graph, keyword search, MCP server, alpha/stable release
channels. See [`docs/VISION.md`](docs/VISION.md) for the full picture and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the pieces fit.

## Quick start

```sh
zig build dev      # install frontend deps if needed, run Vite + native shell
zig build run      # build + launch the bare binary (frontend dist is served from disk)
zig build package  # produce a real .app bundle at zig-out/package/
```

`zig build dev` and `zig build run` rebuild `frontend/dist` automatically.
The native binary reads assets from `frontend/dist` at runtime — no embedded
frontend bundle.

### Build steps

| Step | What it does |
|------|--------------|
| `zig build` | Compile `chynote-zn` and rebuild `frontend/dist` |
| `zig build test` | Run Zig unit tests |
| `zig build check-bridge` | Verify `src/main.zig` handlers match `app.zon` |
| `zig build package` | Produce a macOS `.app` at `zig-out/package/` |
| `scripts/check-submodule.sh` | Verify `zero-native` submodule SHA matches `EXPECTED_SHA` |

CI must run `zig build check-bridge` and `scripts/check-submodule.sh`
before any other build step. See [`docs/PACKAGING.md`](docs/PACKAGING.md).

### Override paths

```sh
-Dzero-native-path=/path/to/zero-native   # use a different fork
-Dcef-dir=/path/to/cef                    # use a different CEF runtime
```

## Stack

- **Backend**: [Zig 0.17](https://ziglang.org/) — `src/`
- **Frontend**: React 19 + TypeScript + Vite — `frontend/`
- **Native shell**: [zero-native](https://github.com/chy3xyz/zero-native) (forked submodule) — system WebView on macOS

## Documentation

| Doc | Purpose |
|-----|---------|
| [`docs/VISION.md`](docs/VISION.md) | What the app is and why |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How the pieces fit (filesystem-as-truth, design principles) |
| [`docs/GETTING-STARTED.md`](docs/GETTING-STARTED.md) | Detailed setup, dir structure, feature guides |
| [`docs/PACKAGING.md`](docs/PACKAGING.md) | Build matrix, deferred items, test status |
| [`docs/ZERO-NATIVE-ARCHITECTURE.md`](docs/ZERO-NATIVE-ARCHITECTURE.md) | The native shell, bridge, manifest, app.zon |
| [`docs/BRIDGE-COMMANDS.md`](docs/BRIDGE-COMMANDS.md) | How to add a new bridge command (end-to-end) |
| [`docs/ABSTRACTIONS.md`](docs/ABSTRACTIONS.md) | Glossary of terms |
| [`docs/adr/`](docs/adr/) | Architecture decision records |

## Repository layout

```
chynote/
├── src/                          # Zig backend
│   ├── main.zig                  # Entry point, bridge handler registry
│   ├── runner.zig                # RunOptions → platform-specific runner
│   ├── vault.zig                 # Vault scanning, parsing, content ops
│   ├── git.zig                   # Git integration
│   ├── system.zig                # System commands (CLI detection, etc.)
│   ├── globals.zig               # Shared state, event emitters
│   ├── parsing.zig               # Frontmatter + text parsing
│   └── generated/                # Build-time codegen output (gitignored)
│
├── frontend/                     # React + TypeScript
│   ├── src/
│   │   ├── App.tsx               # Root component
│   │   ├── components/            # ~98 UI components
│   │   ├── hooks/                # ~40 custom hooks
│   │   ├── lib/                  # Cross-cutting helpers
│   │   ├── utils/                # Domain utilities
│   │   ├── mock-zero/            # Browser-mode mocks
│   │   └── @zero-apps/api/       # zero-native bridge type definitions
│   ├── package.json
│   └── vite.config.ts
│
├── zero-native/                  # Submodule (pinned SHA, see EXPECTED_SHA)
│
├── app.zon                       # Single source of truth for the bridge
├── build.zig                     # Top-level build script
├── build.zig.zon
├── scripts/
│   ├── check-submodule.sh        # CI guard
│   └── check-bridge.zig          # Build-time handler/manifest cross-check
└── docs/                         # All documentation
```
