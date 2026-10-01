#!/usr/bin/env bash
# Gate pending draft releases on their Exein scans. Finalize a draft that passes.
#
# Drafts are processed oldest first. Processing stops at the first draft whose
# scans are still running, so releases always finalize in build order.
#
# Usage: release-gate.sh <fleet>
# Env:   ANALYZER_API_KEY, BALENA_TOKEN session (read by the CLIs)
#        FAIL_ON      lowest blocking severity: critical or high (default: critical)
#        ENFORCE      "false" finalizes a failing draft and tags it override (default: true)
#        RESULTS_DIR  scan results directory (default: exein-results)
set -euo pipefail

readonly GATE_TAG=exein-gate
readonly SCAN_TAG_PREFIX=exein-scan-

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <fleet>" >&2
	exit 2
fi
fleet="$1"
fail_on="${FAIL_ON:-critical}"
enforce="${ENFORCE:-true}"
results_root="${RESULTS_DIR:-exein-results}"
script_dir="$(dirname "$0")"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

set_tag() {
	balena tag set "$2" "$3" --release "$1" >/dev/null
}

# Print "<service> <scan-id>" per scan tag on the release.
release_scans() {
	jq -r --arg prefix "$SCAN_TAG_PREFIX" '
		.release_tag[]? | select(.tag_key | startswith($prefix))
		| "\(.tag_key | ltrimstr($prefix)) \(.value)"' <<<"$1"
}

# Print "pending", "success", or "error" for all scans on the release.
# An unknown status or a failed lookup counts as pending, so the next run retries.
scans_state() {
	local state=success service scan_id status
	while read -r service scan_id <&5; do
		status="$(analyzer --format json scan status --scan "$scan_id" </dev/null | jq -r '.status // empty')" || status=""
		echo "  ${service} ${scan_id}: ${status:-lookup failed}" >&2
		case "$status" in
		success) ;;
		failed | failure | error | cancelled | canceled) echo error && return ;;
		*) state=pending ;;
		esac
	done 5< <(release_scans "$1")
	echo "$state"
}

gate_release() {
	local release="$1" id commit dir fetch_args=() blocking=0 gate_exit=0 decision
	id="$(jq -r '.id' <<<"$release")"
	commit="$(jq -r '.commit' <<<"$release")"
	dir="${results_root}/release-${id}"

	while read -r service scan_id; do
		fetch_args+=("${service}=${scan_id}")
	done < <(release_scans "$release")
	if [[ ${#fetch_args[@]} -eq 0 ]]; then
		echo "::error::Release ${id} has no ${SCAN_TAG_PREFIX}* tags."
		return 1
	fi

	echo "### Release ${id} (\`${commit:0:7}\`)" >>"$summary"
	RESULTS_DIR="$dir" "$script_dir/exein-fetch.sh" "${fetch_args[@]}"
	FAIL_ON="$fail_on" GATE_OUTPUT="${dir}/gate.env" "$script_dir/exein-gate.sh" "$dir"/*-vex.json || gate_exit=$?
	[[ -f "${dir}/gate.env" ]] && blocking="$(sed -n 's/^blocking=//p' "${dir}/gate.env")"

	for asset in "$dir"/*-vex.json "$dir"/*-report.pdf; do
		[[ -f "$asset" ]] || continue
		balena release-asset upload "$id" "$asset" --key "$(basename "$asset")" --overwrite
	done

	case "$gate_exit" in
	0) decision=pass ;;
	1) decision=fail ;;
	*) echo "::error::gate errored on release ${id}" && return 1 ;;
	esac
	if [[ "$decision" = fail && "$enforce" = false ]]; then
		decision=override
	fi

	set_tag "$id" exein-blocking "$blocking"
	set_tag "$id" exein-fail-on "$fail_on"
	set_tag "$id" "$GATE_TAG" "$decision"
	if [[ "$decision" = fail ]]; then
		echo "::warning::Release ${id} failed the gate: ${blocking} ${fail_on}+ CVEs. Left as draft."
		return
	fi
	balena release finalize "$id"
	echo "Release ${id}: ${decision}, finalized." | tee -a "$summary"
}

releases="$(balena release list "$fleet" --json |
	jq -c --arg tag "$GATE_TAG" '
		[.[] | select(.is_final == false and .status == "success")
		 | select(any(.release_tag[]?; .tag_key == $tag and .value == "pending"))]
		| sort_by(.id) | .[]')"

if [[ -z "$releases" ]]; then
	echo "No pending draft releases."
	exit 0
fi

while read -r release <&4; do
	id="$(jq -r '.id' <<<"$release")"
	echo "Release ${id}:"
	state="$(scans_state "$release")"
	case "$state" in
	pending)
		echo "Release ${id}: scans still running. Stopping to keep build order." | tee -a "$summary"
		break
		;;
	error)
		set_tag "$id" "$GATE_TAG" error
		echo "::error::Release ${id}: a scan failed in Exein. Tagged ${GATE_TAG}=error."
		;;
	success) gate_release "$release" ;;
	esac
done 4<<<"$releases"
