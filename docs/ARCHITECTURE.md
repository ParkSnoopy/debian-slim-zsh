# Architecture

This document describes the Debian shell workspace, its development checks, and its unimplemented extensions.
The [README](../README.md) is the end-user guide.

## Scope and current boundary

The workspace is a mutable development environment, not an application server or an agent platform.
Users install project compilers, SDKs, headers, and services inside the container rather than on the host.
Keep the base image small and make additional tools optional.

The source provides the Debian/s6 shell foundation.
Image builds and real lifecycle checks remain acceptance requirements, not implied successes.
The optional Podman topic installs a sudo-engine wrapper, but real nested execution remains unverified.
Preconfigured admin-rootless Podman, a host launcher, managed persistent volumes, dynamic service helpers, and desktop forwarding are not implemented.
Host systemd is outside this project's scope.
The original Ubuntu image used dumb-init, not systemd.

## Source layout

| Source | Responsibility |
| --- | --- |
| [Containerfile](../Containerfile) | Base packages, checked s6 archives, admin account, shell defaults, and bundled installer |
| [rootfs](../rootfs/) | User-switch helper, sudo policy, package service policy, and runtime initialization |
| [src/init.sh](../src/init.sh) | Packaged launcher for the installer coordinator |
| [init.sh](../init.sh) | CLI parsing, topic selection, previews, execution, and explicit remote updates |
| [init.d](../init.d/) | Independent Bash installers with the `.topic` extension |
| [src/.zshenv](../src/.zshenv) | Locale, timezone, and user-local executable path |
| [src/.zshrc](../src/.zshrc) | Minimal prompt and completion initialization |
| [src/_init.sh](../src/_init.sh) | Installer command and topic completion |
| [tests/init.bash](../tests/init.bash) | Offline installer integration checks |
| [tests/container.bash](../tests/container.bash) | Engine-backed image and lifecycle checks |
| [Publication workflow](../.github/workflows/deploy-image.yaml) | Build, test, and publish the same image |

## Image and process layout

The image uses `debian:testing-slim` and the s6-overlay version declared in the Containerfile.
The testing tag follows Debian's rolling testing distribution. Package versions can change between builds.
The build installs timezone data but does not set `TZ` or select a custom system timezone.
`src/.zshenv` supplies the shell's timezone default and preserves a nonempty runtime `TZ` override.
The build verifies fixed SHA-256 checksums for the noarch archive and the selected amd64 or arm64 archive.
Other architectures fail explicitly.
`DEBIAN_FRONTEND=noninteractive` applies only to build-time package installation.

```text
Container runtime
└── /init                                      root, PID 1 supervision
    ├── s6-rc: admin-runtime                   root, oneshot
    │   └── /run/user/1000                     admin, mode 0700
    └── CMD: as-admin /usr/bin/zsh -l           admin, UID/GID 1000:1000
        ├── ~/init.sh                          optional tool installation
        ├── project build and test commands
        └── sudo                              system changes
```

- `/init` remains the entrypoint. Do not bypass it with a shell or tmux entrypoint override.
- The default CMD uses [as-admin](../rootfs/usr/local/bin/as-admin) to set `HOME`, `USER`, `LOGNAME`, `SHELL`, and `XDG_RUNTIME_DIR`.
- The helper uses `setpriv --keep-groups` to preserve inherited device groups and does not change the working directory.
- For terminal input, the helper reopens stdin read-write before dropping privileges because s6 supplies a read-only descriptor that can stall tmux output.
- Nonterminal stdin and separate stdout/stderr streams remain unchanged.
- An explicit CMD replaces the complete default command. Admin commands must include `as-admin`.
- Container `exec` also bypasses the default CMD. Reconnection must select `as-admin` explicitly.
- The [sudo policy](../rootfs/etc/sudoers.d/admin) grants passwordless sudo and preserves supplementary groups.
- Its explicit `secure_path` places root-owned local command directories before package command directories for admin's sudo calls.
- The [admin-runtime definition](../rootfs/etc/s6-overlay/s6-rc.d/admin-runtime/) depends on `base` and creates the runtime directory before CMD execution.
- `S6_BEHAVIOUR_IF_STAGE2_FAILS=2` stops startup when service initialization fails.
- `S6_KEEP_ENV=1` preserves runtime environment variables through s6 startup for the supervision tree and CMD, including timezone and desktop settings.
- [policy-rc.d](../rootfs/usr/sbin/policy-rc.d) returns `101` to block supported package service-start requests outside s6 supervision.
- This policy does not emulate `systemctl`, intercept direct systemd API calls, or establish service readiness.

