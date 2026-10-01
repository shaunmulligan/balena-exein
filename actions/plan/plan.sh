#!/usr/bin/env bash
# Print the build plan as KEY=value lines for $GITHUB_OUTPUT:
#   fleets  JSON array, one build target per fleet (see fleet-target.sh)
#   images  JSON array of {name, image}, the same for every fleet
#   scans   JSON array, one entry per fleet and service
#
# Usage: plan.sh <fleets-json> <project-name> <tag> <source-dir>
# Needs: balena CLI, logged in; docker compose when the project has a compose file.
set -euo pipefail

if [[ $# -ne 4 ]]; then
	echo "usage: $0 <fleets-json> <project-name> <tag> <source-dir>" >&2
	exit 2
fi
script_dir="$(dirname "$0")"

targets="$(jq -r '.[]' <<<"$1" | while read -r fleet; do
	"$script_dir/fleet-target.sh" "$fleet"
done | jq -sc '.')"
images="$("$script_dir/compose-images.sh" "$2" "$3" "$4")"
scans="$(jq -c --argjson images "$images" \
	'[.[] as $fleet | $images[] | {fleet: $fleet.slug, key: $fleet.key, name: $fleet.name, service: .name}]' \
	<<<"$targets")"

echo "fleets=${targets}"
echo "images=${images}"
echo "scans=${scans}"
