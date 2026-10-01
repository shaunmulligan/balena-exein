#!/usr/bin/env bash
# Print a JSON array of {name, image} for each service balena build creates.
# build: services use balena's local tag <project>_<service>:<tag>; image: services keep their reference.
# With no compose file, balena builds one service named "main" from the source directory.
#
# Usage: compose-images.sh <project-name> <tag> [source-dir]
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
	echo "usage: $0 <project-name> <tag> [source-dir]" >&2
	exit 2
fi
project="$1"
tag="$2"
source_dir="${3:-.}"

# The only names balena build reads (balena-cli src/utils/compose_ts.ts).
compose_file=""
for name in docker-compose.yml docker-compose.yaml; do
	if [[ -f "${source_dir}/${name}" ]]; then
		compose_file="${source_dir}/${name}"
		break
	fi
done

if [[ -z "$compose_file" ]]; then
	jq -cn --arg image "${project}_main:${tag}" '[{name: "main", image: $image}]'
	exit 0
fi

docker compose -f "$compose_file" config --format json |
	jq -c --arg project "$project" --arg tag "$tag" '
		[.services | to_entries[]
		 | {name: .key,
		    image: (if .value.build then "\($project)_\(.key):\($tag)" else .value.image end)}]'
