# Debian, with zsh

A small Debian testing workspace with zsh, tmux, and sudo.
Based on [ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh).

## Start a workspace

These examples use rootless Podman on Linux.
[GitHub Actions](.github/workflows/deploy-image.yaml) builds and publishes the image to GHCR after its checks pass.
Pull the latest image:

```bash
podman pull ghcr.io/parksnoopy/debian-slim-zsh:latest
```

### Full desktop and nested-container workspace

Run from your host project directory without `sudo`.
Requires crun, rootless UID/GID mappings, device permissions, and Wayland/PipeWire sockets.
Set `XDG_RUNTIME_DIR` to your session directory; `WAYLAND_DISPLAY` defaults to `wayland-0`.
Remove unavailable devices, sockets, and associated environment options, including `/dev/accel` if absent.

> [!CAUTION]
> Trusted code only: isolation is relaxed and host devices/services are exposed, even through read-only sockets.
> This complete rootless configuration is not runtime-verified.

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

Install required drivers, libraries, and clients separately.
Default seccomp remains enabled; `NET_ADMIN` affects only the workspace network.
For nested containers, [install the Podman topic and use its sudo wrapper](#run-nested-podman).

Exiting the last tmux session or detaching its original client stops the workspace.
Use Podman's `Ctrl-p`, `Ctrl-q` to detach without stopping it.
Attach to a running workspace with `podman attach debian-workspace`.
Resume a stopped workspace with `podman start -ai debian-workspace`.

Packages persist until container removal; named home/storage volumes survive removal.
Reuse volumes with the same user mapping and storage configuration.

## Minimal bare container

Shell only, without shared folders, desktop access, or nested-container permissions:

```bash
podman run -it --hostname debian-dev --name debian-dev \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Runs as `admin` with passwordless `sudo`; use trusted code only.
Exit to stop; resume with:

```bash
podman start -ai debian-dev
```

Packages and home files remain until container removal; examples omit `--rm`.

## Share a project folder

From your host project folder:

```bash
podman run -it --hostname debian-project --name debian-project \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Guest changes affect the host folder.
On SELinux, use `--volume "$PWD:/home/admin/workspace:Z"` for a dedicated project folder, not your whole home.

### Users and file ownership

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

## Allow access to `/dev/fuse`

Requires crun and host-user access to `/dev/fuse`:

```bash
podman run -it --hostname debian-fuse --name debian-fuse \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --device /dev/fuse:/dev/fuse \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Install FUSE tools inside the container; host security policy can still restrict mounts.

## Run nested Podman

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
  ghcr.io/parksnoopy/debian-slim-zsh:latest
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

## Back up and migrate with tar

Restores archived home and Debian package state, keeping the replacement's s6-overlay and existing `/usr/local` files.
Other paths receive missing files only; destination-only files remain.
Full container migration is not runtime-verified.

### Archive the workspace

Inside the running source container as `admin`, from `/home/admin/workspace`.
Stop application writers and all inner containers; do not change packages during backup.
This is not an atomic snapshot; back up databases separately.
Install `zstd` in both containers first: `sudo apt-get update && sudo apt-get install -y zstd`.
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

### Restore into a replacement

Create a fresh container with the same architecture, Debian filesystem layout, and compatible user mapping.
From the same host project folder:

```bash
podman run -it --hostname debian-restored --name debian-restored \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
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

## Install your preferred tools

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

Preview without installing:

```bash
~/init.sh install '*' --dry-run
```

Install everything except a selected topic:

```bash
~/init.sh install '*' --exclude oh-my-zsh
```

Use `--list` for topics, `-y` to skip confirmation; reopen the shell after configuration changes.

## Open another terminal

For a running workspace:

```bash
podman exec -it debian-workspace as-admin zsh -l
```

For tmux:

```bash
podman exec -it debian-workspace as-admin tmux -2u attach-session
```

Substitute your container name; tmux requires an existing session.
Keep the original workspace process running; exiting its shell or last tmux session stops the container.

For project structure and contributor checks, see [Architecture](docs/ARCHITECTURE.md).
