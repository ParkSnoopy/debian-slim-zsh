# Debian, with zsh

A small Debian 13 workspace with zsh, tmux, and sudo.
Enter the shell, install the tools you need, and keep your project dependencies inside the container.
Based on [ubuntu-slim-zsh](https://github.com/ParkSnoopy/ubuntu-slim-zsh).

## Start a workspace

These examples use rootless Podman on Linux.
[GitHub Actions](.github/workflows/deploy-image.yaml) builds and publishes the image to GHCR after its checks pass.
Pull the latest image:

```bash
podman pull ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Open a shell:

```bash
podman run -it --name debian-dev \
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
podman run -it --name debian-project \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --volume "$PWD:/home/admin/workspace" \
  --workdir /home/admin/workspace \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Changes in `/home/admin/workspace` also change your host files.
On SELinux hosts, use `--volume "$PWD:/home/admin/workspace:Z"` for a dedicated project directory.
Do not relabel your whole home directory.

## Allow access to `/dev/fuse`

If your application needs FUSE, pass the device when you create its workspace.
The host must provide `/dev/fuse`, and your host user must have permission to access it.
This example also requires `crun` on the host:

```bash
podman run -it --name debian-fuse \
  --runtime crun --group-add keep-groups \
  --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --device /dev/fuse:/dev/fuse \
  ghcr.io/parksnoopy/debian-slim-zsh:latest
```

Install the FUSE tools your application needs inside the container.
Device access alone does not guarantee that every FUSE mount works under your host's security policy.

> **Podman inside the workspace is not ready yet.**
> The image does not include Podman.
> Passing `/dev/fuse` does not configure nested containers, and installing Podman alone is not sufficient.

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
podman exec -it debian-dev as-admin zsh -l
```

For tmux:

```bash
podman exec -it debian-dev as-admin tmux -2u
```

Keep the original workspace shell open while using these extra terminals.
Exiting that original shell stops the container, including tmux.

For project structure and contributor checks, see [Architecture](docs/ARCHITECTURE.md).
