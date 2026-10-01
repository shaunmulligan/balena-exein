#!/usr/bin/env bash
# Check plan.sh builds one target per fleet and one scan per fleet and service, using a fake balena CLI.
set -euo pipefail

cd "$(dirname "$0")"
plan=../actions/plan/plan.sh
parse=../actions/fleets/parse-fleets.sh
fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/plan.XXXXXX")"
trap 'rm -rf "$fake_bin"' EXIT
failures=0

cat >"${fake_bin}/balena" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
fleet) printf '{"app_name": "%s", "device_type": "%s"}\n' "${2#*/}" "${2#*/}" ;;
device-type) echo '[{"slug": "raspberrypi5", "arch": "aarch64"}, {"slug": "generic-amd64", "arch": "amd64"}]' ;;
esac
FAKE
chmod +x "${fake_bin}/balena"

check() {
	local desc="$1" got="$2" want="$3"
	if [[ "$got" != "$want" ]]; then
		echo "FAIL: ${desc}: got ${got}, want ${want}"
		failures=$((failures + 1))
		return
	fi
	echo "ok:   ${desc}"
}

fleets="$(printf 'MyOrg/raspberrypi5\nmyorg/generic-amd64 # x86\n' | "$parse")"
out="$(PATH="${fake_bin}:$PATH" "$plan" "$fleets" app SHA fixtures/compose-project 2>/dev/null)"
targets="$(sed -n 's/^fleets=//p' <<<"$out")"
scans="$(sed -n 's/^scans=//p' <<<"$out")"
images="$(sed -n 's/^images=//p' <<<"$out")"

check "two fleets" "$(jq length <<<"$targets")" 2
check "fleet key is artifact-safe" "$(jq -r '.[0].key' <<<"$targets")" myorg-raspberrypi5
check "runners" "$(jq -c '[.[].runner]' <<<"$targets")" '["ubuntu-24.04-arm","ubuntu-24.04"]'
check "images" "$(jq -c '[.[].image]' <<<"$images")" '["app_api:SHA","nginx:1.27"]'
check "scans are fleets x services" "$(jq length <<<"$scans")" 4
check "scan entry" "$(jq -c '.[0]' <<<"$scans")" \
	'{"fleet":"MyOrg/raspberrypi5","key":"myorg-raspberrypi5","name":"raspberrypi5","service":"api"}'

out="$(PATH="${fake_bin}:$PATH" "$plan" '["org/raspberrypi5"]' app SHA fixtures/single-project 2>/dev/null)"
check "single project scans main" "$(sed -n 's/^scans=//p' <<<"$out" | jq -c '[.[].service]')" '["main"]'

if PATH="${fake_bin}:$PATH" "$plan" '["org/unknown-board"]' app SHA fixtures/single-project >/dev/null 2>&1; then
	echo "FAIL: unknown device type should fail the plan"
	failures=$((failures + 1))
else
	echo "ok:   unknown device type fails the plan"
fi

check "parse: commas, comments, blanks" "$(printf 'a/one, b/two\n\n# c/old\n' | "$parse")" '["a/one","b/two"]'
for bad in $'\n# only a comment\n' $'a/x\na/x\n' 'a/b"c' 'a/b/c' 'my fleet'; do
	if "$parse" <<<"$bad" >/dev/null 2>&1; then
		echo "FAIL: parse should reject: $(tr '\n' ' ' <<<"$bad")"
		failures=$((failures + 1))
	else
		echo "ok:   parse rejects: $(tr '\n' ' ' <<<"$bad")"
	fi
done

exit "$failures"
