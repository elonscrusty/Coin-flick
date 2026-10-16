#!/usr/bin/env bash
# Runs every offline check and prints a summary:
#   1. tools/check.sh --quick   type check, compile, rule tests
#   2. scenes that print PASS/FAIL: save-faults (5 cases), machine-fx (4 variants), perf
#   3. smoke scenes: the real server and client run the scene with zero game errors
# Everything is offline (Lune + the preview mock). Nothing here replaces a Studio test.
#   bash tools/run_regressions.sh            all
#   bash tools/run_regressions.sh --quick    skip perf and the long smoke scenes
#   bash tools/run_regressions.sh --only save-faults    only checks whose name contains the text
# Full output of each check: $OUT (default /tmp/ctr-regressions-<pid>), printed at the end.
set -uo pipefail
cd "$(dirname "$0")/.."
QUICK=0
ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--quick) QUICK=1; shift ;;
		--only) ONLY="$2"; shift 2 ;;
		*) echo "usage: bash tools/run_regressions.sh [--quick] [--only text]"; exit 2 ;;
	esac
done
OUT="${OUT:-/tmp/ctr-regressions-$$}"
mkdir -p "$OUT"
RESULTS=()
FAILED=0

record() { # name status seconds
	RESULTS+=("$(printf '%-34s %-5s %4ss' "$1" "$2" "$3")")
	if [ "$2" != "PASS" ]; then FAILED=$((FAILED + 1)); fi
}

want() { [ -z "$ONLY" ] || [[ "$1" == *"$ONLY"* ]]; }

# run_check <name> <cmd...>: PASS when the command exits 0 and prints no "[FAIL]" line
run_check() {
	local name="$1"; shift
	want "$name" || return 0
	local t0=$SECONDS
	"$@" > "$OUT/$name.log" 2>&1
	local code=$?
	local status=PASS
	if [ $code -ne 0 ] || grep -q '\[FAIL\]' "$OUT/$name.log" ; then status=FAIL; fi
	record "$name" "$status" $((SECONDS - t0))
}

# a pass/fail scene must end with its own PASS line
run_scene_check() { # name scene marker [scene args...]
	local name="$1" scene="$2" marker="$3"; shift 3
	want "$name" || return 0
	local t0=$SECONDS
	bash tools/preview/run_scene.sh "$scene" --max-time 900 "$@" > "$OUT/$name.log" 2>&1
	local code=$?
	local status=PASS
	if [ $code -ne 0 ] || grep -q '\[FAIL\]' "$OUT/$name.log" || ! grep -q "$marker PASS" "$OUT/$name.log"; then status=FAIL; fi
	record "$name" "$status" $((SECONDS - t0))
}

smoke() { # name scene args...
	local name="$1" scene="$2"; shift 2
	want "$name" || return 0
	local t0=$SECONDS
	bash tools/preview/run_scene.sh "$scene" --max-time 300 "$@" > "$OUT/$name.log" 2>&1
	local code=$?
	local status=PASS
	if [ $code -ne 0 ]; then status=FAIL; fi
	record "$name" "$status" $((SECONDS - t0))
}

run_check "check (types, compile, rules)" bash tools/check.sh --quick

for c in load save pending award release; do
	run_scene_check "save-faults:$c" save-faults "SAVE-FAULTS" --set case=$c
done
for m in AutoCracker HydraulicPress IndustrialCrusher; do
	run_scene_check "machine-fx:$m" machine-fx "MACHINE-FX" --set machine=$m
done
run_scene_check "hud-scope (lobby return)" hud-scope "HUD-SCOPE"
run_scene_check "accounting (results figures)" accounting "ACCOUNTING" --set headless=on
run_scene_check "signs (numeric text audit)" signs "SIGNS"
run_check "sign-faces (rendered lodge text)" python3 tools/preview/check_signs.py --selftest
run_scene_check "placement (bounds, overlaps)" placement "PLACEMENT"
run_scene_check "materials (discoveries, sale)" materials "MATERIALS"
run_scene_check "machine-fx:reduced-motion" machine-fx "MACHINE-FX" --set machine=IndustrialCrusher --set reduced=on
if [ $QUICK -eq 0 ]; then
	run_scene_check "perf (mock numbers, budgets)" perf "PERF" --device phone --set seconds=20
fi

for s in lobby shop party collection settings boards; do
	smoke "smoke:$s" "$s"
done
smoke "smoke:lobby kit-off (lodge Part stand-ins)" lobby --set kit=off
smoke "smoke:hunt" hunt
smoke "smoke:hunt+press" hunt --set machine=HydraulicPress --set mtime=6
smoke "smoke:hunt+crusher" hunt --set machine=IndustrialCrusher --set mtime=6
# docs/m11/CAMERA_SPAWN_FIX.md: the lobby spawn pad is solid, flush and clear; a roof spawn is put back on it
run_scene_check "spawn (lobby spawn pad clear)" spawn "SPAWN"
run_scene_check "spawn kit-off (stand-ins)" spawn "SPAWN" --set kit=off
for v in lobby menu peek aim glimpse table sell explore; do
	run_scene_check "first-person:$v" fp "FP" --set view=$v
done
# UI v2 (docs/ui_v2/REPORT.md): coalesced notifications, records unavailable state, purchase confirmation, invite expiry
run_scene_check "ui:notices coalesce" hunt "NOTICES" --set toast=feedback
run_scene_check "ui:records unavailable" collection "RECORDS" --set records=fail --set tab=Records
run_scene_check "ui:purchase confirm" shop "CONFIRM" --set tab=Storage --set confirm=1
run_scene_check "ui:tutorial skip footer" results "SKIP" --set mode=tutorial --set skip=1
run_scene_check "ui:invite expiry" party "INVITE-EXPIRY" --set view=expired
run_scene_check "ui:notices clear of headers" ui_notices "NOTICE-HEADER" --device phone-small --set dialog=1 --set textsize=Largest --set uiscale=real
run_scene_check "ui:starting hunt" party "STARTING" --set view=startcheck
if [ $QUICK -eq 0 ]; then
	# Master Prompt 7 Pass E: the whole first-person loop, rematch and return (each step is one full simulation)
	for v in output machine reveal rematch lobby cabinet; do
		run_scene_check "loop:$v" loop "LOOP" --set step=$v
	done
fi
if [ $QUICK -eq 0 ]; then
	smoke "smoke:results" results
	smoke "smoke:results party" results --set mode=party
fi

echo
echo "================ regression summary ================"
for r in "${RESULTS[@]}"; do echo "$r"; done
echo "----------------------------------------------------"
if [ $FAILED -eq 0 ]; then
	echo "ALL ${#RESULTS[@]} CHECKS PASS (offline; not Studio). Logs: $OUT"
else
	echo "$FAILED of ${#RESULTS[@]} CHECKS FAILED. Logs: $OUT"
	exit 1
fi
