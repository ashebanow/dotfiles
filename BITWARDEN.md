# Bitwarden Session Management

This document explains how the bitwarden session management system works during machine bootstrap and normal operation.

## Bootstrap Flow

When setting up a new machine (assuming curl, wget, git, nano/vim, and sshd are preinstalled with proper SSH/git configs):

1. **Initial Setup**: Clone the repo and run the top-level `install.sh` file
2. **Installation Process**: `install.sh` sources `bin/install_main.sh`, which in turn sources all `lib/install/*` files and runs everything in order
3. **Configuration Deployment**: After install scripts finish, `install.sh` runs `chezmoi apply`, copying service configs into `$HOME`
4. **Service Activation**: The bitwarden session service is launched and will start running periodically (every 30 minutes on systemd, every 30 minutes on launchd)
5. **First Password Prompt**: When the service first runs (2 minutes after boot on Linux, immediately on macOS), it will display a GUI password prompt for your Bitwarden master password
6. **Session Persistence**: Once you enter the password, it's stored in the system keyring (gnome-keyring on Linux, keychain on macOS) and a session key is cached in `~/.cache/bw-session`

## How Sessions Work

**Important**: The service runs in its own process context and **cannot** automatically export `BW_SESSION` to other processes. Environment variables don't propagate upward from child processes.

### What the Service Does
- Runs periodically to ensure session validity
- Stores your master password securely in the system keyring
- Maintains a valid session key in `~/.cache/bw-session`
- Shows GUI prompts when authentication is needed (non-blocking)

### What You Need to Do
When you need bitwarden access in a shell or application, you must explicitly load the session:

**Bash/Zsh:**
```bash
export BW_SESSION=$(bw-open)
```

**Fish:**
```fish
set -x BW_SESSION (bw-open)
```

**The benefit**: After initial setup, `bw-open` won't prompt for your password - it uses the stored keyring password and cached session.

## Session Management Commands

- `bw-session-manager ensure` - Ensure valid session exists (used by service)
- `bw-session-manager status` - Check if current session is valid
- `bw-session-manager clear` - Clear current session (forces re-authentication)
- `bw-open [email]` - Get session key for shell export (backward compatible)
- `bw_open` (fish function) - Fish-specific session management

## Technical Details

### Service Files
- **Linux**: `~/.config/systemd/user/bitwarden-session.{service,timer}`
- **macOS**: `~/Library/LaunchAgents/com.user.bitwarden-session.plist`

### Storage Locations
- **Session cache**: `~/.cache/bw-session`
- **Password storage**: System keyring (gnome-keyring/keychain)
- **Service logs**: systemd journal (Linux) or `~/Library/Logs/bitwarden-session.log` (macOS)

### Dependencies
- **Linux**: `libsecret-tools`, `zenity` (for GUI prompts)
- **macOS**: Built-in keychain and osascript
- **All platforms**: `bitwarden-cli`

## Troubleshooting

### Service Not Running
```bash
# Linux
systemctl --user status bitwarden-session.timer
systemctl --user start bitwarden-session.timer

# macOS  
launchctl list | grep bitwarden
launchctl load ~/Library/LaunchAgents/com.user.bitwarden-session.plist
```

### Clear Stored Password
```bash
# Linux
secret-tool clear service bitwarden-dotfiles account master-password

# macOS
security delete-generic-password -a master-password -s bitwarden-dotfiles
```

### Manual Session Management
```bash
# Clear cached session
bw-session-manager clear

# Check session status  
bw-session-manager status

# Force new session
bw-session-manager ensure
```