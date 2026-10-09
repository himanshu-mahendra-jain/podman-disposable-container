# Podman Disposable Container

A small, rootless, hardened disposable Alpine Linux container managed by Podman and systemd Quadlet, for SSH into local devices (e.g. a Raspberry Pi, router or NAS) by IP address.

The setup builds a local Alpine image containing only an OpenSSH client and CA certificates, runs it as an unprivileged user, and supplies a dummy SSH key through a Podman secret. The container has a read-only root filesystem, no Linux capabilities, restricted devices and kernel interfaces, resource limits, and rootless IPv4 TCP-only networking.

## Requirements

* Latest Debian or a Debian-based distribution (e.g. Ubuntu) with the latest Podman. On other distributions, install Podman, `uidmap` and `ssh-keygen` manually; the script skips package installation when `apt-get` is unavailable.
* A regular (non-root) user; `sudo` is used only to install packages
* systemd user services with an active user bus
* Podman, `uidmap` and `openssh-client` (installed automatically on Debian-based systems)

## Project Files

```text
.
├── README.md
├── Containerfile                    # Alpine image definition
├── disposable.container             # Quadlet unit
├── podman-disposable-container.sh   # Setup script
└── policy.json                      # Podman image policy
```

The setup script expects these files in the same directory as the script.

## Installation

```bash
chmod +x podman-disposable-container.sh
./podman-disposable-container.sh
```

The script:

1. Installs Podman, `uidmap` and `openssh-client` via `apt-get` (if available) and checks that required commands exist.
2. Copies `Containerfile` and `policy.json` to `~/containers/disposable/`, and `disposable.container` to `~/.config/containers/systemd/`.
3. Generates a passphrase-less Ed25519 dummy key at `~/.ssh/disposable_ed25519` (mode `0600`) if it does not exist.
4. (Re)creates the Podman secret `disposable-ssh-key` from that key.
5. Builds the image `disposable:alpine`, applying `policy.json` to this build only.
6. Runs `systemctl --user daemon-reload` and restarts `disposable.service`.
7. Waits up to ~15 seconds for the container to become ready.
8. Opens a shell with `podman exec -it disposable /bin/sh` (`-i` only for non-interactive input).

The script refuses to run as root. It is safe to re-run: it refreshes configuration, reuses the existing `~/.ssh/disposable_ed25519`, recreates the secret, rebuilds the image, and restarts the service.

To enter the running container manually:

```bash
podman exec -it disposable /bin/sh
```

## Container Image

* Base: `docker.io/library/alpine:latest`
* Packages: `openssh-client`, `ca-certificates`
* User: `disposable-container` (UID/GID 1000), home and working directory `/home/disposable-container`
* Tag: `localhost/disposable:alpine`, used with `Pull=never` so the service never pulls images
* The service process runs `sleep infinity`; shells are attached separately via `podman exec`

### SSH Configuration

`/home/disposable-container/.ssh/config`:

```text
Host *
    IdentityFile /home/disposable-container/.ssh/disposable_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /tmp/known_hosts
```

The key is mounted from the `disposable-ssh-key` secret at `/home/disposable-container/.ssh/disposable_ed25519` (UID/GID 1000, mode `0400`), so it is never baked into the image. Known hosts live in `/tmp` and are lost when the container is recreated.

## Connecting to Devices

UDP is disabled, so the container has no DNS. Connect by IP address:

```bash
ssh pi@192.168.1.50
```

To use names instead, add one `AddHost=` line per device to `disposable.container` under `[Container]`, then re-run the setup script:

```ini
AddHost=pi:192.168.1.50
AddHost=nas:192.168.1.20
```

`ssh pi@pi` then works without DNS. mDNS names such as `raspberrypi.local` are not available. Give devices a static IP or DHCP reservation so entries stay valid.

Copy `~/.ssh/disposable_ed25519.pub` to each device's `~/.ssh/authorized_keys` to allow key login.

## Hardening

| Area | Setting |
| --- | --- |
| Privileges | Rootless Podman, non-root user, `DropCapability=all`, `NoNewPrivileges=true` |
| Filesystem | `ReadOnly=true`, `ReadOnlyTmpfs=true`; `/tmp` and `/run` are tmpfs with `noexec,nosuid,nodev`; no volumes or bind mounts |
| Resources | `PidsLimit=32`, `MemoryMax=128M`, `CPUQuota=100%` |
| Devices | `DevicePolicy=closed` |
| Kernel interfaces | Masked: `/proc/{acpi,kcore,keys,latency_stats,sched_debug,scsi,timer_list,timer_stats}`, `/sys/firmware`, `/sys/fs/selinux`, `/sys/kernel/{debug,tracing,security}` |
| Network | `Network=pasta:--ipv4-only,--no-udp,--no-icmp,--no-dhcp,--no-map-gw` (IPv4 TCP only; no DNS; host not reachable) |
| Address families | `AF_UNIX`, `AF_INET`, `AF_NETLINK` |
| System calls | `SystemCallArchitectures=native` (no custom `SystemCallFilter`) |
| Restart | `Restart=no` |

### Image Policy

`policy.json` rejects all images by default, with one `insecureAcceptAnything` exception for `docker.io/library/alpine` (Docker transport). It is passed to `podman build --signature-policy` only, so the user's global Podman policy is left untouched.

## Verification

```bash
podman ps                                         # running containers
podman inspect disposable                         # container details
podman images                                     # local images
podman secret ls                                  # secrets
systemctl --user status disposable.service --no-pager
journalctl --user -u disposable.service           # service logs
podman exec disposable id                         # container user
podman exec disposable ls -l /home/disposable-container/.ssh/disposable_ed25519
podman exec disposable ip addr                    # network setup
```

## Limitations

This is a hardened disposable environment, not a guarantee of absolute isolation.

* Podman, the kernel, systemd, and the host remain part of the security boundary.
* The container can make outbound IPv4 TCP connections to any address, including the internet; it is not restricted to the local network. Limiting it requires host firewall rules.
* No DNS or mDNS: hosts must be reached by IP or `AddHost=` entries.
* `--no-map-gw` blocks connections to the host running the container.
* Reaching local devices depends on the host's network (e.g. some VM or ChromeOS Linux environments isolate the LAN).
* The base image uses the `latest` tag and is accepted without signature verification.
* The dummy SSH key has no passphrase, and `accept-new` trusts unknown host keys on first connect.
* All container data is temporary; only the host-side `~/.ssh/disposable_ed25519` persists.
* The service does not restart automatically after stopping.

## License

This project is independent of Podman and Alpine Linux, which remain subject to their own licenses.

This project is licensed under the [MIT License](LICENSE).
