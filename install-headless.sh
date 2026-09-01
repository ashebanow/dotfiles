#!/usr/bin/env bash

# install-headless.sh — bootstrap a NON-NixOS headless machine (VPS, cloud VM,
# container) with chezmoi + this dotfiles repo + a first apply.
#
# This is the headless counterpart to bootstrap.sh (which targets personal
# machines: Homebrew, Bitwarden, GUI, shell switching). On a headless machine
# this script:
#   1. Installs chezmoi if missing — distro package manager where quick
#      (apk/apt/dnf/yum/pacman), else the pinned static binary from GitHub
#      releases (v2.72.0) to /usr/local/bin (root) or ~/.local/bin.
#   2. Clones and applies the dotfiles with `chezmoi init --apply --force
#      --no-tty`. The --no-tty/--force flags guarantee an unknown non-TTY host
#      renders headless=true with NO prompt, and suppress apply's changed-file
#      prompt.
#   3. Never prompts for Bitwarden/BWS: the headless .chezmoiignore (BOX-123)
#      excludes the personal-secret templates (hermes bitwardenSecrets, git
#      signingkey, gh oauth_token, nix access token), so apply needs no secret
#      session on headless.
#   4. Never switches shells (no chsh) — the dotfiles work with the existing
#      login shell (bash when present); otherwise they are installed anyway and
#      a note is printed.
#   5. Keeps the repo on disk (~/.local/share/chezmoi) and prints maintenance
#      instructions (chezmoi update / chezmoi apply --force).
#
# No Homebrew, no chsh, no GUI assumptions. Non-interactive: any step that
# would need input fails loudly instead of prompting.
#
# BOX-122. Part of the HEADLESS effort (BOX-118).

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_REPO_URL="https://github.com/ashebanow/dotfiles.git"
# Pinned static binary used when the distro package manager can't provide a
# recent-enough chezmoi (see MIN_CHEZMOI_VERSION).
CHEZMOI_VERSION="v2.72.0"
# Minimum chezmoi required by this repo (see .chezmoiversion).
MIN_CHEZMOI_VERSION="2.48.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions (mirror bootstrap.sh's style)
log_info() {
    echo -e "${BLUE}[install-headless]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[install-headless]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[install-headless]${NC} $*"
}

log_error() {
    echo -e "${RED}[install-headless]${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}${BOLD}[install-headless]${NC} $*"
}

# Show help
show_help() {
    cat << EOF
Install Dotfiles on a NON-NixOS Headless Machine

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Bootstraps a headless machine (Debian/Ubuntu/Fedora/Alpine VPS, container,
    or cloud VM — no screen/keyboard, no personal secrets) with chezmoi and
    this dotfiles repo, then applies it. Non-interactive, idempotent, and
    never prompts for Bitwarden/BWS or switches shells.

    For personal/desktop machines use bootstrap.sh instead.

OPTIONS:
    --repo URL   Git repository URL for dotfiles (default: $DEFAULT_REPO_URL)
    --dry-run    Print the actions that would be taken without executing them
    --debug      Enable debug output (set -x)
    --help       Show this help message and exit

EXAMPLES:
    $0                              # Bootstrap with defaults
    $0 --repo https://github.com/user/dotfiles.git  # Custom repo
    $0 --dry-run                    # Show what would happen

WHAT IT DOES:
    1. Detects the environment (Linux only, non-NixOS, distro family)
    2. Ensures core tools (curl/wget + git)
    3. Installs chezmoi if missing (package manager, else pinned static binary)
    4. Clones + applies the dotfiles: chezmoi init --apply --force --no-tty
    5. Verifies headless=true was rendered (no BWS needed on headless)
    6. Notes the login shell (never changes it)
    7. Prints maintenance instructions (chezmoi update / apply --force)

NOTES:
    - Requires bash to run (on Alpine: apk add bash)
    - Installs git and curl/wget automatically when missing
    - Never prompts for Bitwarden/BWS and never switches shells

For more information, see: https://github.com/ashebanow/dotfiles
EOF
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

REPO_URL="$DEFAULT_REPO_URL"
DRY_RUN=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            if [[ -n "${2:-}" && "$2" != --* ]]; then
                REPO_URL="$2"
                shift 2
            else
                log_error "--repo requires a repository URL"
                exit 1
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Try '$0 --help' for more information." >&2
            exit 1
            ;;
    esac
done

if [[ "$DEBUG_MODE" == "true" ]]; then
    log_info "Debug mode enabled"
    set -x
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Execute a command, or print it under --dry-run.
run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] $*"
        return 0
    fi
    "$@"
}

