#!/usr/bin/env bash
# Type check (luau-lsp with Roblox types, zero diagnostics), compile check, offline rule
# tests and Rojo build. Usage: bash tools/check.sh [--quick]   (--quick skips the build)
# Tools live in ${CTR_TOOLS:-/tmp/ctr-tools}; install them with bash tools/setup_tools.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
T="${CTR_TOOLS:-/tmp/ctr-tools}"
ROJO="$T/rojo/rojo"
LSP="$T/lsp/luau-lsp"
TMP="$(mktemp -d)"
SM="$TMP/sourcemap.json"

"$ROJO" sourcemap default.project.json -o "$SM" >/dev/null
STATUS=0
RAW="$("$LSP" analyze --definitions="$T/globalTypes.d.luau" --sourcemap="$SM" src 2>&1)" || STATUS=$?
OUT="$(printf '%s\n' "$RAW" | grep -v -E '^\[(INFO|WARN)\]' || true)"
if [ "$STATUS" -ne 0 ] || [ -n "$OUT" ]; then
	echo "$OUT"
	echo "TYPECHECK: $(echo "$OUT" | grep -c . || true) problem(s)"
	exit 1
fi
echo "TYPECHECK: ok"

COMPILE="$T/luau/luau-compile"
if [ -x "$COMPILE" ]; then
	while IFS= read -r f; do
		if ! COUT="$("$COMPILE" -O0 --null "$f" 2>&1)"; then
			echo "$f: $COUT"
			echo "COMPILE: failed"
			exit 1
		fi
	done < <(find src -name '*.luau')
	echo "COMPILE: ok"
fi

bash tools/test.sh | tail -n 1

if [ "${1:-}" != "--quick" ]; then
	"$ROJO" build default.project.json -o "$TMP/CrackTheRocks.rbxlx" >/dev/null
	"$ROJO" build match.project.json -o "$TMP/CrackTheRocksMatch.rbxlx" >/dev/null
	echo "BUILD: ok (lobby/single-place + match)"
fi
