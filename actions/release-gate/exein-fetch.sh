#!/usr/bin/env bash
# Wait for Exein Analyzer scans to finish, then download the PDF report and VEX for each.
#
# Usage: exein-fetch.sh <service>=<scan-id> ...
# Env:   ANALYZER_API_KEY  (read by the analyzer CLI)
#        RESULTS_DIR       output directory (default: exein-results)
#        SCAN_TIMEOUT      max wait per scan (default: 30m)
set -euo pipefail

results_dir="${RESULTS_DIR:-exein-results}"
scan_timeout="${SCAN_TIMEOUT:-30m}"

if [[ $# -eq 0 ]]; then
	echo "usage: $0 <service>=<scan-id> ..." >&2
	exit 2
fi

mkdir -p "$results_dir"

for arg in "$@"; do
	service="${arg%%=*}"
	scan_id="${arg#*=}"

	# `report --wait` blocks until the whole scan finishes. `vex --wait` only waits ~40s.
	echo "Waiting for ${service} scan ${scan_id}"
	analyzer scan report --scan "$scan_id" --output "${results_dir}/${service}-report.pdf" \
		--wait --timeout "$scan_timeout"
	analyzer scan vex --scan "$scan_id" --output "${results_dir}/${service}-vex.json" --wait
done