# Execute a command as root (direct if already root, else via sudo).
run_as_root() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] (as root) $*"
        return 0
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        # -n: never prompt — the script is non-interactive by contract; a
        # password-requiring sudo must fail loudly, not block on input.
        sudo -n "$@"
    else
        log_error "This step needs root, but we are not root and sudo is not installed: $*"
        return 1
    fi
}

# Print the installed chezmoi version (e.g. "2.72.0") or nothing.
chezmoi_version() {
    command -v chezmoi >/dev/null 2>&1 || return 1
    chezmoi --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

# version_at_least WANT HAVE — returns 0 if HAVE >= WANT (dotted comparison).
version_at_least() {
    local want="$1" have="$2"
    local -a w h
    IFS='.' read -r -a w <<< "$want"
    IFS='.' read -r -a h <<< "$have"
    local i
    for i in 0 1 2; do
        local wi="${w[$i]:-0}" hi="${h[$i]:-0}"
        if (( wi > hi )); then
            return 1
        fi
        if (( wi < hi )); then
            return 0
        fi
    done
    return 0
}

# Download a file with curl (preferred) or wget.
download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        log_error "Neither curl nor wget is installed — cannot download files (git clone needs one too)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Environment detection
# ---------------------------------------------------------------------------

DISTRO_ID="unknown"
DISTRO_LIKE=""

is_debian_like() {
    [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_LIKE" == *"debian"* ]]
}

is_fedora_like() {
    [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" \
        || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]] \
        || [[ "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* ]]
}

is_arch_like() {
    [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID" == "manjaro" || "$DISTRO_ID" == "endeavouros" ]] \
        || [[ "$DISTRO_LIKE" == *"arch"* ]]
}

is_alpine_like() {
    [[ "$DISTRO_ID" == "alpine" ]]
}

step_detect_environment() {
    log_step "Step 1: Detecting environment..."

    case "$(uname -s)" in
        Linux)
            ;;
        *)
            log_error "install-headless.sh targets Linux headless machines; this is $(uname -s)."
            log_error "Use bootstrap.sh + install.sh for personal/desktop machines."
            exit 1
            ;;
    esac

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    fi
    # Fallback detection for minimal images without /etc/os-release.
    if [[ "$DISTRO_ID" == "unknown" ]]; then
        if command -v apk >/dev/null 2>&1; then
            DISTRO_ID="alpine"
        elif command -v apt-get >/dev/null 2>&1; then
            DISTRO_ID="debian"
        elif command -v dnf >/dev/null 2>&1; then
            DISTRO_ID="fedora"
        elif command -v pacman >/dev/null 2>&1; then
            DISTRO_ID="arch"
        fi
    fi

    if [[ "$DISTRO_ID" == "nixos" ]]; then
        log_error "NixOS detected — this machine is managed by nix-config, not by this script."
        log_error "install-headless.sh targets NON-NixOS headless machines (Debian/Ubuntu/Fedora/Alpine VPS, containers, cloud VMs)."
        exit 1
    fi

    log_info "OS: Linux, Distro: $DISTRO_ID${DISTRO_LIKE:+/$DISTRO_LIKE}"
    log_info "User: $(id -un) (uid $(id -u)), Host: $(hostname)"
    log_info "Repo: $REPO_URL"
}

# ---------------------------------------------------------------------------
# Step 2: Ensure core tools (curl/wget + git)
# ---------------------------------------------------------------------------

step_ensure_core_tools() {
    log_step "Step 2: Ensuring core tools (curl/wget + git)..."
    ensure_download_tool
    ensure_git
}

