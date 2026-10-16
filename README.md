# Debian, with zsh

A small Debian testing workspace with zsh, tmux, and sudo.
Based on [ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh).

## Requirements

- Linux `amd64`/x86-64 host or Linux VM; the published image is `linux/amd64`.
- Podman and an OCI runtime; `crun` is required for `--group-add keep-groups` examples.
- Rootless mode: enabled user namespaces, `newuidmap`/`newgidmap`, and subordinate ranges for your user in `/etc/subuid` and `/etc/subgid`.
- Working Podman storage on a local filesystem and its configured rootless network helper (`pasta` or `slirp4netns`).

See [Podman's rootless prerequisites](https://docs.podman.io/en/latest/markdown/podman.1.html#rootless-mode) for host setup.
Keep `/init` as PID 1: do not add `--init` or `--pid=host`, or override startup with a non-root user.
With `keep-id`, use `--user=0:0` for initialization; the shell drops to `admin`.
Desktop sockets, devices, FUSE, and extra capabilities are only needed for their corresponding examples below.

## Table of Content

- [Requirements](#requirements)
- [Start a workspace](#start-a-workspace)
  - [Users and file ownership](#users-and-file-ownership)
    - [Full desktop and nested-container workspace](#full-desktop-and-nested-container-workspace)
      - [Wayland](#wayland)
      - [X11](#x11)
    - [Minimal bare container](#minimal-bare-container)
      - [Empty-command startup error](#empty-command-startup-error)
    - [Share a project folder](#share-a-project-folder)
    - [Allow access to `/dev/fuse`](#allow-access-to-devfuse)
    - [Run nested Podman](#run-nested-podman)
- [Back up and migrate](#back-up-and-migrate)
  - [Archive the workspace](#archive-the-workspace)
  - [Restore into a replacement](#restore-into-a-replacement)
- [Install your preferred tools](#install-your-preferred-tools)

# Start a workspace

> [!NOTE]
> Always pass `/usr/local/bin/as-admin <entrypoint command>` after the image name in the launch examples below.
> Do not pass only `<entrypoint command>` or omit the command from these examples.
> The helper runs the command as `admin` and sets its home and runtime environment.
> Keep `/init` as the container's entrypoint; the appended command does not replace `/init`.

These examples use rootless Podman on Linux.
[GitHub Actions](.github/workflows/deploy-image.yaml) builds and publishes the image to GHCR after its checks pass.
Pull the latest image:

```bash
podman pull ghcr.io/parksnoopy/debian-slim-zsh:latest
```

## Users and file ownership

For host-rootless Podman:

| Option | Meaning |
| --- | --- |
| `--userns=keep-id:uid=1000,gid=1000` | Maps your host user and primary group to the container's `admin` account at `1000:1000` |
| `--user=0:0` | Starts container initialization as container root, not host root |

The shell runs as `admin`; ordinary bind mounts use these host owners:

| Who creates a file in the workspace? | Owner shown on the host |
| --- | --- |
| `admin` | Your host user |
| Container root, including commands run through `sudo` | A subordinate host UID, not host root |

Use `admin` for project files to avoid subordinate-UID ownership.
Extra ownership/ID-mapping options or host `sudo podman` change these rules.

### Full desktop and nested-container workspace

Run from your host project directory without `sudo`.
Requires crun, rootless UID/GID mappings, device permissions, and the selected display and PipeWire/PulseAudio sockets.
Set `XDG_RUNTIME_DIR` to your host session directory.
Remove unavailable devices, sockets, and associated environment options, including `/dev/accel` if absent.

> [!CAUTION]
> Trusted code only: isolation is relaxed and host devices/services are exposed, even through read-only sockets.
> This complete rootless configuration is not runtime-verified.

#### Wayland

The host must run a Wayland compositor; `WAYLAND_DISPLAY` defaults to `wayland-0`.

```bash
podman run -it \
  --hostname debian-workspace \
  --name debian-workspace \
  --runtime crun \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --group-add keep-groups \
  --workdir /home/admin/workspace \
  --volume debian-workspace-home:/home/admin \
  --volume "$PWD:/home/admin/workspace" \
  --volume debian-workspace-storage:/var/lib/containers \
  --mount "type=bind,src=${XDG_RUNTIME_DIR:?Set XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY:-wayland-0},dst=/run/user/1000/wayland-0,ro=true" \
  --mount "type=bind,src=${XDG_RUNTIME_DIR}/pipewire-0,dst=/run/user/1000/pipewire-0,ro=true" \
  --mount "type=bind,src=${XDG_RUNTIME_DIR}/pulse/native,dst=/run/user/1000/pulse/native,ro=true" \
  --env WAYLAND_DISPLAY=wayland-0 \
  --env GDK_BACKEND=wayland \
  --env QT_QPA_PLATFORM=wayland \
  --env PIPEWIRE_REMOTE=pipewire-0 \
  --env PULSE_SERVER=unix:/run/user/1000/pulse/native \
  --device /dev/dri \
  --device /dev/accel \
  --device /dev/snd \
  --device /dev/net/tun \
  --device /dev/fuse \
  --cap-add NET_ADMIN \
  --cap-add SYS_ADMIN \
  --cap-add MKNOD \
  --security-opt label=disable \
  --security-opt apparmor=unconfined \
  --security-opt unmask=ALL \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/tmux -2u
```

#### X11

Use a local Unix display such as `DISPLAY=:0`, not an SSH-forwarded TCP display.
Set `XAUTHORITY` to the host authority file for that display.
The container uses the host's `HOSTNAME` so local Xauthority entries match.
The container receives the display socket and authority file.
Do not disable X11 access control with `xhost +`.

```bash
podman run -it \
  --hostname "${HOSTNAME:?Set HOSTNAME to your host hostname}" \
  --name debian-workspace \
  --runtime crun \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --group-add keep-groups \
  --workdir /home/admin/workspace \
  --volume debian-workspace-home:/home/admin \
  --volume "$PWD:/home/admin/workspace" \
  --volume debian-workspace-storage:/var/lib/containers \
  --mount 'type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,ro=true' \
  --mount "type=bind,src=${XAUTHORITY:?Set XAUTHORITY to your X11 authority file},dst=/run/user/1000/Xauthority,ro=true" \
  --mount "type=bind,src=${XDG_RUNTIME_DIR:?Set XDG_RUNTIME_DIR}/pipewire-0,dst=/run/user/1000/pipewire-0,ro=true" \
  --mount "type=bind,src=${XDG_RUNTIME_DIR}/pulse/native,dst=/run/user/1000/pulse/native,ro=true" \
  --env "DISPLAY=${DISPLAY:?Set DISPLAY}" \
  --env XAUTHORITY=/run/user/1000/Xauthority \
  --env GDK_BACKEND=x11 \
  --env QT_QPA_PLATFORM=xcb \
  --env PIPEWIRE_REMOTE=pipewire-0 \
  --env PULSE_SERVER=unix:/run/user/1000/pulse/native \
  --device /dev/dri \
  --device /dev/accel \
  --device /dev/snd \
  --device /dev/net/tun \
  --device /dev/fuse \
  --cap-add NET_ADMIN \
  --cap-add SYS_ADMIN \
  --cap-add MKNOD \
  --security-opt label=disable \
  --security-opt apparmor=unconfined \
  --security-opt unmask=ALL \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/tmux -2u
```

Choose one display example; both use the same container name and volumes.
Inside the workspace, install the shared client libraries with `~/init.sh install display-clients`.
Install application-specific drivers, toolkits, and clients separately; the topic does not provide a display server.
Default seccomp remains enabled; `NET_ADMIN` affects only the workspace network.
For nested containers, [install the Podman topic and use its sudo wrapper](#run-nested-podman).

Exiting the last tmux session or detaching its original client stops the workspace.
Use Podman's `Ctrl-p`, `Ctrl-q` to detach without stopping it.
Attach to a running workspace with `podman attach debian-workspace`.
Resume a stopped workspace with `podman start -ai debian-workspace`.

Packages persist until container removal; named home/storage volumes survive removal.
Reuse volumes with the same user mapping and storage configuration.

### Minimal bare container

Shell only, without shared folders, desktop access, or nested-container permissions:

```bash
podman run -it --hostname debian-dev --name debian-dev \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

Runs as `admin` with passwordless `sudo`; use trusted code only.
Exit to stop; resume with:

```bash
podman start -ai debian-dev
```

Packages and home files remain until container removal; examples omit `--rm`.

#### Empty-command startup error

If crun reports `cannot find` with an empty command, inspect the local image and failed container (substitute its name):

```bash
podman --version
crun --version
type podman
podman image inspect ghcr.io/parksnoopy/debian-slim-zsh:latest \
  --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
podman inspect debian-dev --format 'Path={{json .Path}} Args={{json .Args}}'
```

Expected entrypoint/Path: `/init`; command/Args: `/usr/local/bin/as-admin /usr/bin/zsh -l`.
Changing UID mappings does not supply a missing command.
Check aliases/wrappers and startup overrides if local values differ; re-pull the published tag if the local image metadata differs.
For a disposable test with explicit startup:

```bash
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --entrypoint /init \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

### Share a project folder

From your host project folder:

```bash
podman run -it --hostname debian-project --name debian-project \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

Guest changes affect the host folder.
On SELinux, use `--volume "$PWD:/home/admin/workspace:Z"` for a dedicated project folder, not your whole home.

### Allow access to `/dev/fuse`

Requires crun and host-user access to `/dev/fuse`:

```bash
podman run -it --hostname debian-fuse --name debian-fuse \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --device /dev/fuse:/dev/fuse \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

Install FUSE tools inside the container; host security policy can still restrict mounts.

### Run nested Podman

Run outer Podman without `sudo`; use `sudo podman` inside.
Requires host crun, subordinate UID/GID ranges, and `/dev/fuse` access.
Admin's nested rootless engine is separate, unconfigured, and unverified; it needs mapping helpers and compatible subordinate ranges.

> [!CAUTION]
> Trusted code only: extra capabilities and relaxed AppArmor, SELinux labeling, and masked paths.
> Default seccomp remains enabled; this outer configuration is not runtime-verified.

On the host:

```bash
podman run -it --hostname debian-nested --name debian-nested \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --cap-add SYS_ADMIN --cap-add MKNOD \
  --security-opt label=disable \
  --security-opt apparmor=unconfined \
  --security-opt unmask=ALL \
  --device /dev/fuse:/dev/fuse \
  --volume debian-nested-storage:/var/lib/containers \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

Inside, install Podman:

```bash
~/init.sh install podman
```

Run an inner container:

```bash
sudo podman run docker.io/library/debian:13-slim id
```

The sudo wrapper supplies runtime/FUSE/non-systemd defaults and `run`/`create` network, logging, cgroup, and security options.
It cannot add missing outer-container permissions or devices.
Plain `podman` passes through unchanged and needs its own rootless setup.
Put the subcommand first; use `sudo /usr/bin/podman` to bypass the wrapper.
Inner `run` removes containers on exit; add `--rm=false` to retain them.

For Compose, from the folder containing its file:

```bash
sudo podman-compose up -d
sudo podman-compose down
```

Use `network_mode: host` per service: it shares the workspace network, not the physical host network.
The sudo Compose wrapper disables automatic pods and retains containers until removal.
Plain `podman-compose` requires working rootless Podman.
This setup provides no separate inner networks or resource limits.
The storage volume persists inner data without a host engine socket; keep its user mapping and storage driver unchanged.
Stop inner containers before exiting.
Resume this workspace with `podman start -ai debian-nested`.

# Back up and migrate

Restores archived home and Debian package state, keeping the replacement's s6-overlay and existing `/usr/local` files.
Other paths receive missing files only; destination-only files remain.
Full container migration is not runtime-verified.

## Archive the workspace

Inside the running source container as `admin`, from `/home/admin/workspace`.
Stop application writers and all inner containers; do not change packages during backup.
This is not an atomic snapshot; back up databases separately.
Install `zstd` in both containers first: `sudo apt-get update && sudo apt-get install -y zstd`.

Optional cache cleanup: run commands for installed tools only; stop sccache if running and adjust its path for custom cache locations.

```bash
ccache --clear
sccache --stop-server
rm -rf -- "${XDG_CACHE_HOME:-$HOME/.cache}/sccache"
pip cache purge
sudo apt-get clean
```

Writes compressed `rootfs.tar.zstd` in `$PWD`, replacing an existing archive:

```bash
sudo tar \
  -I 'zstd -1' \
  --acls \
  --xattrs \
  --xattrs-include='*' \
  --numeric-owner \
  --sparse \
  --exclude='./proc' \
  --exclude='./sys' \
  --exclude='./dev' \
  --exclude='./run' \
  --exclude='./tmp' \
  --exclude='./init' \
  --exclude='./package' \
  --exclude='./command' \
  --exclude='./etc/s6-overlay' \
  --exclude='./etc/hostname' \
  --exclude='./etc/resolv.conf' \
  --exclude='./etc/hosts' \
  --exclude="./${PWD#/}" \
  -cpf rootfs.tar.zstd -C / .
```

Excludes runtime paths, s6-overlay and its bundled dependencies, and `$PWD` including the archive.
Other mounts are included; symlinks are not followed and sockets are skipped.
Host project files remain outside the archive; the bind mount is not a backup.
Keep the archive private and inspect it only after successful creation:

```bash
sudo tar --zstd -tf rootfs.tar.zstd
```

## Restore into a replacement

Create a fresh container with the same architecture, Debian filesystem layout, and compatible user mapping.
From the same host project folder:

```bash
podman run -it --hostname debian-restored --name debian-restored \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

For desktop/nested access, reuse the full launch options with a new name and fresh data volumes.
Do not attach existing data volumes or other project mounts: restoration writes through them.
Inside as `admin`, stop application writers and inner containers.
Assumes `$PWD` is `/home/admin/workspace`, contains `rootfs.tar.zstd`, and matches the source project path; `$HOME` must also match.
Run each pass only after the previous command succeeds.

**1. Add missing system files:**

```bash
sudo tar \
  --zstd \
  --acls \
  --xattrs \
  --xattrs-include='*' \
  --xattrs-exclude='security.selinux' \
  --numeric-owner \
  --sparse \
  --skip-old-files \
  --exclude='./tmp' \
  --exclude='./init' \
  --exclude='./package' \
  --exclude='./command' \
  --exclude='./etc/s6-overlay' \
  --exclude='./etc/hostname' \
  --exclude='./etc/resolv.conf' \
  --exclude='./etc/hosts' \
  --exclude="./${PWD#/}" \
  --exclude="./${HOME#/}" \
  -xpf rootfs.tar.zstd \
  -C /
```

**2. Replace Debian package files, configuration, APT/dpkg state, and home files:**

```bash
sudo tar \
  --zstd \
  --acls \
  --xattrs \
  --xattrs-include='*' \
  --xattrs-exclude='security.selinux' \
  --numeric-owner \
  --sparse \
  --exclude='./etc/s6-overlay' \
  --exclude='./etc/hostname' \
  --exclude='./etc/resolv.conf' \
  --exclude='./etc/hosts' \
  --exclude='./usr/local' \
  --exclude="./${PWD#/}" \
  -xpf rootfs.tar.zstd \
  -C / ./bin ./sbin ./lib ./usr ./etc ./var "./${HOME#/}"
```

Uses archived package versions, not the replacement's newer packages; this is not a clean rollback.

Check `dpkg --audit` and `sudo apt-get check` before package changes, then restart and verify files, ownership, sudo, and required tools.
ACLs/xattrs need compatible filesystems, mappings, and policies; verify metadata warnings even if tar exits successfully.
SELinux labels follow destination policy; restored files may still be incompatible.
Keep the source and archive until verification succeeds.

# Install your preferred tools

Inside the workspace; nothing installs automatically.
Default: Oh My Zsh.

```bash
~/init.sh
```

Choose tools in any order:

```bash
~/init.sh install python-uv git-config oh-my-tmux
```

| Topic | Installs |
| --- | --- |
| `git-config` | Git, delta, Git LFS, and Git settings |
| `golang` | Go |
| `oh-my-tmux` | Oh My Tmux configuration |
| `oh-my-zsh` | Oh My Zsh |
| `python-uv` | Python, uv, and ruff |
| `python-tldr` | Python and the tldr client |
| `nanorc` | Nano and syntax highlighting |
| `podman` | Podman, podman-compose, crun, conmon, fuse-overlayfs, and sudo wrappers for nested containers |
| `sparky-extras` | Sparky APT repositories: core priority 90, testing 89 |
| `display-clients` | Wayland and X11 client libraries, without recommended packages |

Preview without installing:

```bash
~/init.sh install '*' --dry-run
```

Install everything except a selected topic:

```bash
~/init.sh install '*' --exclude oh-my-zsh
```

Use `--list` for topics, `-y` to skip confirmation; reopen the shell after configuration changes.

For project structure and contributor checks, see [Architecture](docs/ARCHITECTURE.md).
