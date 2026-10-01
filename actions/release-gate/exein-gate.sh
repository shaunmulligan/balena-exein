#!/usr/bin/env bash
# Fail when any VEX file has an exploitable CVE at or above the FAIL_ON severity.
#
# Usage: exein-gate.sh <service>-vex.json ...
# Env:   FAIL_ON              lowest blocking severity: critical or high (default: critical)
#        GATE_OUTPUT          file to append "blocking=<count>" to (optional)
#        GITHUB_STEP_SUMMARY  markdown summary target (default: stdout)
#
# A CVE counts when any of its ratings is blocking and Exein's VEX analysis
# does not mark it as not affected, a false positive, or resolved.
set -euo pipefail

fail_on="${FAIL_ON:-critical}"
case "$fail_on" in
critical) severities='["critical"]' ;;
high) severities='["critical", "high"]' ;;
*)
	echo "FAIL_ON must be critical or high, not ${fail_on}" >&2
	exit 2
	;;
esac

if [[ $# -eq 0 ]]; then
	echo "usage: $0 <service>-vex.json ..." >&2
	exit 2
fi

# shellcheck disable=SC2016 # jq program, not shell.
readonly BLOCKING_FILTER='
	[.vulnerabilities[]?
	 | select((.analysis.state // "") as $s
	          | ["not_affected", "false_positive", "resolved"] | index($s) | not)
	 | select(any(.ratings[]?; (.severity // "" | ascii_downcase) as $s
	              | $severities | index($s)))
	 | .id]
	| unique'

# fd 3 is the markdown summary.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	exec 3>>"$GITHUB_STEP_SUMMARY"
else
	exec 3>&1
fi

total_blocking=0
{
	echo "| Service | Blocking (${fail_on}+) | All CVEs |"
	echo "|---|---:|---:|"
} >&3

for vex in "$@"; do
	service="$(basename "$vex" -vex.json)"
	blocking="$(jq -r --argjson severities "$severities" "${BLOCKING_FILTER} | length" "$vex")"
	all="$(jq '[.vulnerabilities[]?.id] | unique | length' "$vex")"
	total_blocking=$((total_blocking + blocking))
	echo "| ${service} | ${blocking} | ${all} |" >&3
	if [[ "$blocking" -gt 0 ]]; then
		echo "::group::${service}: ${blocking} blocking CVEs"
		jq -r --argjson severities "$severities" "${BLOCKING_FILTER} | .[]" "$vex"
		echo "::endgroup::"
	fi
done

echo >&3
if [[ -n "${GATE_OUTPUT:-}" ]]; then
	echo "blocking=${total_blocking}" >>"$GATE_OUTPUT"
fi

if [[ "$total_blocking" -eq 0 ]]; then
	echo "**Pass:** no ${fail_on}+ CVEs." >&3
	exit 0
fi

echo "**Fail:** ${total_blocking} ${fail_on}+ CVEs." >&3
exit 1