# Install packages via the detected distro package manager (best effort).
pkg_install() {
    if is_alpine_like; then
        run_as_root apk add --no-cache "$@"
    elif is_debian_like; then
        # ca-certificates explicitly: --no-install-recommends would otherwise
        # skip it, and bare Debian/Ubuntu images then fail TLS on curl/git.
        run_as_root apt-get update -qq && run_as_root apt-get install -y --no-install-recommends "$@" ca-certificates
    elif is_fedora_like; then
        if command -v dnf >/dev/null 2>&1; then
            run_as_root dnf install -y "$@"
        else
            run_as_root yum install -y "$@"
        fi
    elif is_arch_like; then
        run_as_root pacman -Sy --needed --noconfirm "$@"
    else
        log_error "Don't know how to install packages on '$DISTRO_ID' — install '$*' manually and re-run."
        return 1
    fi
}

ensure_download_tool() {
    if command -v curl >/dev/null 2>&1; then
        log_info "curl available"
        return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        log_info "wget available"
        return 0
    fi

    log_info "Neither curl nor wget is installed — installing curl via the $DISTRO_ID package manager"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] would install curl via package manager"
        return 0
    fi
    if ! pkg_install curl; then
        log_error "curl or wget is required (to download the chezmoi binary) but could not be installed."
        log_error "Install one manually and re-run this script."
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_error "curl/wget still not available after the install attempt — install one manually and re-run."
        return 1
    fi
    log_success "curl available now"
}

# git is required for the clone (chezmoi init) and for maintenance
# (chezmoi update). chezmoi's builtin go-git can fail to clone from
# GitHub on musl/Alpine, so we make sure the real git is present —
# chezmoi automatically prefers the system git when it's on PATH.
ensure_git() {
    if command -v git >/dev/null 2>&1; then
        log_info "git available: $(git --version)"
        return 0
    fi

    log_info "git not found — installing via the $DISTRO_ID package manager"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] would install git via package manager"
        return 0
    fi
    if ! pkg_install git; then
        log_error "git is required (chezmoi clones and updates with it) but could not be installed."
        log_error "Install git manually and re-run this script."
        return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        log_error "git still not available after the install attempt — install it manually and re-run."
        return 1
    fi
    log_success "git installed: $(git --version)"
}

# Detect the libc on this machine: "musl", "glibc", or "" (unknown).
# Mirrors chezmoi's install.sh, including the glibc < 2.35 -> musl fallback
# (the published glibc builds need >= 2.35).
detect_libc() {
    if [[ -f /etc/alpine-release ]]; then
        echo "musl"
        return 0
    fi
    if command -v ldd >/dev/null 2>&1; then
        local ldd_out
        ldd_out="$(ldd --version 2>&1 | tr '[:upper:]' '[:lower:]')"
        case "$ldd_out" in
            *glibc*|*"gnu libc"*)
                local glibc_version major minor
                glibc_version="$(ldd --version 2>&1 | awk '$1 == "ldd" { print $NF }')"
                IFS='.' read -r -a parts <<< "$glibc_version"
                major="${parts[0]:-0}"
                minor="${parts[1]:-0}"
                if (( major * 10000 + minor < 23500 )); then
                    echo "musl"
                else
                    echo "glibc"
                fi
                return 0
                ;;
            *musl*)
                echo "musl"
                return 0
                ;;
        esac
    fi
    # Unknown libc — assume glibc (the amd64 -glibc asset is the official default).
    echo "glibc"
}

# ---------------------------------------------------------------------------
# Step 3: Install chezmoi
# ---------------------------------------------------------------------------

