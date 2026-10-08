#!/bin/bash
set -e

# Ashu Desktop Linux Installer
# Automatically detects system architecture and installs Ashu Desktop
# Supports:
#   - x86_64 / amd64 (native)
#   - aarch64 / arm64 (configured with high-performance runtime)

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This installer requires root privileges." >&2
  echo "Please run: curl -fsSL <URL> | sudo bash" >&2
  exit 1
fi

REPO_OWNER="AshutoshKumarGiri07"
REPO_NAME="AyuGramDesktop"
PAGES_URL="${PAGES_URL:-https://${REPO_OWNER}.github.io/${REPO_NAME}}"
APT_SOURCE="/etc/apt/sources.list.d/ashu-desktop.list"

# Verify apt package manager
if ! command -v apt-get >/dev/null 2>&1; then
  echo "Error: 'apt-get' package manager not found." >&2
  echo "This installer supports Debian, Ubuntu, and Debian-based distributions." >&2
  exit 1
fi

# Detect OS architecture
RAW_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
IS_ARM=0
case "$RAW_ARCH" in
  x86_64|amd64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    IS_ARM=1
    ;;
  *)
    echo "Error: Architecture '${RAW_ARCH}' is not supported." >&2
    echo "Ashu Desktop supports x86_64 / amd64 and aarch64 / arm64." >&2
    exit 1
    ;;
esac

echo "==> Detected system architecture: ${RAW_ARCH} (package arch: ${ARCH})"

# Setup multiarch and emulation runtime on ARM64
if [ "$IS_ARM" -eq 1 ]; then
  echo "==> Configuring ARM64 environment for Ashu Desktop..."

  # Fix /lib64 symlink if necessary (ensures usrmerge compatibility)
  if [ -d /lib64 ] && [ ! -L /lib64 ]; then
    mkdir -p /usr/lib64
    cp -rn /lib64/* /usr/lib64/ 2>/dev/null || true
    rm -rf /lib64
    ln -sf usr/lib64 /lib64
  fi

  # Enable amd64 foreign architecture
  dpkg --add-architecture amd64 2>/dev/null || true

  # Configure multiarch sources for Ubuntu if needed
  if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    if ! grep -q "Architectures:" /etc/apt/sources.list.d/ubuntu.sources; then
      sed -i '/^Types: deb/a Architectures: arm64' /etc/apt/sources.list.d/ubuntu.sources
    fi
    if [ ! -f /etc/apt/sources.list.d/amd64.sources ]; then
      cat > /etc/apt/sources.list.d/amd64.sources << 'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-security
Components: main universe
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    fi
  fi

  echo "==> Updating package repository cache..."
  apt-get update -qq || true

  echo "==> Installing emulator runtime and system libraries..."
  apt-get install -y --no-install-recommends \
    qemu-user \
    libc6:amd64 \
    libglib2.0-0t64:amd64 2>/dev/null || \
  apt-get install -y --no-install-recommends \
    qemu-user-static \
    libc6:amd64 \
    libglib2.0-0:amd64 2>/dev/null || true

  apt-get install -y --no-install-recommends \
    libgtk-3-0t64:amd64 \
    libx11-xcb1:amd64 \
    libgl1:amd64 \
    libpulse0:amd64 \
    libasound2t64:amd64 2>/dev/null || \
  apt-get install -y --no-install-recommends \
    libgtk-3-0:amd64 \
    libx11-xcb1:amd64 \
    libgl1:amd64 \
    libpulse0:amd64 \
    libasound2:amd64 2>/dev/null || true
fi

echo "==> Setting up Ashu Desktop APT repository..."
echo "deb [trusted=yes] ${PAGES_URL}/apt ./" > "$APT_SOURCE"

echo "==> Refreshing Ashu Desktop repository..."
apt-get update -o Dir::Etc::sourcelist="$APT_SOURCE" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null || apt-get update

echo "==> Installing ashu-desktop..."
INSTALLED=0
if apt-get install -y ashu-desktop; then
  INSTALLED=1
else
  echo "==> APT install had an issue, fetching package from GitHub Releases..."
  LATEST_DEB_URL=$(curl -sSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" \
    | grep -o "https://[^\"]*_${ARCH}\.deb" \
    | head -n 1)

  if [ -z "$LATEST_DEB_URL" ]; then
    LATEST_DEB_URL=$(curl -sSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" \
      | grep -o "https://[^\"]*_amd64\.deb" \
      | head -n 1)
  fi

  if [ -n "$LATEST_DEB_URL" ]; then
    TMP_DEB="$(mktemp /tmp/ashu-desktop-XXXXXX.deb)"
    echo "==> Downloading ${LATEST_DEB_URL}..."
    curl -fsSL "$LATEST_DEB_URL" -o "$TMP_DEB"
    if dpkg -i "$TMP_DEB" 2>/dev/null || dpkg -i --force-architecture "$TMP_DEB" 2>/dev/null; then
      INSTALLED=1
    else
      apt-get install -f -y || true
      dpkg -i --force-architecture "$TMP_DEB" && INSTALLED=1 || true
    fi
    rm -f "$TMP_DEB"
  fi
fi

if [ "$INSTALLED" -ne 1 ]; then
  echo "Error: Failed to install ashu-desktop." >&2
  exit 1
fi

# Ensure launcher wrapper exists if running on ARM
if [ "$IS_ARM" -eq 1 ]; then
  BIN_FILE="$(which ashu-desktop 2>/dev/null || echo "/usr/bin/ashu-desktop")"
  if [ -f "$BIN_FILE" ] && file -b "$BIN_FILE" 2>/dev/null | grep -qi "x86-64"; then
    mkdir -p /usr/lib/ashu-desktop
    mv -f "$BIN_FILE" /usr/lib/ashu-desktop/ashu-desktop
    cat > "$BIN_FILE" << 'RUNNER'
#!/bin/bash
EXEC_BIN="/usr/lib/ashu-desktop/ashu-desktop"
if command -v qemu-x86_64 >/dev/null 2>&1; then
  exec qemu-x86_64 "$EXEC_BIN" "$@"
elif command -v qemu-x86_64-static >/dev/null 2>&1; then
  exec qemu-x86_64-static "$EXEC_BIN" "$@"
elif command -v box64 >/dev/null 2>&1; then
  exec box64 "$EXEC_BIN" "$@"
else
  exec "$EXEC_BIN" "$@"
fi
RUNNER
    chmod +x "$BIN_FILE"
  fi
fi

which gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor || true
which update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true

echo ""
echo "========================================================"
echo "  Ashu Desktop has been installed successfully! (${ARCH})"
echo "========================================================"
echo "Run 'ashu-desktop' from the terminal or your application menu."
echo "Updates will be installed automatically via: sudo apt update && sudo apt upgrade"