Shell termination triggers s6 shutdown and stops the container without deleting it.
Do not globally enable `S6_CMD_RECEIVE_SIGNALS` for an interactive CMD.
Tmux detach is not a keep-alive contract. An independent container lifetime requires an explicit long-running CMD or service.

Build metadata lives under `/usr/local/share/debian-slim-zsh/`.
`packages.tsv` records package versions at build time, and `s6-overlay-version` records the overlay version.
These records do not track later user package installations.

## Installer flow and topic contract

1. The packaged `~/init.sh` invokes `/usr/local/share/debian-slim-zsh/init.sh`.
2. The coordinator validates topic names, removes duplicates, and applies exclusions without changing caller order.
3. A dry run prints the selected operations before confirmation, downloads, or package changes.
4. An accepted nonempty selection refreshes the APT index once.
5. Each selected topic runs in a separate Bash process. Failed topics do not prevent later topics from running.
6. The coordinator reports all failed topics and returns a nonzero status when any topic fails.

Supported topics are `git-config`, `golang`, `oh-my-tmux`, `oh-my-zsh`, `python-uv`, `python-tldr`, `nanorc`, and `podman`.
The default selection is `oh-my-zsh`.
No topic requires another topic to run first. Each topic declares its own package dependencies.
Keep the coordinator catalogue, previews, completion catalogue, topic files, and tests consistent.

Files in `init.d/` use `.topic`, but their interpreter remains Bash.
CLI topic names do not include the extension.
Local execution uses `init.d/<name>.topic` next to the coordinator, with the packaged topic directory as a fallback when that directory is absent.
The Containerfile copies the complete topic directory into the image.

Remote downloads require an explicit `INIT_BASE_URL` and request `<base>/init.d/<name>.topic`.
The coordinator downloads each complete topic before executing it and removes its temporary file afterward.
Remote self-update also requires `INIT_GITHUB_REPOSITORY` and optionally `INIT_GITHUB_BRANCH`.
No default points to the Ubuntu repository or assumes a published Debian fork exists.
Self-update checks Bash syntax before replacing the coordinator and asks before replacing the user's shell environment.
It does not replace the bundled topic directory.
Remote topic downloads still require `INIT_BASE_URL` on subsequent calls.

The `.topic` rename changes the distribution contract.
An older image with only `.sh` topics cannot acquire a matching local bundle through coordinator-only self-update.
Rebuild the image or replace the coordinator and topic directory together. Legacy aliases are not provided.

## Ownership, devices, and persistent state

The shell account is fixed at UID/GID `1000:1000`.
`--userns=keep-id:uid=1000,gid=1000` maps the rootless host caller and primary group to that container account.
The host caller does not need numeric UID/GID `1000:1000`.
`--user=0:0` selects the entrypoint's identity inside the mapping. It does not change the mapping or select host root.
This explicit user selection overrides keep-id's default process identity so that s6 starts as container root.
The default CMD then invokes `as-admin`, which switches to UID/GID `1000:1000` before starting zsh.

For ordinary bind mounts without additional ID-mapping or ownership-changing options, files created by admin belong to the host caller.
Files created by container UID 0 belong to its mapped subordinate host UID, not host UID 0.
The exact subordinate UID depends on the outer namespace mapping. Do not hardcode it or equate container root with host root.
Sudo-created project files can therefore have inconvenient host ownership even when the outer engine is rootless.
Use admin for project writes. Host-root execution, idmapped mounts, and explicit ownership changes require separate analysis.