install_chezmoi_package_manager() {
    local ok=false

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] would install chezmoi via the $DISTRO_ID package manager"
        return 1 # fall through to the binary plan below
    fi

    if is_alpine_like; then
        log_info "Installing chezmoi via apk..."
        if run_as_root apk add --no-cache chezmoi; then
            ok=true
        fi
    elif is_debian_like; then
        log_info "Installing chezmoi via apt..."
        if run_as_root apt-get update -qq && run_as_root apt-get install -y --no-install-recommends chezmoi; then
            ok=true
        fi
    elif is_fedora_like; then
        log_info "Installing chezmoi via dnf/yum..."
        if command -v dnf >/dev/null 2>&1; then
            if run_as_root dnf install -y chezmoi; then
                ok=true
            fi
        elif command -v yum >/dev/null 2>&1; then
            if run_as_root yum install -y chezmoi; then
                ok=true
            fi
        fi
    elif is_arch_like; then
        log_info "Installing chezmoi via pacman..."
        if run_as_root pacman -Sy --needed --noconfirm chezmoi; then
            ok=true
        fi
    else
        log_info "No known package manager for '$DISTRO_ID' — using the pinned static binary"
        return 1
    fi

    if [[ "$ok" == "true" ]] && command -v chezmoi >/dev/null 2>&1; then
        local v
        v="$(chezmoi_version || true)"
        if [[ -n "$v" ]] && version_at_least "$MIN_CHEZMOI_VERSION" "$v"; then
            log_success "chezmoi installed via package manager: v$v"
            return 0
        fi
        log_warn "Package manager installed chezmoi v$v, but this repo needs >= $MIN_CHEZMOI_VERSION — falling back to the pinned static binary"
    elif [[ "$ok" == "true" ]]; then
        log_warn "Package manager install did not put chezmoi on PATH — falling back to the pinned static binary"
    else
        log_warn "Package manager install failed — falling back to the pinned static binary"
    fi
    return 1
}

install_chezmoi_binary() {
    local arch asset install_dir
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $(uname -m) — install chezmoi manually and re-run this script"
            return 1
            ;;
    esac

    # Asset naming mirrors chezmoi's own installer (assets/scripts/install.sh):
    # amd64 picks a -glibc/-musl build (musl for musl libc, and for glibc <
    # 2.35 since the glibc builds need >= 2.35); arm64 uses the plain
    # linux_arm64 tarball (no libc-suffixed arm64 assets are published).
    local libc
    if [[ "$arch" == "amd64" ]]; then
        libc="$(detect_libc)"
        if [[ "$libc" == "musl" ]]; then
            asset="chezmoi_${CHEZMOI_VERSION#v}_linux-musl_amd64.tar.gz"
        else
            asset="chezmoi_${CHEZMOI_VERSION#v}_linux-glibc_amd64.tar.gz"
        fi
    else
        asset="chezmoi_${CHEZMOI_VERSION#v}_linux_${arch}.tar.gz"
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
        install_dir="/usr/local/bin"
    else
        install_dir="$HOME/.local/bin"
    fi

    local url="https://github.com/twpayne/chezmoi/releases/download/${CHEZMOI_VERSION}/${asset}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[dry-run] would download $asset and install it to $install_dir/chezmoi"
        return 0
    fi

    log_info "Downloading $asset from GitHub releases..."
    mkdir -p "$install_dir"
    local tmp
    tmp="$(mktemp -d)"

    if ! download_file "$url" "$tmp/chezmoi.tar.gz"; then
        rm -rf "$tmp"
        log_error "Failed to download chezmoi from $url"
        log_error "Install chezmoi manually (https://chezmoi.io/install/) and re-run this script."
        return 1
    fi

    tar -xzf "$tmp/chezmoi.tar.gz" -C "$tmp" chezmoi
    install -m 0755 "$tmp/chezmoi" "$install_dir/chezmoi"
    rm -rf "$tmp"

    # Ensure it's on PATH for the rest of this script.
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        export PATH="$install_dir:$PATH"
    fi

    local v
    v="$(chezmoi_version || true)"
    if [[ -n "$v" ]] && version_at_least "$MIN_CHEZMOI_VERSION" "$v"; then
        log_success "chezmoi installed: v$v ($install_dir/chezmoi)"
        return 0
    fi

    log_error "Installed chezmoi binary failed the version check (v$v) — please install chezmoi >= $MIN_CHEZMOI_VERSION manually."
    return 1
}

step_install_chezmoi() {
    log_step "Step 3: Ensuring chezmoi is installed..."

    if command -v chezmoi >/dev/null 2>&1; then
        local v
        v="$(chezmoi_version || true)"
        if [[ -n "$v" ]] && version_at_least "$MIN_CHEZMOI_VERSION" "$v"; then
            log_info "chezmoi already installed: v$v ($(command -v chezmoi))"
            return 0
        fi
        log_warn "Installed chezmoi v$v is older than the required $MIN_CHEZMOI_VERSION — reinstalling a newer one"
    fi

    if install_chezmoi_package_manager; then
        return 0
    fi

    install_chezmoi_binary
}

# ---------------------------------------------------------------------------
# Step 4: Get the repo and first apply
# ---------------------------------------------------------------------------

