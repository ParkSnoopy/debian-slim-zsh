# Debian, with zsh

A small Debian testing workspace with zsh, tmux, and sudo.
Enter the shell, install the tools you need, and keep your project dependencies inside the container.
Based on [ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh).

## Start a workspace

These examples use rootless Podman on Linux.
[GitHub Actions](.github/workflows/deploy-image.yaml) builds and publishes the image to GHCR after its checks pass.
Pull the latest image:

```bash
podman pull ghcr.io/parksnoopy/debian-slim-zsh:latest
```

### Full desktop and nested-container workspace

Run this from your host project directory, as your normal user without `sudo`.
It opens tmux with project files, persistent home and Podman storage, desktop sockets, GPU/audio devices, TUN, and FUSE access.

The host needs crun, configured rootless UID/GID mappings, and permission to access each device.
This example assumes a Wayland desktop with PipeWire and its PulseAudio-compatible socket.
`XDG_RUNTIME_DIR` must point to your host session directory.
`WAYLAND_DISPLAY` selects its Wayland socket, defaulting to `wayland-0`.
Remove unavailable device or socket mounts and their corresponding environment options before running the command.
For example, many hosts do not have `/dev/accel`.

> **Use only with trusted code.**
> This example disables several isolation controls and exposes host devices and desktop services.
> Read-only socket mounts still permit communication with those services.
> This complete rootless configuration is not yet runtime-verified.

```bash
podman run -it \
  --hostname debian-workspace \
  --name debian-workspace \
  --runtime crun \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --group-add keep-groups \
  --workdir /home/admin/host \
  --volume debian-workspace-home:/home/admin \
  --volume "$PWD:/home/admin/host" \
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
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt unmask=ALL \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/tmux -2u new-session -A -s workspace
```

