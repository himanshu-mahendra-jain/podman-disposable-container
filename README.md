# Podman Disposable Container

A small, rootless, hardened disposable Alpine Linux container managed by Podman and systemd Quadlet.

The setup builds a local Alpine image containing only an OpenSSH client and CA certificates, runs it as an unprivileged user, provides a temporary dummy SSH key through a Podman secret, and applies multiple container and systemd restrictions to reduce the container's access to the host.

The container uses a read-only root filesystem, temporary filesystems for `/tmp` and `/run`, no Linux capabilities, `NoNewPrivileges`, restricted device access, restricted address families, a process limit, memory and CPU limits, and rootless IPv4 TCP-only networking.

## Requirements

* Debian GNU/Linux 13 (Trixie) or newer
* `sudo`
* systemd user services
* Podman
* `uidmap`
* User-level systemd/Quadlet support
* An active user systemd bus

The installation script installs the required Podman packages automatically:

* `podman`
* `uidmap`

Root privileges are used only through `sudo` for package installation. The container itself is intended to run rootlessly as the current user.

## What It Installs

The setup installs:

* Podman
* `uidmap`

It also creates the following user-level configuration:

```text
~/containers/disposable/
├── Containerfile

~/.config/containers/
├── policy.json
└── systemd/
    └── disposable.container
```

The script also creates a local SSH key at:

```text
~/.ssh/test
```

This is a dedicated dummy key for the disposable container and is not intended to be an existing personal SSH key.

## Installation

Make the setup script executable and run it:

```bash
chmod +x podman-disposable-container.sh
./podman-disposable-container.sh
```

The script:

1. Installs Podman and `uidmap`.
2. Creates the required user directories.
3. Copies the container configuration files.
4. Generates a dummy Ed25519 SSH key if one does not already exist.
5. Stores the key as a Podman secret.
6. Builds the local container image.
7. Reloads the user systemd manager.
8. Starts or restarts the Quadlet service.
9. Waits for the container to become ready.
10. Opens a shell inside the container.

The script waits up to approximately 15 seconds for the container to start.

## Container Image

The image is based on:

```text
docker.io/library/alpine:latest
```

The Containerfile installs:

```text
openssh-client
ca-certificates
```

It then creates an unprivileged user:

```text
disposable-container
UID: 1000
GID: 1000
```

The container uses this user rather than running processes as root.

The user's home directory is:

```text
/home/disposable-container
```

The default working directory is the same location.

The container starts with:

```text
/bin/sh
```

## SSH Configuration

The image creates:

```text
/home/disposable-container/.ssh/config
```

with the following behavior:

```text
IdentityFile /home/disposable-container/.ssh/test
IdentitiesOnly yes
StrictHostKeyChecking accept-new
UserKnownHostsFile /tmp/known_hosts
```

This means the SSH client:

* Uses the dedicated container SSH key.
* Does not automatically try other identities.
* Accepts previously unknown host keys.
* Stores learned host keys in `/tmp/known_hosts`.

Because `/tmp` is a temporary filesystem, the known-hosts file is not persistent between container recreations.

## Dummy SSH Key

The setup script creates:

```text
~/.ssh/test
```

when it does not already exist.

The key is generated as an Ed25519 key with:

```text
ssh-keygen -t ed25519 -N ""
```

The key has no passphrase because it is intended only as a disposable test identity.

The host-side private key is restricted to:

```text
0600
```

The key is then imported into Podman as:

```text
disposable-ssh-key
```

The secret is mounted inside the container at:

```text
/home/disposable-container/.ssh/test
```

with:

```text
UID: 1000
GID: 1000
Mode: 0400
```

The private key is therefore provided to the container through a Podman secret rather than being copied into the container image.

## Container Name

The running container is named:

```text
disposable
```

The locally built image is tagged:

```text
disposable:alpine
```

The Quadlet configuration refers to:

```text
localhost/disposable:alpine
```

The container is configured with:

```text
Pull=never
```

Therefore, the running service uses only the explicitly built local image and does not pull an image when the service starts.

## Rootless Execution

The container is run through the user's rootless Podman environment.

The container image itself uses:

