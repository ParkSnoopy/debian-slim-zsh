# Debian, with zsh

A small Debian 13 stable workspace with zsh, tmux, and sudo.  
Based on [ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh).  

## Requirements

- Linux `amd64`/x86-64 host or VM for the published `linux/amd64` image.  
- Podman with an OCI runtime (`crun` for `--group-add keep-groups`).  
- Rootless mode: user namespaces, `newuidmap`/`newgidmap`, and subordinate ranges in `/etc/subuid` and `/etc/subgid`.  
- Local Podman storage and a configured rootless network helper (`pasta` or `slirp4netns`).  

See [Podman's rootless prerequisites](https://docs.podman.io/en/latest/markdown/podman.1.html#rootless-mode).  
Keep `/init` as PID 1.  
Do not add `--init`, `--pid=host`, or a non-root startup user.  
Desktop sockets, devices, and extra capabilities are optional outside the desktop examples.  

## Table of Content

- [Requirements](#requirements)
- [Start a workspace](#start-a-workspace)
  - [Users and file ownership](#users-and-file-ownership)
    - [Full desktop and nested-container workspace](#full-desktop-and-nested-container-workspace)
      - [Wayland](#wayland)
      - [X11](#x11)
    - [Minimal bare container](#minimal-bare-container)
- [Back up and migrate](#back-up-and-migrate)
  - [Archive the workspace](#archive-the-workspace)
  - [Restore into a replacement](#restore-into-a-replacement)
- [Install your preferred tools](#install-your-preferred-tools)
- [User help](docs/USER_HELP.md)

# Start a workspace

> [!NOTE]
> Pass `/usr/local/bin/as-admin <entrypoint command>` after the image name.  
> Do not pass a bare command or omit it from these examples.  
> The helper sets the `admin` identity and environment.  
> Keep `/init` as the container entrypoint.  

These examples use rootless Podman on Linux.  
[User help](docs/USER_HELP.md) covers startup failures, nested Podman, and verification limits.  
[GitHub Actions](.github/workflows/deploy-image.yaml) publishes the image to GHCR.  

```bash
podman pull ghcr.io/parksnoopy/debian-slim-zsh:latest
```

## Users and file ownership

For host-rootless Podman:  

| Option | Meaning |
| --- | --- |
| `--userns=keep-id:uid=1000,gid=1000` | Maps your host user and primary group to the container's `admin` account at `1000:1000` |
| `--user=0:0` | Starts container initialization as container root, not host root |

Commands run as `admin`.  
Ordinary bind mounts use these host owners:  

| Who creates a file in the workspace? | Owner shown on the host |
| --- | --- |
| `admin` | Your host user |
| Container root, including commands run through `sudo` | A subordinate host UID, not host root |

Use `admin` for project files to avoid subordinate-UID ownership.  
Other mappings or host `sudo podman` change these rules.  

### Full desktop and nested-container workspace

Run from your host project directory without `sudo`.  
Set `XDG_RUNTIME_DIR` to your host session directory.  
Remove unavailable devices, sockets, and associated environment options, including `/dev/accel` if absent.  

> [!CAUTION]
> Trusted code only.  
> These examples relax isolation and expose host devices and services, even through read-only sockets.  

#### Wayland

The host must run a Wayland compositor.  
`WAYLAND_DISPLAY` defaults to `wayland-0`.  

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
Set `XAUTHORITY` to its host authority file.  
`HOSTNAME` must match the host for local cookies.  
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

Choose one of the display examples, which share a container name and volumes.  
Install client libraries inside with `~/init.sh install display-clients`.  
Install application-specific drivers and toolkits separately.  
For nested containers, see [Podman in Podman](docs/USER_HELP.md#podman-in-podman).  
Default seccomp remains enabled.  
`NET_ADMIN` affects only the workspace network.  

Exiting the last tmux session or detaching its original client stops the workspace.  
Use Podman's `Ctrl-p`, `Ctrl-q` to detach without stopping it.  
Attach with `podman attach debian-workspace`.  
Resume with `podman start -ai debian-workspace`.  

Packages persist until container removal.  
Named home/storage volumes survive removal.  
Reuse volumes with the same user mapping and storage configuration.  

### Minimal bare container

Shell only, without desktop access or nested-container permissions:  

```bash
podman run -it --hostname debian-dev --name debian-dev \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

Runs as `admin` with passwordless `sudo`.  
Use trusted code only.  
Exit to stop the container, then resume with:  

```bash
podman start -ai debian-dev
```

Packages and home files remain until container removal.  
These examples omit `--rm`.  
To share a project, add `--volume "$PWD:/home/admin/workspace" --workdir /home/admin/workspace` before the image name.  
Guest writes affect the host folder.  
On SELinux, add `:Z` only for a dedicated project folder, not your whole home.  
For FUSE, add `--device /dev/fuse` and install its tools inside.  
Host device permissions and security policy still apply.  

# Back up and migrate

Restore home and Debian package state while retaining the replacement's s6-overlay and existing `/usr/local` files.  
Other paths receive missing files only.  
Destination-only files remain.  
See [migration verification limits](docs/USER_HELP.md#verification-limits).  

## Archive the workspace

Run as `admin` inside the source container, from `/home/admin/workspace`.  
Stop application writers and inner containers.  
Do not change packages during backup.  
This is not an atomic snapshot.  
Back up databases separately.  
Install `zstd` in both containers: `sudo apt-get update && sudo apt-get install -y zstd`.  

Optional cache cleanup for installed tools only, with custom sccache paths adjusted:  

```bash
ccache --clear
sccache --stop-server
pip cache purge
sudo apt-get clean
rm -rf -- "${XDG_CACHE_HOME:-$HOME/.cache}"
```

Write `rootfs.tar.zstd` in `$PWD`, replacing an existing archive:  

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

This excludes runtime paths, s6-overlay, and `$PWD` including the archive.  
Other mounts are included.  
Symlinks are not followed and sockets are skipped.  
Host project files are not backed up.  
Keep the archive private.  
Inspect it only after creation succeeds:  

```bash
sudo tar --zstd -tf rootfs.tar.zstd
```

## Restore into a replacement

Create a fresh container with the same architecture, Debian layout, and compatible user mapping.  
Run from the same host project folder:  

```bash
podman run -it --hostname debian-restored --name debian-restored \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

For desktop/nested access, reuse the full launch options with a new name and fresh data volumes.  
Do not attach existing data volumes or other project mounts.  
Restoration writes through them.  
Inside as `admin`, stop application writers and inner containers.  
Use the source container's `$HOME` and project path (`/home/admin/workspace`).  
The archive must be in `$PWD`.  
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

This restores archived package versions.  
It is not a clean rollback.  

Check `dpkg --audit` and `sudo apt-get check` before package changes.  
Restart and check files, ownership, sudo, and required tools.  
Check ACL/xattr warnings even if tar succeeds.  
Metadata needs compatible filesystems, mappings, and policies.  
SELinux labels follow destination policy.  
Restored files may still be incompatible.  
Keep the source and archive until verification succeeds.  

# Install your preferred tools

Run inside the workspace.  
The default selection is Oh My Zsh:  

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
| `sparky-extras` | Sparky core APT repository at priority 90 |
| `display-clients` | Wayland and X11 client libraries, without recommended packages |
| `rust` | Stable Rust, complete profile, and `x86_64-unknown-linux-gnu`, without PATH changes |
| `backports` | Debian 13 backports, with individual packages selected explicitly |

Preview without installing:  

```bash
~/init.sh install '*' --dry-run
```

Install everything except a selected topic:  

```bash
~/init.sh install '*' --exclude oh-my-zsh
```

Use `--list` for topics and `-y` to skip confirmation.  
Reopen the shell after configuration changes.  

See [Architecture](docs/ARCHITECTURE.md) for project structure and contributor checks.  
