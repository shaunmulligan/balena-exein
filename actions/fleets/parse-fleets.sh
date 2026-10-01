#!/usr/bin/env bash
# Print a JSON array of fleet slugs from a newline- or comma-separated list on stdin.
# Blank lines and "#" comments are ignored. Fails on an empty list, a duplicate,
# or an entry that is not a fleet slug (<org>/<fleet>) or name.
set -euo pipefail

fleets="$(tr ',' '\n' | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d')"

if [[ -z "$fleets" ]]; then
	echo "::error::The fleets list is empty." >&2
	exit 1
fi
invalid="$(grep -Ev '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$' <<<"$fleets" || true)"
if [[ -n "$invalid" ]]; then
	echo "::error::Not a fleet slug: $(paste -sd ' ' - <<<"$invalid")" >&2
	exit 1
fi
duplicates="$(sort <<<"$fleets" | uniq -d)"
if [[ -n "$duplicates" ]]; then
	echo "::error::Duplicate fleets: $(paste -sd ' ' - <<<"$duplicates")" >&2
	exit 1
fi

jq -Rnc '[inputs]' <<<"$fleets"
