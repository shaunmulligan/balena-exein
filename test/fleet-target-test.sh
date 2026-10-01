#!/usr/bin/env bash
# Check fleet-target.sh maps each device type to the right runner, using a fake balena CLI.
set -euo pipefail

cd "$(dirname "$0")"
script=../actions/plan/fleet-target.sh
fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/fleet-target.XXXXXX")"
trap 'rm -rf "$fake_bin"' EXIT
failures=0

# The fake fleet's device type is the fleet slug after "/".
cat >"${fake_bin}/balena" <<'FAKE'
#!/usr/bin/env bash
# org/fail-* fleets fail like a broken API call; org/warn-* write a warning to stderr.
case "$2" in
*/fail-*) echo "BalenaRequestError: Request error: 503" >&2 && exit 3 ;;
# With --json, the CLI can print its error as multi-line JSON on stdout.
*/denied-*) printf '{\n  "error": "Fleet not found"\n}\n' && exit 1 ;;
*/warn-*) echo "balena-cli update check failed" >&2 ;;
esac
case "$1" in
fleet) name="${2#*/}" && printf '{"app_name": "%s", "device_type": "%s"}\n' "$name" "${name#warn-}" ;;
device-type) cat <<'JSON'
[{"slug": "raspberrypi5", "arch": "aarch64"},
 {"slug": "generic-amd64", "arch": "amd64"},
 {"slug": "raspberrypi3", "arch": "armv7hf"},
 {"slug": "raspberry-pi", "arch": "rpi"},
 {"slug": "odd-board", "arch": "riscv64"},
 {"slug": "genericx86-64-ext", "aliases": ["intel-nuc"], "arch": "amd64"}]
JSON
;;
esac
FAKE
chmod +x "${fake_bin}/balena"

expect() {
	local fleet="$1" want_runner="$2" want_emulated="$3" got
	if ! got="$(PATH="${fake_bin}:$PATH" "$script" "$fleet" 2>/dev/null)"; then
		got=error
	fi
	local runner=error emulated=error
	if [[ "$got" != error ]]; then
		runner="$(jq -r '.runner' <<<"$got")"
		emulated="$(jq -r '.emulated' <<<"$got")"
	fi
	if [[ "$runner" != "$want_runner" || "$emulated" != "$want_emulated" ]]; then
		echo "FAIL: ${fleet} -> ${runner}/${emulated}, want ${want_runner}/${want_emulated}"
		failures=$((failures + 1))
		return
	fi
	echo "ok:   ${fleet} -> ${runner} emulated=${emulated}"
}

expect org/raspberrypi5 ubuntu-24.04-arm false
expect org/generic-amd64 ubuntu-24.04 false
expect org/raspberrypi3 ubuntu-24.04 true
expect org/raspberry-pi ubuntu-24.04 true
expect org/intel-nuc ubuntu-24.04 false
expect org/warn-raspberrypi5 ubuntu-24.04-arm false
expect org/odd-board error error
expect org/not-a-device-type error error

msg="$(PATH="${fake_bin}:$PATH" "$script" org/fail-raspberrypi5 2>&1 >/dev/null || true)"
if [[ "$msg" == *"exit 3"*"Request error: 503"* ]]; then
	echo "ok:   failed balena call reports exit code and error"
else
	echo "FAIL: failed balena call reported: ${msg:-nothing}"
	failures=$((failures + 1))
fi

msg="$(PATH="${fake_bin}:$PATH" "$script" org/denied-raspberrypi5 2>&1 >/dev/null || true)"
if [[ "$(head -n 1 <<<"$msg")" == *"exit 1"*"Fleet not found"* && "$msg" == *"can access that fleet"* ]]; then
	echo "ok:   multi-line stdout error is reported on one line, with a hint"
else
	echo "FAIL: multi-line stdout error reported as: ${msg:-nothing}"
	failures=$((failures + 1))
fi

if "$script" >/dev/null 2>&1; then
	echo "FAIL: no argument should exit non-zero"
	failures=$((failures + 1))
else
	echo "ok:   no argument -> usage error"
fi

exit "$failures"
