#!/bin/bash
set -e

# Ashu Desktop Linux Installer
# Automatically detects system architecture and installs Ashu Desktop

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This installer requires root privileges." >&2
  echo "Please run: curl -fsSL <URL> | sudo bash" >&2
  exit 1
fi

REPO_OWNER="AshutoshKumarGiri07"
REPO_NAME="AyuGramDesktop"
PAGES_URL="${PAGES_URL:-https://${REPO_OWNER}.github.io/${REPO_NAME}}"
APT_SOURCE="/etc/apt/sources.list.d/ashu-desktop.list"

# Detect OS architecture
RAW_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$RAW_ARCH" in
  x86_64|amd64)
    ARCH="amd64"
    ;;
  *)
    echo "Error: Architecture '${RAW_ARCH}' is not supported." >&2
    echo "Ashu Desktop is currently built for x86_64 / amd64." >&2
    exit 1
    ;;
esac

# Verify apt package manager
if ! command -v apt-get >/dev/null 2>&1; then
  echo "Error: 'apt-get' package manager not found." >&2
  echo "This installer supports Debian, Ubuntu, and Debian-based distributions." >&2
  exit 1
fi

echo "==> Detected architecture: ${RAW_ARCH} (package arch: ${ARCH})"
echo "==> Setting up Ashu Desktop APT repository..."

echo "deb [trusted=yes] ${PAGES_URL}/apt ./" > "$APT_SOURCE"

echo "==> Updating package repository cache..."
apt-get update -o Dir::Etc::sourcelist="$APT_SOURCE" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null || apt-get update

echo "==> Installing ashu-desktop..."
if ! apt-get install -y ashu-desktop; then
  echo "==> APT install had an issue, trying direct package download..."
  LATEST_DEB_URL=$(curl -sSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" \
    | grep -o "https://[^\"]*_${ARCH}\.deb" \
    | head -n 1)

  if [ -n "$LATEST_DEB_URL" ]; then
    TMP_DEB="$(mktemp /tmp/ashu-desktop-XXXXXX.deb)"
    echo "==> Downloading ${LATEST_DEB_URL}..."
    curl -fsSL "$LATEST_DEB_URL" -o "$TMP_DEB"
    apt-get install -y "$TMP_DEB" || dpkg -i "$TMP_DEB"
    rm -f "$TMP_DEB"
  else
    echo "Error: Failed to install ashu-desktop." >&2
    exit 1
  fi
fi

which gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor || true
which update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true

echo ""
echo "==> Ashu Desktop has been installed successfully!"
echo "==> Run 'ashu-desktop' to start the application."
echo "==> Updates will be installed automatically via: sudo apt update && sudo apt upgrade"
