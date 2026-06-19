# Pin the zero-native submodule

**Status:** Accepted (2026-06-19)

## Context

`zero-native/` is a forked submodule. The parent repo's `.gitmodules`
declared only `path` and `url`, with no `branch` directive or recorded
SHA. Any contributor who ran `git submodule update --remote` would
silently land on a different commit than the one we tested against,
with no way to detect the drift in CI.

The fork is `chy3xyz/zero-native` on `main`, currently at
`9bd93837b2dd86ff087812d048dc29b2d6599f41`. It diverges from the
upstream `vercel-labs/zero-native@0.2.0` via the
`chy3xyz/production-readiness-waves` merge, so we cannot rely on
upstream version tags as a proxy.

## Decision

1. Add `branch = main` to `.gitmodules` so a fresh `git submodule
   update --init` lands on the same tip every time.
2. Record the expected SHA in `zero-native/EXPECTED_SHA` (a tracked
   plain-text file). Bumping the fork means bumping this file in a
   commit.
3. Add `scripts/check-submodule.sh` that compares the recorded SHA
   against `git -C zero-native rev-parse HEAD` and exits non-zero on
   mismatch. Wire it into CI before any `zig build` step.

## Consequences

- Submodule bumps become an explicit, code-reviewed action instead of
  an implicit `git submodule update` side effect.
- CI catches drift before it ships.
- A local "I bumped the fork but forgot to update EXPECTED_SHA" is
  caught immediately on the next push.