Use crun's `keep-groups` when host device access depends on supplementary groups.
Check actual device access through both `as-admin` and sudo, not only numeric group output.
`no-new-privileges` and `nosuid` can prevent sudo or UID-mapping helpers from working.

The README's `/dev/fuse` example passes a host device. It does not configure nested Podman or guarantee FUSE mounts under every security policy.
`CAP_MKNOD` permits device-node creation subject to namespace, filesystem, and security restrictions. It does not grant access to the host Podman engine.
Do not recursively change ownership or permissions on a host workspace.
Do not automatically recreate containers, overwrite mounted homes, prune images, or reset storage during startup or reconnection.

| State | Current location | Same-container restart | Container removal |
| --- | --- | --- | --- |
| APT packages and system configuration | Writable layer | Retained | Lost without a separate backup |
| Admin home, SDKs, and caches | Writable layer unless explicitly mounted | Retained | Lost unless separately persisted |
| Bound project files | Host directory | Retained | Host files remain |
| Runtime directory and sockets | `/run` | Reinitialized by startup | Discarded |

A future launcher must separate home, workspace, runtime, and inner-container storage.
Persisting home does not preserve APT-installed packages.
Image replacement and storage cleanup must be explicit user operations.

## Optional Podman wrapper

[podman.topic](../init.d/podman.topic) installs Podman, crun, conmon, and fuse-overlayfs through APT.
It generates and syntax-checks a wrapper, then installs it as root-owned `/usr/local/bin/podman` with mode `0755`.
The package-owned `/usr/bin/podman` remains unchanged. The topic does not start an engine, pull images, or rewrite Podman configuration files.
The image's explicit sudo policy selects the local wrapper before the package executable, independently of Debian's default search order.

The wrapper executes `/usr/bin/podman` directly, preserving argument boundaries, streams, signals, and exit status without recursive command lookup.
Non-root calls pass through unchanged. Root calls receive these defaults:

| Scope | Defaults |
| --- | --- |
| Every command | `--runtime=crun --cgroup-manager=cgroupfs --events-backend=file --storage-driver=overlay --storage-opt=overlay.mount_program=/usr/bin/fuse-overlayfs` |
| `run` and `create` | `--cgroups=disabled --network=host --log-driver=k8s-file --security-opt label=disable --security-opt apparmor=unconfined` |
| `run` only | `--rm` |

The `container run` and `container create` aliases receive the same defaults as their top-level forms.
Caller arguments follow injected defaults. For example, `run --rm=false` retains the container.
Root calls require command-first syntax, except top-level help and version flags.
Leading global options are rejected rather than silently bypassing run defaults. Native syntax remains available through `sudo /usr/bin/podman`.
The wrapper neither changes outer-container permissions nor configures admin's subordinate mappings.
It does not add creation options to `build` or other subcommands.

## Planned extensions: not implemented

### Nested Podman

