#!/usr/bin/env bash
# Print the fleet's build target as one JSON object.
# The arch picks the runner: native where GitHub has one, QEMU on x64 for 32-bit ARM.
#
# Usage: fleet-target.sh <fleet>
# Needs: balena CLI, logged in.
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <fleet>" >&2
	exit 2
fi

fleet="$(balena fleet "$1" --json)"
device_type="$(jq -r '.device_type' <<<"$fleet")"
arch="$(balena device-type list --all --json |
	jq -r --arg dt "$device_type" '.[] | select(.slug == $dt) | .arch')"

case "$arch" in
aarch64) runner=ubuntu-24.04-arm emulated=false ;;
amd64 | i386 | i386-nlp) runner=ubuntu-24.04 emulated=false ;;
armv7hf | rpi) runner=ubuntu-24.04 emulated=true ;;
*)
	echo "::error::No build runner for arch '${arch}' (device type ${device_type})." >&2
	exit 1
	;;
esac

echo "Fleet $1: ${device_type} (${arch}), build on ${runner}, emulated=${emulated}" >&2
# key is the slug made safe for artifact names.
jq -c --arg slug "$1" --arg device_type "$device_type" --arg arch "$arch" \
	--arg runner "$runner" --argjson emulated "$emulated" '
	{slug: $slug,
	 key: ($slug | ascii_downcase | gsub("[^a-z0-9_-]"; "-")),
	 name: .app_name,
	 device_type: $device_type, arch: $arch, runner: $runner, emulated: $emulated}' <<<"$fleet"
