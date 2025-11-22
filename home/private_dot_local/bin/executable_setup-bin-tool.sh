#!/usr/bin/env bash
set -euo pipefail

# Detect OS and architecture
detect_platform() {
    local os arch

    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux) os="linux" ;;
        darwin) os="darwin" ;;
        *) echo "Unsupported OS: $os" >&2; exit 1 ;;
    esac

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7*) arch="armv7" ;;
        i386|i686) arch="386" ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac

    echo "${os}_${arch}"
}

# Get latest release version from GitHub
get_latest_version() {
    curl -s "https://api.github.com/repos/marcosnils/bin/releases/latest" | \
        grep '"tag_name"' | \
        sed -E 's/.*"v?([^"]+)".*/\1/'
}

# Main installation
install_bin_if_necessary() {
    if command -v bin >/dev/null 2>&1; then
        exit 0
    fi

    local platform version binary_name download_url

    platform=$(detect_platform)
    version=$(get_latest_version)

    if [[ -z "$version" ]]; then
        echo "Failed to get latest version" >&2
        exit 1
    fi

    echo "Latest version: v${version}"
    echo "Platform: ${platform}"

    # Construct binary name
    binary_name="bin_${version}_${platform}"

    # Construct download URL
    download_url="https://github.com/marcosnils/bin/releases/download/v${version}/${binary_name}"

    echo "Downloading from: ${download_url}"

    # Create temp directory
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    # Download binary
    if ! curl -fsSL -o "${tmpdir}/bin" "${download_url}"; then
        echo "Download failed. The binary name pattern might be different." >&2
        echo "Check https://github.com/marcosnils/bin/releases/latest for available binaries." >&2
        exit 1
    fi

    # Make executable
    chmod +x "${tmpdir}/bin"

    # Use bin to install itself
    echo "Installing bin..."
    "${tmpdir}/bin" install --force github.com/marcosnils/bin
}

install_bin_if_necessary "$@"

if ! bin list |grep -q bob ; then
    echo "Installing bob from github.com/MordechaiHadad/bob"
    bin install github.com/MordechaiHadad/bob
fi

if ! bin list |grep -q devcockpit ; then
    echo "Installing devcockpit from github.com/caioricciuti/dev-cockpit"
    bin install github.com/caioricciuti/dev-cockpit
fi

bin ensure
