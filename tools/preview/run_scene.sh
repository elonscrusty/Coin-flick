#!/usr/bin/env bash
# Runs one preview scene headlessly on the mock runtime (step 1 of render.sh only, no picture) and
# prints what the scene printed. For pass/fail and measurement scenes (perf, save-faults ...).
#   bash tools/preview/run_scene.sh <scene> [--device pc] [--seed N] [--max-time S] [--studio] [--set k=v ...]
# Exit code: 0 when the scene ran without errors, 1 when game code raised errors, 2 on bad usage.
# Scenes print PASS/FAIL lines; callers (tools/run_regressions.sh) grep them.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
T="${CTR_TOOLS:-/tmp/ctr-tools}"
if [ ! -x "$T/lune/lune" ] && [ -z "${CTR_TOOLS:-}" ] && [ -x /tmp/sh-tools/lune/lune ]; then T=/tmp/sh-tools; fi
LUNE="$T/lune/lune"
if [ ! -x "$LUNE" ]; then
	echo "run_scene: Lune not found (bash tools/setup_tools.sh)"
	exit 2
fi
if [ $# -lt 1 ]; then
	echo "usage: bash tools/preview/run_scene.sh <scene> [--device pc] [--max-time S] [--set k=v ...]"
	exit 2
fi
SCENE="$1"
shift
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"$LUNE" run "$HERE/runtime/main.luau" -- --scene "$SCENE" --out "$OUT/$SCENE.json" --repo "$REPO" --root "$HERE" "$@"
exit $?
