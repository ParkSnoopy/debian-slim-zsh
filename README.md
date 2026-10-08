# Debian development workspace

This project adapts [ParkSnoopy/ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh) to Debian 13 and s6-overlay.
[plan.md](plan.md) defines the target architecture and acceptance gates.
The original image uses `dumb-init`, not systemd. This image replaces `dumb-init` with s6-overlay.

## Implementation boundary

The current changes implement the phase-1 shell foundation. Real image build and lifecycle checks remain required before phase 1 is complete.
Podman-in-Podman, the host launcher, persistent volume mappings, dynamic service management, and desktop forwarding remain later phases.
The image does not yet include Podman or claim nested-container support.

## Image contract

- `Containerfile` uses `debian:13-slim` and s6-overlay `3.2.3.2`. The build verifies fixed archive checksums for amd64 or arm64.
- `/init` runs as root. The default CMD runs `/usr/local/bin/as-admin /usr/bin/zsh -l`.
- `admin` has UID/GID `1000:1000`, home `/home/admin`, and passwordless sudo. This image is for trusted development code.
- `as-admin` sets the account environment and preserves inherited supplementary groups. It does not change the working directory.
- The `admin-runtime` s6-rc oneshot creates `/run/user/1000` with owner `1000:1000` and mode `0700`.
- Shell termination stops the container through s6. Starting the same container preserves its writable layer.
- Explicit CMD overrides retain `/init` but replace the entire default command. Commands that need admin identity must include `as-admin`.
- `exec` bypasses the default CMD. Shell reconnection must also select `as-admin` explicitly.
- Rootless Podman with keep-id requires `--user=0:0` for init. Host ownership and device-group acceptance belong to phase 2.
- `policy-rc.d` returns `101` to block supported package service-start requests. It does not emulate `systemctl` or prove service readiness.
- Build-time APT noninteractive mode does not persist in the runtime environment.
- `/usr/local/share/debian-slim-zsh/packages.tsv` records build-time package versions. The adjacent `s6-overlay-version` records the overlay version.

Boot and shell startup do not install packages or download bootstrap code. No startup script replaces home files or changes workspace ownership.

## Bootstrap structure

`src/init.sh` dispatches to the bundled coordinator at `/usr/local/share/debian-slim-zsh/init.sh`.
The coordinator uses adjacent `init.d/` topics by default. A downloaded coordinator can use the installed topic directory.
Selection, exclusions, confirmation, dry runs, and aggregated topic failures retain their existing interfaces.
The only topics are `git-config`, `golang`, `oh-my-tmux`, `oh-my-zsh`, `python-uv`, `python-tldr`, and `nanorc`.
The default is `oh-my-zsh`. Selections keep their requested order without duplicates. No topic must run before another.
Each topic installs its own package dependencies. The coordinator refreshes the package index once before any selected topic runs.

Remote topic downloads require an explicit `INIT_BASE_URL`. Remote updates also require `INIT_GITHUB_REPOSITORY`, with optional `INIT_GITHUB_BRANCH`.
No default points to the Ubuntu repository or assumes a published Debian fork exists.
Remote updates replace the coordinator, not the image's bundled topics. Remote topic selection still requires `INIT_BASE_URL` on subsequent calls.
Updates check Bash syntax before replacement and request confirmation before replacing `.zshenv`.

Optional topic installation remains separate from image acceptance. Live SDK and application installations require their own checks.

## Development checks

1. Run `bash tests/init.bash` for offline installer regression checks.
2. Run `bash -n` and `shellharden --check` on each Bash script separately. Run `zsh -n` on the shell configuration and completion.
3. Build the image with `docker build -f Containerfile -t debian-slim-zsh:test .`.
4. Run `bash tests/container.bash debian-slim-zsh:test` against a working engine.
5. Run `actionlint .github/workflows/deploy-image.yaml` after workflow changes.

The container suite accepts `CONTAINER_ENGINE=podman` as an explicit engine selection. It does not test the later keep-id launcher profile.
The suite checks Debian identity, admin identity, inherited groups, sudo, runtime permissions, offline startup, real TTY input, and noninteractive output/exit status.
It installs `hello` in a disposable container and checks package, configuration, and home persistence across restart.
Its SIGTERM check enables s6's CMD signal forwarding for a noninteractive command. The default interactive shell does not enable this option.
Test cleanup removes only the suite's disposable containers and temporary files. An absent engine is a failure, not a skipped pass.

CI builds from `Containerfile` and runs the container suite before publishing the tested image to `ghcr.io/parksnoopy/debian-slim-zsh`.
Pull requests run the same checks without publication. Local static checks do not establish a successful CI run or registry publication.
