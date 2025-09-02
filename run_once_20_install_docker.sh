#!/usr/bin/env bash
# No -u to avoid aborting on unset vars while we debug
set -eo pipefail

# ----- Config -----
DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
DMG_TMP="$(mktemp -t docker-desktop).dmg"
MOUNT_POINT="$(mktemp -d -t docker-mount-XXXX)"
MAX_WAIT_SECONDS=120

cleanup() {
  if mount | grep -q " $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -f "$DMG_TMP" 2>/dev/null || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# ----- Apple Silicon only -----
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Skipping Docker Desktop install (this Mac is not Apple Silicon)."
  exit 0
fi

# ----- Already installed? -----
if [[ -d "/Applications/Docker.app" ]]; then
  echo "Docker Desktop already installed. Launching…"
  open -g -a "Docker" || true
  exit 0
fi

# ----- Clear leftovers -----
if mount | grep -q "/Volumes/Docker"; then
  hdiutil detach "/Volumes/Docker" -quiet || true
fi
sudo rm -rf "/Applications/Docker.app" 2>/dev/null || true

echo "Downloading Docker Desktop DMG…"
curl -fL "$DMG_URL" -o "$DMG_TMP"

# Validate temp paths
[[ -s "$DMG_TMP" ]] || { echo "Download failed (empty file)"; exit 1; }
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || { echo "Failed to create mount point"; exit 1; }

echo "Mounting DMG at $MOUNT_POINT…"
hdiutil attach "$DMG_TMP" -nobrowse -mountpoint "$MOUNT_POINT" -quiet

[[ -d "$MOUNT_POINT/Docker.app" ]] || { echo "Docker.app not found in DMG"; exit 1; }

echo "Copying Docker.app to /Applications (sudo may prompt)…"
sudo -v
sudo cp -R "$MOUNT_POINT/Docker.app" "/Applications/"

# Optional: reduce first-run prompts
if command -v xattr >/dev/null 2>&1; then
  sudo xattr -dr com.apple.quarantine "/Applications/Docker.app" || true
fi

echo "Unmounting DMG…"
hdiutil detach "$MOUNT_POINT" -quiet || true

echo "Launching Docker Desktop…"
open -g -a "Docker" || true

echo "Waiting for Docker engine to start (up to ${MAX_WAIT_SECONDS}s)…"
SECONDS_WAITED=0
while (( SECONDS_WAITED < MAX_WAIT_SECONDS )); do
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Docker is ready."
    exit 0
  fi
  sleep 2
  SECONDS_WAITED=$((SECONDS_WAITED + 2))
done

echo "Docker is still starting in the background; it should finish shortly."
