# User help

[Back to README](../README.md)  

- [Startup failures](#startup-failures)
- [Podman in Podman](#podman-in-podman)
- [Verification limits](#verification-limits)

## Startup failures

If crun reports `cannot find` with an empty command, inspect the local image and failed container.  
Replace `debian-dev` with the failed container's name.  

```bash
podman --version
crun --version
type podman
podman image inspect ghcr.io/parksnoopy/debian-slim-zsh:latest \
  --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
podman inspect debian-dev --format 'Path={{json .Path}} Args={{json .Args}}'
```

Expected entrypoint/Path: `/init`.  
Expected command/Args: `/usr/local/bin/as-admin /usr/bin/zsh -l`.  
Changing UID mappings does not supply a missing command.  
Check aliases, wrappers, and startup overrides if local values differ.  
Pull the published image again if the local image metadata differs.  
For a disposable test with explicit startup:  

```bash
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --user=0:0 \
  --entrypoint /init \
  ghcr.io/parksnoopy/debian-slim-zsh:latest \
  /usr/local/bin/as-admin /usr/bin/zsh -l
```

## Podman in Podman

Run the outer Podman as your host user without `sudo`.  
Run the inner engine as container root through `sudo podman`.  
The host needs crun, subordinate UID/GID ranges, and access to `/dev/fuse`.  
Admin's nested rootless engine is separate and unconfigured.  
It needs mapping helpers and compatible subordinate ranges.  

> [!CAUTION]
> Trusted code only. The example adds capabilities and relaxes AppArmor, SELinux labeling, and masked paths.  
> Default seccomp remains enabled. See [verification limits](#verification-limits).  

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

Inside the workspace:  

```bash
~/init.sh install podman
sudo podman run docker.io/library/debian:13-slim id
```

The sudo wrapper supplies runtime, storage, network, logging, cgroup, and security defaults for the inner engine.  
It cannot add missing outer-container permissions or devices.  
Plain `podman` passes through unchanged and needs its own rootless setup.  
Put the subcommand first. Use `sudo /usr/bin/podman` to bypass the wrapper.  
Inner `run` removes containers on exit. Add `--rm=false` to retain them.  

For Compose, run these commands from the folder containing its file:  

```bash
sudo podman-compose up -d
sudo podman-compose down
```

Use `network_mode: host` per service. It shares the workspace network, not the physical host network.  
The sudo Compose wrapper disables automatic pods and retains containers until removal.  
Plain `podman-compose` requires working rootless Podman.  
This setup provides no separate inner networks or resource limits.  
The storage volume persists inner data without a host engine socket.  
Reuse it with the same user mapping and storage driver.  
Stop inner containers before exiting the workspace.  
Resume with `podman start -ai debian-nested`.  

## Verification limits

The full rootless desktop launch examples and their Wayland/X11 connections are not runtime-verified.  
The rootless outer configuration for nested Podman is not runtime-verified.  
Admin's nested rootless engine is unconfigured and unverified.  
Full container migration is not runtime-verified.  
Static documentation checks do not establish these runtime guarantees.  
