#!/usr/bin/env bash
# Check exein-gate.sh in both directions against fixture VEX files.
set -euo pipefail

cd "$(dirname "$0")"
gate=../actions/release-gate/exein-gate.sh
fixtures=fixtures
failures=0

expect() {
	local want="$1" fail_on="$2"
	shift 2
	local got=0
	FAIL_ON="$fail_on" GITHUB_STEP_SUMMARY=/dev/null "$gate" "$@" >/dev/null 2>&1 || got=$?
	if [[ "$got" -ne "$want" ]]; then
		echo "FAIL: FAIL_ON=${fail_on} $* exited ${got}, want ${want}"
		failures=$((failures + 1))
		return
	fi
	echo "ok:   FAIL_ON=${fail_on} $* -> ${got}"
}

expect 0 critical "${fixtures}/clean-vex.json"
expect 0 high "${fixtures}/clean-vex.json"
expect 1 critical "${fixtures}/vulnerable-vex.json"
expect 1 high "${fixtures}/vulnerable-vex.json"
expect 0 critical "${fixtures}/high-only-vex.json"
expect 1 high "${fixtures}/high-only-vex.json"
expect 1 critical "${fixtures}/clean-vex.json" "${fixtures}/vulnerable-vex.json"
expect 2 medium "${fixtures}/clean-vex.json"
expect 2 critical

out="$(mktemp "${TMPDIR:-/tmp}/gate-output.XXXXXX")"
FAIL_ON=high GATE_OUTPUT="$out" GITHUB_STEP_SUMMARY=/dev/null "$gate" "${fixtures}/vulnerable-vex.json" >/dev/null || true
if [[ "$(cat "$out")" != "blocking=2" ]]; then
	echo "FAIL: GATE_OUTPUT was '$(cat "$out")', want 'blocking=2'"
	failures=$((failures + 1))
else
	echo "ok:   GATE_OUTPUT -> blocking=2"
fi
rm -f "$out"

exit "$failures"