```text
USER disposable-container
```

so the default process inside the container is not root.

The Quadlet configuration additionally applies:

```text
DropCapability=all
NoNewPrivileges=true
```

All Linux capabilities are dropped and processes are prevented from gaining additional privileges.

## Read-Only Root Filesystem

The container root filesystem is configured as read-only:

```text
ReadOnly=true
ReadOnlyTmpfs=true
```

Writable temporary filesystems are provided separately for:

```text
/tmp
/run
```

with:

```text
noexec,nosuid,nodev
```

The resulting configuration is:

```text
/tmp  rw,noexec,nosuid,nodev
/run  rw,noexec,nosuid,nodev
```

There is no persistent writable container filesystem configured by the Quadlet unit.

## Process Limit

The container is restricted to:

```text
PidsLimit=32
```

The systemd service also has resource limits:

```text
MemoryMax=128M
CPUQuota=100%
```

This limits the container service to 128 MiB of memory and one CPU's worth of CPU time.

## Device Access

The systemd service uses:

```text
DevicePolicy=closed
```

Device access is therefore denied by default.

The container does not explicitly request access to host devices.

## Restricted Kernel Interfaces

The Quadlet configuration masks several sensitive kernel and `/proc`/`/sys` interfaces:

```text
/proc/acpi
/proc/kcore
/proc/keys
/proc/latency_stats
/proc/sched_debug
/proc/scsi
/proc/timer_list
/proc/timer_stats
/sys/firmware
/sys/fs/selinux
/sys/kernel/debug
/sys/kernel/tracing
/sys/kernel/security
```

These paths are therefore unavailable from inside the container.

## Network Configuration

The container uses rootless Podman's `pasta` networking:

```text
Network=pasta:--ipv4-only,--no-udp,--no-icmp,--no-dhcp,--no-map-gw
```

The configuration requests:

* IPv4 only
* No UDP
* No ICMP
* No DHCP
* No automatic gateway mapping

The service additionally restricts the available address families to:

```text
AF_UNIX
AF_INET
AF_NETLINK
```

The configuration is intended to provide outbound TCP/IPv4 networking suitable for SSH while removing several other network capabilities.

## System Call Architecture

The systemd service specifies:

```text
SystemCallArchitectures=native
```

This restricts system calls to the native architecture of the host.

The Quadlet configuration does not define a broad custom `SystemCallFilter` list.

## Image Policy

The setup installs a Podman policy at:

```text
~/.config/containers/policy.json
```

The default policy is:

```text
reject
```

The policy contains a specific exception for:

```text
docker.io/library/alpine
```

using the Docker transport and:

```text
insecureAcceptAnything
```

This allows the Alpine base image used during the build to be accepted without signature verification under this policy.

The runtime service itself uses:

```text
Pull=never
```

so the running disposable container does not pull images.

## Building the Image

The setup script copies the Containerfile to:

```text
~/containers/disposable/Containerfile
```

It then builds:

```bash
cd ~/containers/disposable
podman build -t disposable:alpine -f Containerfile .
```

The image uses the current `alpine:latest` base image at build time.

The resulting image is local to the user's Podman environment.

## Quadlet Systemd Service

The Quadlet unit is installed at:

```text
~/.config/containers/systemd/disposable.container
```

The generated user service is:

```text
disposable.service
```

After copying the configuration, the setup script runs:

```bash
systemctl --user daemon-reload
systemctl --user restart disposable.service
```

The container is configured with:

```text
Restart=no
```

The container process itself runs:

```text
sleep infinity
```

This keeps the service running while the interactive shell is attached separately with `podman exec`.

## Opening the Container

After the container becomes ready, the setup script automatically attaches a shell:

```bash
podman exec -it disposable /bin/sh
```

when running from an interactive terminal.

For a non-interactive input stream it uses:

```bash
podman exec disposable /bin/sh
```

You can also enter the running container manually:

```bash
podman exec -it disposable /bin/sh
```

## Useful Verification Commands

Check the container:

```bash
podman ps
```

Inspect the container:

```bash
podman inspect disposable
```

Check the image:

```bash
podman images
```

Check the Quadlet service:

