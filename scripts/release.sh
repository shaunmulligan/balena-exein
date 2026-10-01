#!/usr/bin/env bash
# Tag a release whose internal action refs point at the release tag, not @main.
#
# On main, the reusable workflows use this repo's actions and workflows at @main. A caller
# pinned to vX.Y.Z must get the actions from vX.Y.Z too, so the tag goes on a
# commit, off main, that rewrites those refs.
#
# Usage: scripts/release.sh vX.Y.Z
set -euo pipefail

readonly REPO=shaunmulligan/balena-exein

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 vX.Y.Z" >&2
	exit 2
fi
version="$1"
major="${version%%.*}"

if [[ -n "$(git status --porcelain)" ]]; then
	echo "Working tree is not clean." >&2
	exit 1
fi
if [[ "$(git rev-parse --abbrev-ref HEAD)" != main ]]; then
	echo "Release from main." >&2
	exit 1
fi

git switch --detach --quiet
# Both action refs (actions/<name>) and nested workflow refs (.github/workflows/<file>).
sed -i.bak -E "s#(${REPO}/(actions/[a-z-]+|\.github/workflows/[a-z-]+\.yml))@main#\1@${version}#g" .github/workflows/*.yml
rm -f .github/workflows/*.yml.bak
if git diff --quiet; then
	echo "No @main refs to rewrite." >&2
	git switch --quiet main
	exit 1
fi

git commit --quiet -s -S -am "Release ${version}"
git tag -s "$version" -m "Release ${version}"
git tag -f -s "$major" -m "Release ${version}"
git switch --quiet main

echo "Tagged ${version} and moved ${major}. Push with:"
echo "  git push origin ${version} && git push --force origin ${major}"
