#!/usr/bin/env bash
# Renders a list of named shots on several devices into one folder (PNG + scene JSON for check_layout.py).
#   bash tools/preview/render_list.sh LIST OUTDIR [devices] [--only text] [-- extra render.sh args]
# LIST lines: "<name> <scene> [key=value ...]"; blank lines and lines starting with # are skipped.
# devices default: pc,phone-1108,phone-portrait. Example: tools/preview/ui_v2.list (docs/ui_v2/REPORT.md).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$1"
OUTDIR="$2"
shift 2
DEVICES="pc,phone-1108,phone-portrait"
ONLY=""
EXTRA=()
while [ $# -gt 0 ]; do
	case "$1" in
		--only) ONLY="$2"; shift 2 ;;
		--) shift; EXTRA=("$@"); break ;;
		*) DEVICES="$1"; shift ;;
	esac
done
mkdir -p "$OUTDIR"
FAIL=0
while read -r name scene rest; do
	[ -z "${name:-}" ] && continue
	case "$name" in \#*) continue ;; esac
	if [ -n "$ONLY" ] && [[ "$name" != *"$ONLY"* ]]; then continue; fi
	SETS=()
	for kv in $rest; do SETS+=(--set "$kv"); done
	IFS=',' read -ra DEVS <<< "$DEVICES"
	for d in "${DEVS[@]}"; do
		if ! bash "$HERE/render.sh" "$scene" --device "$d" "${SETS[@]}" "${EXTRA[@]}" \
			--out "$OUTDIR/$name-$d.png" --json "$OUTDIR/$name-$d.json" > "$OUTDIR/.$name-$d.log" 2>&1; then
			echo "FAILED $name $d (log $OUTDIR/.$name-$d.log)"
			FAIL=$((FAIL + 1))
		else
			echo "ok $name $d"
		fi
	done
done < "$LIST"
echo "render_list: $FAIL failed"
[ $FAIL -eq 0 ]
