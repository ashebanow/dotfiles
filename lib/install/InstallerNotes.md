# Instructions for Unusual Installs

Table of Contents:

* [Nix](#nix)
* [Homebrew](#homebrew),
* [Kitty](#kitty),
* [Github Copilot Extension](#github-copilot-extension),
* [Zed](#zed)

## Nix

Nix build installers come in multiple flavors: single vs multi-user, and standard nix vs Determinate Systems nix.

We install multi-user Determinate Systems nix on host systems, and single-user standard nix on containers. This choice is forced on us because multi-user requires systemd.

For multi-user Determinate Systems nix, the installer is:

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate
```

For single-user standard nix, the installer is:

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon
```

## Homebrew

Homebrew installs the same on Mac and Linux:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Kitty

Kitty installs the same on Mac and Linux:

```bash
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
```

On Linux, you will likely want to install the desktop entries for Kitty as well:

```bash
# Create symbolic links to add kitty and kitten to PATH (assuming ~/.local/bin is in
# your system-wide PATH)
ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/
# Place the kitty.desktop file somewhere it can be found by the OS
cp ~/.local/kitty.app/share/applications/kitty.desktop ~/.local/share/applications/
# If you want to open text files and images in kitty via your file manager also add the kitty-open.desktop file
cp ~/.local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
# Update the paths to the kitty and its icon in the kitty desktop file(s)
sed -i "s|Icon=kitty|Icon=$(readlink -f ~)/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" ~/.local/share/applications/kitty*.desktop
sed -i "s|Exec=kitty|Exec=$(readlink -f ~)/.local/kitty.app/bin/kitty|g" ~/.local/share/applications/kitty*.desktop
# Make xdg-terminal-exec (and hence desktop environments that support it use kitty)
echo 'kitty.desktop' > ~/.config/xdg-terminals.list
```

## Github Copilot Extension

To install the Github Copilot extension for Kitty, run the following command:

If you have not already authenticated to the GitHub CLI, run the following command in your terminal and answer the questions it asks you:

```bash
gh auth login
```

To install the Copilot in the CLI extension, run the following command.

```bash
gh extension install github/gh-copilot
```

After installing the Copilot in the CLI extension, you can update at any time by running:

```bash
gh extension upgrade gh-copilot
```

## Zed

You can install Zed using the following command on Mac or Linux, but note that it installs for the current user, not in the system. Use a package manager for system-wide installs, but note that it installs for the current user, not in the system. Use a package manager for system-wide installs.

```bash
curl -f https://zed.dev/install.sh | sh
```

### Installing via a package manager

There are several third-party Zed packages for various Linux distributions and package managers, sometimes under zed-editor. You may be able to install Zed using these package names:

* Flathub: dev.zed.Zed
* Arch: zed
* Arch (AUR): zed-git, zed-preview, zed-preview-bin
* Alpine: zed (aarch64) (x86_64)
* Nix: zed-editor (unstable)
* Fedora/Ultramarine (Terra): zed, zed-preview, zed-nightly
* Homebrew macOS: `brew install --cask zed`
* Solus: zed
* Parabola: zed
* Manjaro: zed
* ALT Linux (Sisyphus): zed
* AOSC OS: zed
* openSUSE Tumbleweed: zed
