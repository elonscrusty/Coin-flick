#!/usr/bin/env bash
# Offline rule tests for src/shared (pile, match rules, geode rolls). Needs Lune
# (bash tools/setup_tools.sh installs it into /tmp/ctr-tools).
set -euo pipefail
cd "$(dirname "$0")/.."
T="${CTR_TOOLS:-/tmp/ctr-tools}"
"$T/lune/lune" run tests/run.luau
