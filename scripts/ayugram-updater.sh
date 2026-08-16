#!/bin/bash
set -euo pipefail

REPO="__GITHUB_REPO__"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"
QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

log() { $QUIET || echo "$@"; }

INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' ayugram-desktop 2>/dev/null || echo "0")
log "Installed: $INSTALLED_VERSION"

RESPONSE=$(curl -sf --max-time 30 "$GITHUB_API" 2>/dev/null) || {
    log "Failed to check for updates"
    exit 1
}

LATEST_TAG=$(echo "$RESPONSE" | grep -oP '"tag_name"\s*:\s*"\Kv?[^"]+')
LATEST_VERSION=$(echo "$LATEST_TAG" | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
    log "Could not parse latest version"
    exit 1
fi

log "Latest:    $LATEST_VERSION"

if dpkg --compare-versions "$LATEST_VERSION" gt "$INSTALLED_VERSION" 2>/dev/null; then
    log "Update available: $INSTALLED_VERSION -> $LATEST_VERSION"

    DEB_URL=$(echo "$RESPONSE" | grep -oP '"browser_download_url"\s*:\s*"\K[^"]*\.deb')

    if [ -z "$DEB_URL" ]; then
        log "No .deb asset found in latest release"
        exit 1
    fi

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    log "Downloading: $DEB_URL"
    curl -sfL --max-time 300 -o "$TMPDIR/ayugram.deb" "$DEB_URL" || {
        log "Download failed"
        exit 1
    }

    log "Installing update..."
    if [ "$(id -u)" -eq 0 ]; then
        dpkg -i "$TMPDIR/ayugram.deb" || apt-get install -f -y
    else
        sudo dpkg -i "$TMPDIR/ayugram.deb" || sudo apt-get install -f -y
    fi

    log "Updated to $LATEST_VERSION"
else
    log "Already up to date ($INSTALLED_VERSION)"
fi
