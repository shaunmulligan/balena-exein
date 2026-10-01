#!/usr/bin/env bash
# Print the ID of the Exein Analyzer object with this name. Create the object if it does not exist.
#
# Usage: exein-object.sh <name>
# Env:   ANALYZER_API_KEY  (read by the analyzer CLI)
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <name>" >&2
	exit 2
fi
name="$1"

find_id() {
	analyzer --format json object list |
		jq -r --arg name "$name" '[.[] | select(.name == $name) | .id] | first // empty'
}

id="$(find_id)"
if [[ -z "$id" ]]; then
	echo "Creating Exein object ${name}" >&2
	analyzer object new "$name" >&2
	id="$(find_id)"
fi

if [[ -z "$id" ]]; then
	echo "::error::Exein object ${name} not found after create." >&2
	exit 1
fi
echo "$id"