step_get_dotfiles() {
    log_step "Step 4: Getting the dotfiles repo (first apply)..."

    local source_dir="$HOME/.local/share/chezmoi"

    if [[ -d "$source_dir/.git" ]]; then
        log_info "chezmoi source repo already initialized at $source_dir — pulling latest and re-applying"
        run chezmoi update --force --no-tty
    else
        log_info "Initializing chezmoi from $REPO_URL and applying..."
        log_info "Non-TTY host -> headless=true is rendered without prompting; no BWS session needed"
        # --no-tty: never acquire a TTY for prompts (stdinIsATTY => false =>
        # headless=true on unknown hosts). --force: suppress apply's
        # changed-file prompt. Verified with chezmoi v2.72.0.
        run chezmoi init --apply --force --no-tty "$REPO_URL"
    fi

    log_success "Dotfiles are at $source_dir (kept on disk for maintenance)"
}

# ---------------------------------------------------------------------------
# Step 5: Verify headless=true was rendered
# ---------------------------------------------------------------------------

step_verify_headless() {
    log_step "Step 5: Verifying headless=true was rendered..."

    local config_file="$HOME/.config/chezmoi/chezmoi.toml"
    if [[ -f "$config_file" ]] && grep -qE '^\s*headless\s*=\s*true\s*$' "$config_file"; then
        log_info "Rendered config has headless=true — personal-secret templates (hermes, ssh, git signingkey, gh/nix tokens) are excluded"
    else
        log_warn "Could not confirm headless=true in $config_file — expected on a non-TTY host"
        log_warn "If apply succeeded anyway, review what was written before trusting this machine"
    fi
}

# ---------------------------------------------------------------------------
# Step 6: Login shell note (never switch shells)
# ---------------------------------------------------------------------------

step_shell_note() {
    log_step "Step 6: Checking the login shell (never switching it)..."

    local shell_path=""
    shell_path="$(command -v getent >/dev/null 2>&1 && getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
    [[ -z "$shell_path" ]] && shell_path="${SHELL:-}"

    if [[ -z "$shell_path" ]]; then
        log_info "Could not determine the login shell — the dotfiles work with whatever shell you log in with"
        return 0
    fi

    local shell_name
    shell_name="$(basename "$shell_path")"

    if [[ "$shell_name" == "bash" ]]; then
        log_info "Login shell is bash — the dotfiles' bash config (~/.bashrc) will load on login"
    else
        log_warn "Login shell is $shell_path (not bash)."
        log_warn "The dotfiles are installed anyway (they harm nothing); bash-only aliases/helpers just won't be active."
        log_warn "We deliberately never change the login shell on headless machines. To use bash, run 'bash' (if installed)."
    fi
}

# ---------------------------------------------------------------------------
# Step 7: Maintenance instructions
# ---------------------------------------------------------------------------

step_print_maintenance() {
    log_step "Step 7: Maintenance"

    echo "  The repo stays at ~/.local/share/chezmoi (managed by chezmoi)."
    echo ""
    echo "  Periodic update (pull latest dotfiles and re-apply):"
    echo "      chezmoi update"
    echo ""
    echo "  Re-apply after manual edits / to converge:"
    echo "      chezmoi apply --force"
    echo ""
    echo "  If the config template (.chezmoi.toml.tmpl) changed upstream, regenerate it:"
    echo "      chezmoi update --init"
    echo ""
    echo "  Headless hosts carry no personal secrets. Anything excluded on headless lives"
    echo "  in the '{{ if .headless }}' block of ~/.local/share/chezmoi/home/.chezmoiignore.tmpl"
    echo "  (edit and 'chezmoi apply' to re-admit a file)."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log_step "install-headless: bootstrapping a NON-NixOS headless machine with chezmoi dotfiles"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN mode: printing actions without executing them"
    fi
    echo ""

    step_detect_environment
    echo ""
    step_ensure_core_tools
    echo ""
    step_install_chezmoi
    echo ""
    step_get_dotfiles
    echo ""
    step_verify_headless
    echo ""
    step_shell_note
    echo ""
    step_print_maintenance
    echo ""
    log_success "Done. Start a new shell (or log in again) to pick up the dotfiles."
}

main