Nested Podman can run rootless as admin. Sudo is not an inherent requirement.
The [README's manual example](../README.md#run-nested-podman) instead runs the guest engine as container root through sudo inside a rootless outer container.
That example is unverified and does not implement the planned admin-rootless engine below.

Admin's rootless mode requires working `newuidmap` and `newgidmap` helpers and valid guest subordinate UID/GID ranges.
Those ranges must fit the outer namespace's actual mappings. Installing Podman or copying host range values does not establish valid nested mappings.
Validate helper privileges, mount restrictions, storage ownership, runtime directories, and non-systemd configuration together before claiming support.

The host, guest root, and guest admin engines have separate container inventories and storage.
Host `podman ps` lists the outer workspace, not the guest engine's inner containers.
Guest `sudo podman ps` selects the guest root engine. Guest admin's `podman ps` selects its rootless engine when configured.
Use the selected engine's required global options consistently.
The named storage volume does not connect these engines. Host API socket access would be a separate control path that the example does not provide.

```text
Host rootless Podman
└── Workspace container
    ├── admin zsh                              implemented shell foundation
    ├── admin Podman CLI                       planned
    ├── admin Podman API under s6              planned, optional
    └── Podman / conmon / crun                 planned
        └── inner build and test containers    planned
```

- Prepare Podman, crun, conmon, uidmap, fuse-overlayfs, and the required network helpers in the image.
- Validate the host's subordinate UID/GID ranges and the outer namespace before assigning inner ranges. Start validation with the common 65,536-ID allocation.
- Every inner subordinate ID must exist in the outer mapping. Keep mappings stable with their storage and reject incompatible storage reuse.
- Pass `/dev/fuse` at outer-container creation and keep graphroot outside the outer writable layer.
- Use admin's rootless engine, with graphroot at `/home/admin/.local/share/containers/storage` and runroot under `/run/user/1000`.
- Keep root's engine separate. `sudo podman` selects another engine rather than adding permissions to admin's engine.
- Use standard Podman configuration paths. Do not globally override user configuration through environment variables.
- Start with `cgroupfs`, disabled inner cgroup creation, and file-based logs and events. Do not imply per-inner-container resource limits.
- Initially share the outer network from inner containers. Inner host networking refers to the workspace, not the physical host.
- Validate isolated inner networking and port publication separately.
- Run the optional API directly as admin at `/run/user/1000/podman/podman.sock`. Do not expose it over TCP or substitute the host Podman socket.
- Keep the shell available when the API fails. API restart must not stop all inner containers.
- Stop inner workloads and release their mounts during orderly shutdown. Do not automatically restart every stored inner container on boot.

The future trusted-development profile must validate capabilities, label/seccomp/AppArmor restrictions, and masked paths against the target host.
The original design starts those checks with `cap-add=ALL` and explicit filter relaxations, not default `--privileged`.
Rootless operation cannot grant permissions that the host user does not have.
These settings are not a tested launcher profile.

### Service management

A small helper should support registration/application, start, stop, restart, status, logs, and readiness checks without container recreation.
Compile changed definitions into a new database and apply them through `s6-rc-update` while preserving overlay services.
Do not overwrite a live compiled database or promise automatic rollback after partial transition failures.
Specify each service's user, working directory, environment, foreground command, termination signal, and readiness check.
Do not require an interactive shell configuration to start system services.
Never hide failures behind a success-only `systemctl` wrapper. Test actual responses as well as process existence.
Systemd-dependent test targets require a separate test environment.

### Desktop and device forwarding

Keep `XDG_RUNTIME_DIR=/run/user/1000` and pass the actual Wayland display name.
Mount only selected Wayland, PulseAudio, or PipeWire sockets, not the entire host runtime directory.
A read-only socket mount does not restrict protocol operations.
Forward `/dev/dri`, `/dev/accel`, `/dev/snd`, and `/dev/net/tun` only when present and needed.
Missing optional desktop devices must not block a headless shell. Missing required FUSE access must fail the selected nested-storage path explicitly.
Validate host permissions, inherited groups, and container userspace libraries together.
Prefer shared TUN/VPN management in the outer container. Inner containers need their own explicit device and socket forwarding.

## Development checks

Run from the repository root with Bash, zsh, Shellharden, and actionlint available:

```bash
bash tests/init.bash
for file in init.sh src/init.sh init.d/*.topic tests/*.bash rootfs/usr/local/bin/as-admin rootfs/usr/sbin/policy-rc.d; do
  bash -n "$file"
  shellharden --check "$file"
done
for file in src/.zshenv src/.zshrc src/_init.sh; do
  zsh -n "$file"
done
actionlint .github/workflows/deploy-image.yaml
```

The installer suite uses controlled package and download fixtures in a temporary home.
It checks the exact eight-topic inventory, `.topic` paths, arbitrary order, exclusions, failures, updates, and download cleanup.
Podman checks redirect installation into the fixture directory and capture the generated wrapper's exec arguments with controlled identity and exit status.
They cover repeated installation, package failure, root defaults, non-root passthrough, command aliases, quoting, output streams, and error propagation.
It does not install real packages or contact upstream services.

Build and exercise the image with a working engine:

```bash
docker build -f Containerfile -t debian-slim-zsh:test .
bash tests/container.bash debian-slim-zsh:test
```

The container suite also accepts `CONTAINER_ENGINE=podman` with a Podman-built image.
It checks admin identity, sudo, inherited groups, runtime permissions, offline startup, a real TTY, output streams, and exit status.
The TTY checks require writable terminal stdin and actual pane output from the documented `tmux -2u` command.
It installs `hello` and checks package, configuration, and home persistence across restart of the same container.
It also installs the Podman topic and checks wrapper ownership, sudo command lookup, and root/non-root version commands before and after restart.
Those checks do not establish successful nested container creation.
Lifecycle installation and restart checks print their output and shell trace to expose failures before cleanup removes the containers.
Its noninteractive SIGTERM case explicitly enables CMD signal forwarding.
Test cleanup removes only disposable test containers and temporary files. An absent engine is a failure, not a skipped pass.

The publication workflow builds from the Containerfile and tests the loaded image before pushing it to `ghcr.io/parksnoopy/debian-slim-zsh`.
Its separate nested smoke test installs the Podman topic and runs `hello-world` through the installed `sudo podman` wrapper.
The test requires a successful exit and the expected greeting. It uses a disposable privileged outer Docker container without a host engine socket.
That test does not verify the README's restricted rootless outer-container configuration.
Lifecycle tests still run after a nested smoke-test failure. Either failure blocks publication.
Pushes to `main` publish tags in `YYYYMMDD` format using the `Asia/Seoul` date.
The full image reference is `ghcr.io/parksnoopy/debian-slim-zsh:{YYYYMMDD}`.

Pull requests run the same build and checks without publication.
Repeated successful builds on the same date replace that date's tag.
Do not infer a successful hosted run or publication from local syntax checks.

### Remaining acceptance gates

| Boundary | Required evidence |
| --- | --- |
| Shell foundation | Real image build, TTY prompt/input/signals, noninteractive streams/status, sudo package installation, and restart persistence |
| Host ownership and devices | Bound files owned by the host caller, real device access, and preserved supplementary groups through sudo |
| Nested Podman | Real pull, build, run, stop, multiple file UID/GID values, DNS, external connectivity, and storage recovery after restart |
| Dynamic services | Post-creation registration, actual health response, restart, failed configuration detection, and persistence after restart |
| Optional API | Working CLI with API disabled, actual socket requests when enabled, and independent API restart |
| Desktop integration | Separate real Wayland, audio, GPU, and TUN checks on supported devices |

Do not advance through these boundaries based on static checks or fixtures alone.
Missing hardware or an unavailable engine remains unverified.
Do not install project build dependencies on the host to satisfy a container acceptance gate.

## Technical references

- [s6-overlay: init, CMD, service definitions, and shutdown](https://github.com/just-containers/s6-overlay)
- [Podman run: namespaces, users, groups, and devices](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
- [Debian setpriv](https://manpages.debian.org/trixie/util-linux/setpriv.1.en.html) and [sudoers](https://manpages.debian.org/trixie/sudo/sudoers.5.en.html)
- [Debian containers.conf](https://manpages.debian.org/trixie/golang-github-containers-common/containers.conf.5.en.html) and [storage configuration](https://manpages.debian.org/trixie/containers-storage/containers-storage.conf.5.en.html)
- [Podman API service](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)
- [s6-rc transitions](https://www.skarnet.org/software/s6-rc/s6-rc.html) and [s6-rc-update](https://skarnet.org/software/s6-rc/s6-rc-update.html)
- [Debian service-start policy](https://manpages.debian.org/trixie/init-system-helpers/invoke-rc.d.8.en.html)
- [XDG runtime conventions](https://specifications.freedesktop.org/basedir/latest/) and [Wayland client API](https://wayland.freedesktop.org/docs/html/apb.html)
