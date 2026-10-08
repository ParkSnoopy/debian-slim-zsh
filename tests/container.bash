#!/bin/bash
set -euo pipefail
trap 'echo "Container check failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ENGINE="${CONTAINER_ENGINE:-docker}"
IMAGE="${1:?Specify the image to test}"
command -v "$ENGINE" >/dev/null || {
	echo "Container engine unavailable: $ENGINE" >&2
	exit 1
}
"$ENGINE" info >/dev/null
"$ENGINE" image inspect "$IMAGE" >/dev/null
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/container-check.XXXXXX")"
NAME="debian-slim-zsh-${CHECK_DIR##*.}"
trap '"$ENGINE" rm -f "$NAME" "$NAME-signal" >/dev/null 2>&1; rm -rf "$CHECK_DIR"' EXIT

"$ENGINE" run --rm --network none --user 0:0 --group-add 1234 "$IMAGE" \
	/usr/local/bin/as-admin /usr/bin/zsh -lec '
		. /etc/os-release
		[[ "$ID" == debian ]]
		[[ "$TZ" == Asia/Seoul ]]
		[[ "$(id -u):$(id -g)" == 1000:1000 ]]
		[[ " $(id -G) " == *" 1234 "* ]]
		[[ "$HOME:$USER:$LOGNAME:$SHELL" == /home/admin:admin:admin:/usr/bin/zsh ]]
		[[ "$XDG_RUNTIME_DIR" == /run/user/1000 ]]
		[[ "$(stat -c %u:%g:%a "$XDG_RUNTIME_DIR")" == 1000:1000:700 ]]
		[[ "$(cat /proc/1/comm)" == s6-svscan ]]
		[[ -z "${DEBIAN_FRONTEND+x}" ]]
		[[ "$(sudo -n id -u)" == 0 ]]
		[[ " $(sudo -n id -G) " == *" 1234 "* ]]
		~/init.sh --help
		~/init.sh --dry-run
	'

"$ENGINE" run --rm --network none --user 0:0 \
	--env TZ=Etc/UTC --env 'WORKSPACE_TEST_VALUE=two words' "$IMAGE" \
	/usr/local/bin/as-admin /usr/bin/zsh -lec '
		[[ "$TZ" == Etc/UTC ]]
		[[ "$WORKSPACE_TEST_VALUE" == "two words" ]]
	'

status=0
"$ENGINE" run --rm --network none --user 0:0 "$IMAGE" \
	/usr/local/bin/as-admin bash -c 'echo payload; echo diagnostic >&2; exit 37' \
	>"$CHECK_DIR/stdout" 2>"$CHECK_DIR/stderr" || status=$?
[ "$status" -eq 37 ]
grep -qx payload "$CHECK_DIR/stdout"
grep -qx diagnostic "$CHECK_DIR/stderr"

# Allocate a real host PTY and keep the image default CMD unchanged.
export CONTAINER_ENGINE="$ENGINE" TEST_IMAGE="$IMAGE"
printf '[[ -o interactive ]] && [[ "$(id -un)" == admin ]] && echo TTY_OK\nexit\n' |
	timeout 30 script -qec '"$CONTAINER_ENGINE" run --rm -it --network none --user 0:0 "$TEST_IMAGE"' \
	"$CHECK_DIR/tty"
grep -qx $'TTY_OK\r' "$CHECK_DIR/tty"

"$ENGINE" create --name "$NAME" --user 0:0 "$IMAGE" \
	/usr/local/bin/as-admin bash -exc '
		if [ -f /etc/workspace-lifecycle-test ]; then
			hello >/dev/null
			[ "$(cat "$HOME/lifecycle-test")" = preserved ]
			[ "$(cat /etc/workspace-lifecycle-test)" = preserved ]
			echo RESTART_OK
		else
			sudo -n apt-get update
			sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends hello
			~/init.sh install podman -y
			echo preserved > "$HOME/lifecycle-test"
			echo preserved | sudo -n tee /etc/workspace-lifecycle-test
			echo INSTALL_OK
		fi
		[ "$(stat -c %u:%g:%a /usr/local/bin/podman)" = 0:0:755 ]
		[ "$(sudo -n bash -c "command -v podman")" = /usr/local/bin/podman ]
		podman --version
		sudo -n podman --version
	' >/dev/null
ID="$("$ENGINE" inspect --format '{{.Id}}' "$NAME")"
"$ENGINE" start -a "$NAME" | tee "$CHECK_DIR/first"
[ "$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$NAME")" -eq 0 ]
grep -qx INSTALL_OK "$CHECK_DIR/first"
"$ENGINE" start -a "$NAME" | tee "$CHECK_DIR/restart"
[ "$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$NAME")" -eq 0 ]
grep -qx RESTART_OK "$CHECK_DIR/restart"
[ "$("$ENGINE" inspect --format '{{.Id}}' "$NAME")" = "$ID" ]

"$ENGINE" run -d --name "$NAME-signal" --network none --user 0:0 \
	-e S6_CMD_RECEIVE_SIGNALS=1 "$IMAGE" /usr/local/bin/as-admin bash -ec '
		trap "exit 23" TERM
		touch /home/admin/signal-ready
		while :; do sleep 1; done
	' >/dev/null
ready=false
for attempt in {1..100}; do
	if "$ENGINE" exec "$NAME-signal" test -f /home/admin/signal-ready; then
		ready=true
		break
	fi
	sleep 0.1
done
[ "$ready" = true ]
"$ENGINE" stop --time 20 "$NAME-signal" >/dev/null
[ "$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$NAME-signal")" -eq 23 ]
echo 'Container identity, sudo, TTY, exit status, restart persistence, and SIGTERM checks passed.'