Device and socket access does not install GPU drivers, GUI libraries, audio clients, or VPN tools.
`NET_ADMIN` applies inside the container's network namespace, not the physical host network.
For nested containers, [install the Podman topic and use its sudo wrapper](#run-nested-podman).

Exit the last tmux session to stop the workspace.
Detaching the original tmux client also ends the container command.
Detach Podman with `Ctrl-p`, `Ctrl-q` instead to leave it running.
Attach to a running workspace with `podman attach debian-workspace`.
Resume a stopped workspace with `podman start -ai debian-workspace`.

Installed packages remain in this container until you remove it.
The named volumes retain home files and nested Podman storage even after container removal.
Reuse those volumes only with the same user mapping and storage configuration.

## Minimal bare container

Open a shell without shared folders, desktop sockets, extra devices, or nested-container permissions:

```bash
podman run -it --hostname debian-dev --name debian-dev \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

You work as `admin` and can use `sudo` without a password.
Use this workspace for code you trust.

Exit the shell to stop the container.
Resume the same workspace later:

```bash
podman start -ai debian-dev
```

Your installed packages and home files stay in that container until you remove it.
The examples do not use `--rm`.

## Share a project folder

Run this from the host project folder you want to work on:

```bash
podman run -it --hostname debian-project --name debian-project \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Changes in `/home/admin/workspace` also change your host files.
On SELinux hosts, use `--volume "$PWD:/home/admin/workspace:Z"` for a dedicated project directory.
Do not relabel your whole home directory.

### Users and file ownership

Run these host commands as your normal user, without `sudo`.
The two user options have different purposes:

| Option | Meaning |
| --- | --- |
| `--userns=keep-id:uid=1000,gid=1000` | Maps your host user and primary group to the container's `admin` account at `1000:1000` |
| `--user=0:0` | Starts container initialization as container root, not host root |

After initialization, the default shell runs as `admin`.
For an ordinary shared folder without extra ownership-changing or ID-mapping options:

| Who creates a file in the workspace? | Owner shown on the host |
| --- | --- |
| `admin` | Your host user |
| Container root, including commands run through `sudo` | A subordinate host UID, not host root |

Files created through `sudo` can still have inconvenient ownership.
Use admin for ordinary project files.
These rules assume the outer Podman runs rootless. They do not apply unchanged to host `sudo podman`.

## Allow access to `/dev/fuse`

If your application needs FUSE, pass the device when you create its workspace.
The host must provide `/dev/fuse`, and your host user must have permission to access it.
This example also requires `crun` on the host:

```bash
podman run -it --hostname debian-fuse --name debian-fuse \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --device /dev/fuse:/dev/fuse \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Install the FUSE tools your application needs inside the container.
Device access alone does not guarantee that every FUSE mount works under your host's security policy.

## Run nested Podman

Podman is optional. Install the `podman` topic inside a workspace created with the options below.
Run the outer container as your normal host user, without `sudo`.
Inside the workspace, this example uses `sudo podman`, not admin's rootless Podman engine.
The host needs rootless Podman, crun, configured subordinate UID/GID ranges, and access to `/dev/fuse`.

Guest Podman can also run rootless as `admin`. It does not inherently require `sudo`.
That mode needs working UID/GID mapping helpers and subordinate ranges that fit within the outer container's mappings.
The image and example do not configure or verify admin's nested rootless engine.
`sudo podman` uses a separate engine and storage, not admin's engine with extra permissions.

> **Use only with trusted code.**
> This example adds container capabilities and disables security filters to allow nested mounts.
> It is an unverified example, not a tested nested-container profile.

On the host:

```bash
podman run -it --hostname debian-nested --name debian-nested \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --cap-add SYS_ADMIN --cap-add MKNOD \
  --security-opt label=disable \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt unmask=ALL \
  --device /dev/fuse:/dev/fuse \
  --volume debian-nested-storage:/var/lib/containers \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Inside that workspace, install the tools:

```bash
~/init.sh install podman
```

Then run an inner container:

```bash
sudo podman run docker.io/library/debian:13-slim id
```

The installed wrapper supplies the nested runtime, FUSE storage, and non-systemd defaults for `sudo podman`.
It adds the network, logging, cgroup, and security options to `run` and `create` commands.
Plain `podman` as admin passes through unchanged and still needs its own rootless setup.
The wrapper cannot add the outer container's device access or permissions after creation.

`sudo podman run` removes the inner container when it exits. Add `--rm=false` to retain it.
Put the subcommand first, as in `sudo podman run ...` or `sudo podman ps`.
Use `sudo /usr/bin/podman` to bypass the wrapper when you need full control of global options.

Inner `--network=host` shares the workspace network, not the physical host network.
This example does not provide separate inner-container networks or resource limits.

The named volume retains inner images and data without using the host Podman socket.
Do not reuse it with a different user mapping or storage driver.
Stop inner containers before exiting the workspace shell.
Resume this workspace with `podman start -ai debian-nested`.

## Install your preferred tools

Run these commands inside the workspace.
Nothing installs automatically when you open a shell.

Install Oh My Zsh, the default topic:

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
| `podman` | Podman, crun, conmon, fuse-overlayfs, and nested defaults for `sudo podman` |

Preview without installing:

```bash
~/init.sh install '*' --dry-run
```

Install everything except a selected topic:

```bash
~/init.sh install '*' --exclude oh-my-zsh
```

Use `--list` to list topics or `-y` to skip confirmation.
Open a new shell after changing your shell configuration.

## Open another terminal

While the workspace is running:

```bash
podman exec -it debian-workspace as-admin zsh -l
```

For tmux:

```bash
podman exec -it debian-workspace as-admin tmux -2u attach-session -t workspace
```

These commands target the full workspace. Substitute `debian-dev` for the minimal example.
The tmux attach command requires the full example's existing `workspace` session.
Keep the original workspace process running while using these extra terminals.
Exiting the original shell or last tmux session stops the container.

For project structure and contributor checks, see [Architecture](docs/ARCHITECTURE.md).
