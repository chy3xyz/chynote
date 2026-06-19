#!/usr/bin/env bash
# Verify that the zero-native submodule is checked out at the recorded SHA.
# CI / other clones will fail loudly if they drift.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FILE="${REPO_ROOT}/zero-native/EXPECTED_SHA"

if [[ ! -f "$EXPECTED_FILE" ]]; then
  echo "FATAL: ${EXPECTED_FILE} missing" >&2
  exit 1
fi

EXPECTED_SHA="$(tr -d '[:space:]' < "$EXPECTED_FILE")"

if [[ ! -f "${REPO_ROOT}/zero-native/.git" && ! -d "${REPO_ROOT}/zero-native/.git" ]]; then
  echo "FATAL: zero-native submodule not initialized. Run: git submodule update --init" >&2
  exit 1
fi

ACTUAL_SHA="$(git -C "${REPO_ROOT}/zero-native" rev-parse HEAD)"

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "FATAL: zero-native submodule drift detected" >&2
  echo "  expected: ${EXPECTED_SHA}" >&2
  echo "  actual:   ${ACTUAL_SHA}" >&2
  echo "  run: git submodule update --remote zero-native && update zero-native/EXPECTED_SHA" >&2
  exit 1
fi

echo "ok: zero-native pinned at ${EXPECTED_SHA}"
