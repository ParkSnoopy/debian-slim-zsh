#!/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/init-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
export ROOT CHECK_DIR
export HOME="$CHECK_DIR/home" TMPDIR="$CHECK_DIR/tmp" NO_COLOR=1
export COMMAND_LOG="$CHECK_DIR/commands"
export CURL_FAIL=false APT_FAIL=false UPDATE_INVALID=false UPDATE_HASH=b1ec88e
export INIT_BASE_URL= INIT_GITHUB_REPOSITORY=
unset INIT_GITHUB_BRANCH INIT_TARGET_SCRIPT
mkdir -p "$HOME" "$TMPDIR"
touch "$COMMAND_LOG"

# Controlled command fixtures: no package installation or upstream requests.
sudo() {
	echo "sudo $*" >> "$COMMAND_LOG"
	if [ "$APT_FAIL" = true ]; then
		case "$*" in
			'apt install -y golang'|'apt install -y podman crun conmon fuse-overlayfs') return 7 ;;
		esac
	fi
	if [ "$1" = install ]; then
		local -a args=("$@")
		[ "${args[-1]}" = /usr/local/bin/podman ] || return 64
		command install -m 755 "${args[-2]}" "$CHECK_DIR/podman"
	fi
}

python() {
	echo "python $*" >> "$COMMAND_LOG"
}

python3() {
	echo "python3 $*" >> "$COMMAND_LOG"
}

curl() {
	local url= output=
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-o) output="$2"; shift 2 ;;
			https://*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	echo "curl $url" >> "$COMMAND_LOG"
	[ "$CURL_FAIL" = false ] || return 23
	case "$url" in
		*/commits/*)
			echo '{'
			echo "  \"sha\": \"$UPDATE_HASH\","
			echo '  "fixture": true'
			echo '}'
			;;
		*/init.d/*.topic) cp "$ROOT/init.d/${url##*/}" "$output" ;;
		*/src/.zshenv) cp "$ROOT/src/.zshenv" "$output" ;;
		*/src/_init.sh) return 23 ;;
		*/init.sh)
			if [ "$UPDATE_INVALID" = true ]; then
				echo 'if' > "$output"
				return 0
			fi
			cp "$ROOT/init.sh" "$output"
			;;
		*) return 23 ;;
	esac
}
export -f sudo python python3 curl

run() {
	local expected="$1" status=0
	shift
	OUTPUT="$(bash "$ROOT/init.sh" "$@" </dev/null 2>&1)" || status=$?
	if [ "$status" != "$expected" ]; then
		echo "$OUTPUT" >&2
		echo "Expected status $expected; received $status for $*." >&2
		exit 1
	fi
}

run 0 --help
run 0 install --help
run 0 update --help
run 0 --list
[ "$OUTPUT" = $'git-config\ngolang\noh-my-tmux\noh-my-zsh\npython-uv\npython-tldr\nnanorc\npodman' ]
while IFS= read -r topic; do
	[ -f "$ROOT/init.d/$topic.topic" ]
	grep -q "'$topic:" "$ROOT/src/_init.sh"
