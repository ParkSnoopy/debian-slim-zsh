# Ubuntu, with zsh

Enjoy `zsh`'s powerful completion within docker container  
By default, docker `ENTRYPOINT` and `CMD` is hard to override,  
you had to run `zsh` over `bash`, which is exhausting sometimes.  

# Use

## Pull the image
```bash
docker pull ghcr.io/parksnoopy/ubuntu-slim-zsh:latest
```
## Run the container

```bash
docker run -it -u root -w /root ghcr.io/parksnoopy/ubuntu-slim-zsh:latest
```

Entrypoint as `tmux` instead of `zsh`

```bash
docker run -it -u root -w /root --entrypoint '["/usr/bin/dumb-init", "/usr/bin/tmux", "-2u"]' ghcr.io/parksnoopy/ubuntu-slim-zsh:latest
```

## Run initialization script

> [!NOTE]  
> [`/root/init.sh`](src/init.sh) is the packaged bootstrap script.  
>   
> Normally, `zsh` is used with `omz`,  
> but it makes image unnessasarily heavy.  
>   
> So initial setup is split into install topics under [`init.d/`](init.d/)  
> and run by the curl-fetched master script.  

Default install with unminimize, apt HTTPS support, minimal packages, and omz

```bash
~/init.sh
```

Preview the default install

```bash
~/init.sh --dry-run
```

List available install topics

```bash
~/init.sh --list
```

Update the installed init script when a newer git commit is available

```bash
~/init.sh update
```

Install only selected topics

```bash
~/init.sh install omt python-uv
```

Exclude a topic from the default install

```bash
~/init.sh --exclude omz
```

Install SteamCMD and create a `/usr/local/bin/steamcmd` wrapper that runs as the `steam` user

```bash
~/init.sh install steamcmd
```

Install a Minecraft Fabric server (prompts for Minecraft version and install directory)

```bash
~/init.sh install minecraft-fabric
```

Install a Minecraft NeoForge server (prompts for Minecraft version and install directory)

```bash
~/init.sh install minecraft-neoforge
```

Install every available topic without confirmation

```bash
~/init.sh install '*' -y
```

## Installer structure

`init.sh` parses arguments, applies defaults and exclusions, and orders the
selected topics before either previewing or installing them. Dry runs return
before confirmation, downloads, or package changes. Shared membership and
append helpers handle both selection and exclusion without recursive dispatch.
Topic failures remain aggregated after the installation loop.

`src/init.sh` is the image's thin bootstrap. Topic scripts remain under
`init.d/` and use direct command sequences. Upstream shell installers are
downloaded completely before execution, with temporary files removed on exit.
Self-update validates the downloaded Bash script before replacement and still
requires confirmation before replacing `.zshenv`.

## Development checks

`bash tests/init.bash` exercises the CLI with controlled download and package
command fixtures in a temporary home; it does not install packages or contact
upstream services. Run `bash -n` and `shellharden --check` on `init.sh`,
`src/init.sh`, each `init.d/*.sh` script, and `tests/init.bash` individually.
