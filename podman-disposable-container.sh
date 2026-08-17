#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure systemd user bus environment variables are present
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

# 1. Install prerequisites non-interactively
export DEBIAN_FRONTEND=noninteractive
sudo apt update -y
sudo apt install -y podman uidmap

# 2. Setup target directory layout
mkdir -p ~/containers/disposable
chmod 700 ~/containers ~/containers/disposable

mkdir -p ~/.config/containers/systemd
chmod 700 ~/.config/containers/systemd

mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 3. Copy configuration files from the project folder
cp "$SCRIPT_DIR/Containerfile" ~/containers/disposable/Containerfile
cp "$SCRIPT_DIR/disposable.container" ~/.config/containers/systemd/disposable.container
cp "$SCRIPT_DIR/policy.json" ~/.config/containers/policy.json

# 4. Generate dummy SSH key if not present
SSH_KEY="$HOME/.ssh/test"
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "disposable-key"
fi
chmod 600 "$SSH_KEY"

# 5. Create or refresh Podman secret safely without tripping set -e
if podman secret exists disposable-ssh-key 2>/dev/null; then
    podman secret rm disposable-ssh-key
fi
podman secret create disposable-ssh-key "$SSH_KEY"

# 6. Build the container image
cd ~/containers/disposable
podman build -t disposable:alpine -f Containerfile .

# 7. Reload and restart Quadlet systemd service
systemctl --user daemon-reload
systemctl --user restart disposable.service

# 8. Wait for service readiness with a timeout (15s max)
echo "Waiting for disposable container to start..."
RETRIES=30
until [ "$(podman inspect -f '{{.State.Running}}' disposable 2>/dev/null)" = "true" ] || [ "$RETRIES" -le 0 ]; do
    sleep 0.5
    ((RETRIES--))
done

if [ "$RETRIES" -le 0 ]; then
    echo "Error: Timed out waiting for disposable container to become ready." >&2
    systemctl --user status disposable.service --no-pager || true
    exit 1
fi

# 9. Attach shell to the container (with TTY detection)
if [ -t 0 ]; then
    podman exec -it disposable /bin/sh
else
    podman exec disposable /bin/sh
fi
