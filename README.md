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

> [!CAUTION]
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

Device and socket access does not install GPU drivers, GUI libraries, audio clients, or VPN tools.
Seccomp uses Podman's default profile.
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

> [!CAUTION]
> **Use only with trusted code.**
> This example adds capabilities and relaxes AppArmor, SELinux labeling, and masked paths for nested mounts.
> It keeps Podman's default seccomp profile.
> It is an unverified example, not a tested nested-container profile.

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

The topic also installs `podman-compose`. From a folder with a Compose file, use:

```bash
sudo podman-compose up -d
sudo podman-compose down
```

Set `network_mode: host` on each service to use the workspace network without creating inner bridge networks.
The sudo wrapper disables automatic pods and retains Compose containers until you remove them.
Plain `podman-compose` as admin uses the package defaults and needs working rootless Podman.

Inner `--network=host` shares the workspace network, not the physical host network.
This example does not provide separate inner-container networks or resource limits.

The named volume retains inner images and data without using the host Podman socket.
Do not reuse it with a different user mapping or storage driver.
Stop inner containers before exiting the workspace shell.
Resume this workspace with `podman start -ai debian-nested`.

## Back up and migrate with tar

This procedure restores all archived home files into a replacement container.
It also replaces Debian package files, configuration, and package-manager state with the archived versions.
Other system paths receive only missing files; the replacement image retains s6-overlay and existing `/usr/local` files.
It does not compare timestamps or package versions, and it does not delete destination-only files.
The complete container migration procedure is not yet runtime-verified.

### Archive the workspace

Stop application writers and all inner containers first, including any run by admin's rootless engine.
Do not install or update packages during the archive.
Keep the source workspace running while creating the archive.
This is not an atomic snapshot. Use application-specific backups for databases.

Run these commands inside the source workspace as `admin`.
This example assumes your current directory is the host-mounted project folder `/home/admin/workspace`.
The command excludes `$PWD` and writes `rootfs.tar` there, replacing any existing file with that name:

```bash
sudo tar \
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
  -cpf rootfs.tar -C / .
```

Container root creates the archive. The archive itself is excluded from the backup.
Proceed only if the archive command exits successfully. A failed command can leave a partial archive.

The runtime directories, `/tmp`, s6-overlay installation and service definitions, and the current directory are excluded by this command.
The replacement image supplies `/init`, `/package`, `/command`, and `/etc/s6-overlay`.
Excluding all of `/package` also excludes s6-overlay's versioned dependencies, so old versions are not added alongside the replacement's files.
Project files in `$PWD` remain in the host folder and are available whenever the same bind mount is attached.
The bind mount is not a separate backup of those files.
Other mounts are traversed, including home volumes, nested Podman storage, and project folders mounted elsewhere.
Symbolic links are stored as links, not followed.
Sockets are not archived, and inaccessible or changing files can prevent a complete backup.
The archive can contain credentials and private project files. Keep it private.
ACLs and extended attributes can require compatible filesystems, mappings, and security policies on the destination.
Review attribute warnings and verify required metadata after restore; tar can report attribute failures without a failing exit status.

Inspect the archive before restoration:

```bash
sudo tar -tf rootfs.tar
```

A readable archive alone does not prove that application data is consistent.

### Restore into a replacement

Create a fresh container from the image you want to keep.
Use the same architecture and compatible user mapping as the source.
Do not attach existing data volumes or project folders at other paths during restoration: archive writes would also change those mounts.
Run restoration from the same guest project path as the source; `$PWD` is excluded and that project bind mount can be reused.
On the host, run this from the same project folder to start the replacement without a backup mount:

```bash
podman run -it --hostname debian-restored --name debian-restored \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

For a full workspace, use its launch options with a different container name and fresh data volumes instead of existing ones.
Leave other host project folders unmounted until restoration is complete.
Stop any application writers or inner containers in the replacement before restoring.

Run the following commands inside the replacement as `admin`, with `$PWD` at the same guest project path as the source and `$HOME` matching the archived home path.
This example assumes you are already in `/home/admin/workspace` and `rootfs.tar` is in that directory.
First restore missing files outside home, without changing existing files or directory metadata:

```bash
sudo tar \
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
  -xpf rootfs.tar \
  -C /
```

Proceed only if that command succeeds.
Then restore the Debian package trees together, replacing matching files and directory metadata.
This includes `/usr`, `/etc`, `/var`, and the standard binary/library links, rather than restoring the dpkg database alone:

```bash
sudo tar \
  --acls \
  --xattrs \
  --xattrs-include='*' \
  --xattrs-exclude='security.selinux' \
  --numeric-owner \
  --sparse \
  --exclude='./etc/s6-overlay' \
  --exclude='./usr/local' \
  --exclude="./${PWD#/}" \
  --exclude="./${HOME#/}" \
  -xpf rootfs.tar \
  -C / ./bin ./sbin ./lib ./usr ./etc ./var
```

The archive must come from the same architecture and Debian filesystem layout.
This restores the source's Debian package versions; it does not retain the replacement image's newer Debian packages.
It is not a clean package rollback because destination-only files remain.
Proceed only if that command succeeds.
Then restore every archived home file, replacing matching destination files:

```bash
sudo tar \
  --acls \
  --xattrs \
  --xattrs-include='*' \
  --xattrs-exclude='security.selinux' \
  --numeric-owner \
  --sparse \
  --exclude="./${PWD#/}" \
  -xpf rootfs.tar \
  -C / "./${HOME#/}"
```

Run extraction through `sudo` so container root can restore numeric ownership.
They omit `--overwrite`; normal tar extraction still replaces matching files during the package and home passes.
The SELinux exclusion leaves labels to the destination's security policy. Verify other required attributes after restoration.
Missing files restored outside home can still be incompatible with the newer image.
This procedure restores APT and dpkg state with the package trees instead of merging package records.
After restoration, run `dpkg --audit` and `sudo apt-get check` before installing or updating packages.
Restart the replacement after all three restore commands succeed, then check home files, ownership, sudo, and required tools.
The minimal example has no desktop devices or nested-container permissions; those require the corresponding launch options.
Keep the original container and archive until the replacement passes all required checks.

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
| `podman` | Podman, podman-compose, crun, conmon, fuse-overlayfs, and sudo wrappers for nested containers |

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
podman exec -it debian-workspace as-admin tmux -2u attach-session
```

These commands target the full workspace. Substitute `debian-dev` for the minimal example.
The tmux attach command requires an existing session.
Keep the original workspace process running while using these extra terminals.
Exiting the original shell or last tmux session stops the container.

For project structure and contributor checks, see [Architecture](docs/ARCHITECTURE.md).