```bash
systemctl --user status disposable.service --no-pager
```

Check service logs:

```bash
journalctl --user -u disposable.service
```

Check the Podman secret:

```bash
podman secret ls
```

Check the user-level Quadlet configuration:

```bash
ls -la ~/.config/containers/systemd/
```

Check the container user:

```bash
podman exec disposable id
```

Check the mounted SSH key:

```bash
podman exec disposable ls -l /home/disposable-container/.ssh/test
```

Check the network configuration from inside the container:

```bash
podman exec disposable ip addr
```

## Re-running the Setup Script

The setup script is designed to be run again.

On subsequent runs it:

1. Reinstalls or verifies the required packages.
2. Refreshes the configuration files.
3. Reuses the existing `~/.ssh/test` key if present.
4. Removes and recreates the `disposable-ssh-key` Podman secret.
5. Rebuilds the local image.
6. Reloads the Quadlet configuration.
7. Restarts the service.
8. Waits for the container to become ready.
9. Opens a new shell inside the container.

The existing SSH key is not regenerated when:

```text
~/.ssh/test
```

already exists.

The Podman secret is deliberately recreated on each run so that it reflects the current host-side key.

## Disposable Storage

The Quadlet configuration does not define a persistent volume or bind mount for the container.

The root filesystem is read-only.

Writable locations are temporary:

```text
/tmp
/run
```

The SSH `known_hosts` file is also stored under:

```text
/tmp/known_hosts
```

Consequently, data written to these temporary locations is not intended to persist across container recreation.

The host-side dummy SSH private key is persistent:

```text
~/.ssh/test
```

It exists independently of the container filesystem.

## Security Model

The container combines several independent restrictions:

* Rootless Podman execution
* Unprivileged container user
* All Linux capabilities dropped
* `NoNewPrivileges`
* Read-only root filesystem
* Temporary `tmpfs` filesystems
* `noexec`
* `nosuid`
* `nodev`
* Process limit
* Memory limit
* CPU limit
* Device access denied by default
* Masked sensitive kernel interfaces
* Restricted address families
* IPv4-only networking
* UDP disabled
* ICMP disabled
* DHCP disabled
* Gateway mapping disabled
* Local-image-only runtime
* SSH key supplied through a Podman secret

These restrictions are intended to make the container suitable for disposable command-line work where isolation from the host is important.

## Important Limitations

This configuration should not be treated as a complete security boundary against every possible container or kernel vulnerability.

In particular:

* Podman, the Linux kernel, systemd, and the host remain part of the security boundary.
* The container has network access.
* The container can make outbound IPv4 TCP connections.
* The Alpine base image uses the `latest` tag.
* The supplied image policy explicitly accepts the configured Alpine image without signature verification.
* The dummy SSH key has no passphrase.
* `StrictHostKeyChecking accept-new` accepts previously unknown SSH host keys.
* No persistent container storage is provided.
* The Quadlet service does not automatically restart after stopping because `Restart=no` is configured.

The container should therefore be considered a hardened disposable environment rather than a guarantee of absolute isolation.

## Project Files

The intended project layout is:

```text
.
├── README.md
├── Containerfile
├── disposable.container
├── podman-disposable-container.sh
└── policy.json
```

The setup script expects these configuration files to be located in the same project directory as the script.

## Result

After a successful setup, the main components are:

```text
Podman image:
  localhost/disposable:alpine

Container:
  disposable

Quadlet:
  ~/.config/containers/systemd/disposable.container

Systemd service:
  disposable.service

Podman secret:
  disposable-ssh-key

SSH key:
  ~/.ssh/test

Container user:
  disposable-container
  UID 1000
  GID 1000
```

The resulting environment provides a small Alpine shell with the OpenSSH client and CA certificates, running as an unprivileged rootless container with the restrictions defined by the Quadlet service.

## License

This project is independent of Podman and Alpine Linux.

Podman and Alpine Linux are separate open-source projects and remain subject to their respective licenses and project terms.

The source code for this project is licensed under the GNU General Public License v3.0 (GPLv3). See the LICENSE file for the full license terms.

If you fork or build upon this project, attribution to the original project is appreciated.