done <<< "$OUTPUT"
shopt -s nullglob
topic_files=("$ROOT"/init.d/*.topic)
[ "${#topic_files[@]}" -eq 8 ]
legacy_topic_files=("$ROOT"/init.d/*.sh)
[ "${#legacy_topic_files[@]}" -eq 0 ]
run 0 install git-config golang git-config python-uv --exclude python-uv --dry-run
[[ "$OUTPUT" == *'Preview topic: git-config'*'Preview topic: golang'* ]]
[[ "$OUTPUT" != *'Preview topic: python-uv'* ]]
[ "$(echo "$OUTPUT" | grep -c 'Preview topic: git-config')" -eq 1 ]
run 0 install podman nanorc python-tldr python-uv oh-my-zsh oh-my-tmux golang git-config --dry-run
[[ "$OUTPUT" == *'Preview topic: podman'*'Preview topic: nanorc'*'Preview topic: python-tldr'*'Preview topic: python-uv'*'Preview topic: oh-my-zsh'*'Preview topic: oh-my-tmux'*'Preview topic: golang'*'Preview topic: git-config'* ]]
[[ "$OUTPUT" == *'sudo apt install -y podman crun conmon fuse-overlayfs'*'/usr/local/bin/podman'* ]]
run 0 --dry-run
[[ "$OUTPUT" == *'Preview topic: oh-my-zsh'* ]]
[ "$(echo "$OUTPUT" | grep -c 'Preview topic:')" -eq 1 ]
run 0 install '*' --dry-run
[ "$(echo "$OUTPUT" | grep -c 'Preview topic:')" -eq 8 ]
run 0 install '*' --exclude '*' --dry-run
[ "$OUTPUT" = '' ]
run 1 install unknown --dry-run
run 1 install unminimize --dry-run
run 1 install xtradeb --dry-run
run 1 install
run 1 update extra
run 0 install golang
[[ "$OUTPUT" == *'Proceed? [y/N]'*'Cancelled.'* ]]
[ ! -s "$COMMAND_LOG" ]
run 0 update
[[ "$OUTPUT" == *'Checking ParkSnoopy/debian-slim-zsh@main'*'Already up to date'*'Skipped '* ]]
grep -qx 'curl https://api.github.com/repos/ParkSnoopy/debian-slim-zsh/commits/main' "$COMMAND_LOG"
INIT_TARGET_SCRIPT="$CHECK_DIR/default-init.sh" UPDATE_HASH=3333333333333333333333333333333333333333 run 0 update
grep -qx 'curl https://raw.githubusercontent.com/ParkSnoopy/debian-slim-zsh/main/init.sh' "$COMMAND_LOG"
bash -n "$CHECK_DIR/default-init.sh"
INIT_GITHUB_REPOSITORY=fixture/other INIT_GITHUB_BRANCH=release run 0 update
grep -qx 'curl https://api.github.com/repos/fixture/other/commits/release' "$COMMAND_LOG"
INIT_GITHUB_REPOSITORY=fixture/other INIT_GITHUB_BRANCH=release INIT_TARGET_SCRIPT="$CHECK_DIR/custom-init.sh" UPDATE_HASH=3333333333333333333333333333333333333333 run 0 update
grep -qx 'curl https://raw.githubusercontent.com/fixture/other/release/init.sh' "$COMMAND_LOG"
: > "$COMMAND_LOG"

run 0 install golang -y
[[ "$OUTPUT" == *'Topic complete: golang'* ]]
OUTPUT="$(echo y | bash "$ROOT/init.sh" install golang 2>&1)"
[[ "$OUTPUT" == *'Topic complete: golang'* ]]
APT_FAIL=true run 1 install golang python-uv -y
[[ "$OUTPUT" == *'Topic failed: golang'*'Topic complete: python-uv'*'Failed topics: golang'* ]]
run 0 install python-tldr python-uv -y
[[ "$OUTPUT" == *'Topic complete: python-tldr'*'Topic complete: python-uv'* ]]
run 0 install python-uv python-tldr -y
[[ "$OUTPUT" == *'Topic complete: python-uv'*'Topic complete: python-tldr'* ]]
! grep -q '^curl ' "$COMMAND_LOG"

APT_FAIL=true run 1 install podman -y
[ ! -e "$CHECK_DIR/podman" ]
run 0 install podman -y
[[ "$OUTPUT" == *'Topic complete: podman'* ]]
[ -x "$CHECK_DIR/podman" ]
bash -n "$CHECK_DIR/podman"
cp "$CHECK_DIR/podman" "$CHECK_DIR/podman-first"
run 0 install podman -y
cmp "$CHECK_DIR/podman" "$CHECK_DIR/podman-first"

export INIT_BASE_URL=https://fixture.invalid/debian-slim-zsh
export INIT_GITHUB_REPOSITORY=fixture/debian-slim-zsh
run 0 install golang -y
[[ "$OUTPUT" == *'Topic complete: golang'* ]]
grep -qx 'curl https://fixture.invalid/debian-slim-zsh/init.d/golang.topic' "$COMMAND_LOG"
run 0 install podman -y
cmp "$CHECK_DIR/podman" "$CHECK_DIR/podman-first"
grep -qx 'curl https://fixture.invalid/debian-slim-zsh/init.d/podman.topic' "$COMMAND_LOG"
CURL_FAIL=true run 1 install golang -y
[[ "$OUTPUT" == *'Topic failed: golang'* ]]

run 0 update
[[ "$OUTPUT" == *'Already up to date'*'Update '*'.zshenv? [y/N]'*'Skipped '* ]]
[ ! -e "$HOME/.zshenv" ]
OUTPUT="$(echo y | bash "$ROOT/init.sh" update 2>&1)"
cmp "$ROOT/src/.zshenv" "$HOME/.zshenv"
UPDATE_HASH=1111111111111111111111111111111111111111 run 0 update
[ -x "$HOME/init.sh" ]
bash -n "$HOME/init.sh"
cmp "$HOME/init.sh" <(sed 's/^CURRENT_COMMIT_HASH="[0-9a-f]*"/CURRENT_COMMIT_HASH="1111111"/' "$ROOT/init.sh")
OUTPUT="$(bash "$HOME/init.sh" install golang -y 2>&1)"
[[ "$OUTPUT" == *'Topic complete: golang'* ]]
UPDATE_INVALID=true UPDATE_HASH=2222222222222222222222222222222222222222 run 2 update
cmp "$HOME/init.sh" <(sed 's/^CURRENT_COMMIT_HASH="[0-9a-f]*"/CURRENT_COMMIT_HASH="1111111"/' "$ROOT/init.sh")

CURL_FAIL=true
for topic in nanorc oh-my-zsh; do
	status=0
	bash "$ROOT/init.d/$topic.topic" >/dev/null 2>&1 || status=$?
	[ "$status" -eq 23 ]
done
shopt -s nullglob
temporary_files=("$TMPDIR"/*)
[ "${#temporary_files[@]}" -eq 0 ]

# Capture the generated wrapper's exec boundary without running a real engine.
id() {
	[ "$*" = -u ] || return 64
	echo "$PODMAN_TEST_UID"
}
exec() {
	printf '%s\0' "$@" > "$CHECK_DIR/podman-argv"
	echo 'fixture stdout'
	echo 'fixture stderr' >&2
	exit "$PODMAN_TEST_STATUS"
}
export -f id exec
export PODMAN_TEST_UID=0 PODMAN_TEST_STATUS=0
global_args=(/usr/bin/podman --runtime=crun --cgroup-manager=cgroupfs --events-backend=file --storage-driver=overlay --storage-opt=overlay.mount_program=/usr/bin/fuse-overlayfs)
container_args=(--cgroups=disabled --network=host --log-driver=k8s-file --security-opt label=disable --security-opt apparmor=unconfined)

check_podman() {
	local expected_status="$1" status=0
	shift
	: > "$CHECK_DIR/podman-argv"
	bash "$CHECK_DIR/podman" "$@" > "$CHECK_DIR/podman-stdout" 2> "$CHECK_DIR/podman-stderr" || status=$?
	[ "$status" -eq "$expected_status" ]
	if [ "${#expected_args[@]}" -eq 0 ]; then
		[ ! -s "$CHECK_DIR/podman-argv" ]
	else
		cmp "$CHECK_DIR/podman-argv" <(printf '%s\0' "${expected_args[@]}")
		grep -qx 'fixture stdout' "$CHECK_DIR/podman-stdout"
		grep -qx 'fixture stderr' "$CHECK_DIR/podman-stderr"
	fi
}

payload=(--name 'two words' --network=none --rm=false image sh -c 'echo "$HOME"' '')
expected_args=("${global_args[@]}" run "${container_args[@]}" --rm "${payload[@]}")
check_podman 0 run "${payload[@]}"
check_podman 0 container run "${payload[@]}"
PODMAN_TEST_STATUS=37 check_podman 37 run "${payload[@]}"
expected_args=("${global_args[@]}" create "${container_args[@]}" image)
check_podman 0 create image
check_podman 0 container create image
expected_args=("${global_args[@]}" ps --all)
check_podman 0 ps --all
expected_args=("${global_args[@]}" --help)
check_podman 0 --help
expected_args=()
check_podman 2 --log-level=debug run image
grep -q 'Put the subcommand first' "$CHECK_DIR/podman-stderr"
expected_args=(/usr/bin/podman run "${payload[@]}")
PODMAN_TEST_UID=1000 check_podman 0 run "${payload[@]}"
unset -f id exec
echo 'Installer selection, execution, failure, update, and download guards passed.'