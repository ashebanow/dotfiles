# dotfiles README

These docs are mostly for bluefin and bazzite based installs.
The scripts also work on Mac, Windows WSL2/Ubuntu, and Arch-based
systems.

Currntly in the process of rearchitecting:

* Switch to using plain Nix or even pixi. Pixi works better for
some of these scenarios, since it doesn't require Home Manager to
publish applications.
* Rely on native package manager where possible for basic productivity
tools. That means we need to filter the Brewfile(s) to omit things that
are installed by the native package manager.

Also note that the instructions aren't fully up to date. As I add
more automation steps I'll make it all current and consistent.

## Bluefin-DX or Bazzite/Bazzite-DX

1. Install your preferred image and boot into it. Be sure to use the -nvidia variant if appropriate. I recommend using encrypted BTRFS.

2. If you didn't change your hostname from the default during OS setup, you can change your hostname with `sudo hostnamectl hostname <change_me_PLEASE>`.

3. Go through the post-install setup wizard, if it runs automatically.

4. Click the `Show Apps` button in the doc, run `System Update`.

    Alternatively, run `ujust update`.

    IRun `ujust bazzite-cli` or `ujust bluefin-cli` as appropriate.

    Reboot.

6. Login to bitwarden-cli (`bw`) and github-cli ('gh')

   ```bash
    bw login        # enter account email and master password
   ```

   After the login succeeds, copy the "export BW_SESSION=" line and then
   paste it into the terminal.

7. To turn off password entry when using sudo, run the `sudo visudo` command, then search for the line that looks like:

   ```bash
   #%wheel         ALL = (ALL) NOPASSWD: ALL
   ```

   Uncoment that line, then comment the one above it that says `ALL` instead of `NOPASSWORD: ALL`. Save and exit the editor.

8. Copy ssh folder to your home directory. Set the permissions properly:
    * the .ssh directory and the hosts directory should be 700
    * all .pub files should be mode 644
    * the `allowed_signers`, `authorized_keys`, `config`, and `known_hosts`
      files should be 600
    * all other files should be 400

9. Install dotfiles:

    ```bash
    git clone git@github.com:ashebanow/dotfiles.git ~/.local/share/chezmoi
    cd ~/.local/share/chezmoi
    ./install.sh
    ```

    You should also create our Development tree:

    ```bash
    mkdir -p Development/{ricing,homelab,education}
    mkdir -p Development/homelab/homelab-cattivi
    cd Development/homelab/homelab-cattivi
    git clone git@github.com:ashebanow/homelab.git main
    cd main
    git worktree ../lxc # as needed for active worktrees
    ```

10. Run `ujust setup-luks-tpm-unlock` if you used data encryption above.

11. Run `gh auth login` to setup github. You'll need your ssh key from above (which may or may not be github specific) and an auth token. I keep mine in bitwarden.

12. Setup Tailscale

    ```bash
    sudo tailscale up --ssh --accept-routes
    ```

13. Create a distrobox instance. I use ubuntu to get coverage on both fedora and ubuntu stuff:

    ```bash
    ujust distrobox-assemble
    ```

    Once created, do a `distrobox enter ubuntu`. In the distrobox, do the following setup:

    ```bash
    sudo apt update && sudo apt upgrade
    # setup your environment for ubuntu development here. You won't have access to
    # homebrew from Bluefin, you'll need to start from more or less scratch.
    exit     # to leave distrobox
    ```

14. Initialize bat themes:

    ```bash
    bat cache --build
    ```

15. Reboot one last time, and you should have a basic desktop setup.

## Examples of use of Bitwarden in chezmoi

username = {{ (bitwarden "item ID or name" "property name").login.username }}
password = {{ (bitwarden "item ID or name" "property name").login.password }}
github_public = {{ (bitwarden "github_ssh_key" "sshKey").publicKey }}

{{ (bitwardenFields "item" "item ID or name").property_name.value }}
{{ bitwardenAttachment "id_rsa" "bf22e4b4-ae4a-4d1c-8c98-ac620004b628" }}
????? {{ bitwardenAttachmentByRef "id_rsa" "item ID or name" "property name" }}

### Secrets Manager

{{ (bitwardenSecrets "be8e0ad8-d545-4017-a55a-b02f014d4158" .accessToken).value }}

### Querying on command line

bw get item "github_ssh_key" --raw | jq -r '.sshKey.publicKey'


## Linux Setup Instructions

THESE ARE OLD, RANDOM NOTES FROM A LAND BEFORE TIME. IGNORE.

### TODOs

- COPY wallpapers

### New Machine Setup

- Install your favorite linux distro on the new host machine ("newhost" from here on out).
  Instructions here are for Arch.
- Install some basics:
  ```bash
  sudo pacman -Syu yay
  pacman -Syu atuin bat coreutils curl eza fd fzf \
      github-cli git git-delta gnupg \
      ripgrep tmux ugrep wget xz zoxide zsh
  ```
- use the Ventoy USB key to get ssh secrets & config from 'ssh' folder. Make sure you fix the permissions after the copy:
  ```bash
  cd $HOME/.ssh
  fd -tf |xargs chmod 600
  fd -tf --glob '*.pub' |xargs chmod 644
  fd -td |xargs chmod 700
  chmod 700 .
  ```
- Install 1password and 1password-cli, setup account access, then
  go to Settings>Developer and enable SSH integration.
- Set up chezmoi with our dotfiles:

  ```bash
  yay -Syu chezmoi
  chezmoi init git@github.com:ashebanow/dotfiles.git
  chezmoi apply
  ```

  Close your shell window and reopen it to use the dotfiles.

- Install docker, docker compose, and portainer agent:

  ```bash
  yay -Syu docker docker-compose
  sudo systemctl enable docker.service
  sudo systemctl start docker.service
  # NOTE: you only need this if you want to have portainer manager your machine.
  # More useful for servers than desktops.
  docker run -d \
     -p 9001:9001 \
     --name portainer_agent \
     --restart=always \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /var/lib/docker/volumes:/var/lib/docker/volumes \
     portainer/agent:2.19.5
  ```

Afterwards, be sure to run the Firewall app and add a new service portainer-agent on port 9001, and put it in the Docker zone.

Now, on your portainer server, connect to the portainer agent on your new system.

### Setting up lxc (ubuntu)

1. Create LXC from template but DO NOT start it up yet. Use DHCP and host DNS settings.

2. Edit `/etc/pve/lxc/<LXC_ID>.conf`, where `LXC_ID` is 104, 105, etc. Add the following lines:

   ```bash
   lxc.cgroup2.devices.allow: c 10:200 rwm
   lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
   ```

3. Start the LXC, and open a console to it. Run the following:

   ```bash
   # tell proxmox not to update this LXC's resolve.conf, because it can break with tailscale on host.
   touch /etc/.pve-ignore.resolv.conf
   # update ubuntu system & install curl
   apt update && apt upgrade -y && apt install curl -y
   # reboot
   reboot now
   ```

4. After the LXC has restarted, open a console once more and install Tailscale as shown below. You will need to follow the instructions from the tailscale up command to continue.

   ```bash
   # install and start tailscale
   curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/lunar.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
   curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/lunar.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
   apt update && apt upgrade -y && apt install tailscale -y
   tailscale up --ssh --accept-routes
   # Go to the indicated website and register/approve the machine as needed.
   # Be sure to set no-expiry so that the server doesn't need to reauth all the time.
   ```

### Repositories to setup locally

Here are the GitHub URLs for each Development/ subdirectory:

```
./ricing/firefox-nordic-theme: https://github.com/EliverLara/firefox-nordic-theme.git
./ricing/firefox-nordic-theme/chrome/firefox-nordic-theme: https://github.com/EliverLara/firefox-nordic-theme.git
./ricing/dracula/gnome-terminal: https://github.com/dracula/gnome-terminal
./ricing/dracula/git: https://github.com/dracula/git.git
./ricing/dracula/wezterm: https://github.com/dracula/wezterm.git
./ricing/dracula/foot: https://github.com/dracula/foot
./ricing/dracula/warp: https://github.com/dracula/warp.git
./ricing/dracula/zsh-syntax-highlighting: https://github.com/dracula/zsh-syntax-highlighting.git
./ricing/dracula/zsh: https://github.com/dracula/zsh.git
./ricing/dracula/wallpaper: https://github.com/dracula/wallpaper.git
./ricing/dracula/obsidian: https://github.com/dracula/obsidian.git
./homelab/homelab-cattivi: git@github.com:ashebanow/homelab-cattivi.git
./homelab/nix-config: https://github.com/ashebanow/nix-config.git
```


### Proxmox

#### New LXCs

Install, ideally via community script.

Install tailscale in most cases, but not for things like iVentoy

Add authorized_keys file containing our ssh public key.


#### Add NAS mounts

For each NAS share your LXCs need, do one or more of the following on the host proxmox system:

```bash
pvesm add cifs storage-isos --server storage --share isos --username ashebanow --password [PASSWORD] --path /mnt/storage-isos
pvesm add cifs storage-backups --server storage --share backups --username ashebanow --password [PASSWORD] --path /mnt/storage-backups
```

You then need to configure each LXC with the internal mounts you will need, as shown in the "Install iVentoy" example below.

##### Install iVentoy

First do the install:

```bash
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/iventoy.sh)"
```

Now add the mount of the ISOs folder, replacing the '108' in the command line with the lxc container ID you just created:

```bash
pct set 108 -mp0 /mnt/storage-isos,mp=/mnt/storage-isos
```


## Misc Apps - Rough Notes
distrobox

atuin:

    bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh)

Next step is to login to their server. If you have never logged in before, you
need to register first. Be sure to save your login info, including your password
and encryption key.

    atuin register -u <YOUR_USERNAME> -e <YOUR EMAIL>

If you have logged in before, do so again with:

    atuin login -u <YOUR_USERNAME>

Once the registration or login has succeeded, you should do a sync:

    atuin sync

asdf (ruby, python, js/node)

bat (ubuntu derivatives only):

    mkdir -p ~/.local/bin
    ln -s /usr/bin/batcat ~/.local/bin/bat

### lunarvim

No longer used. If you have it installed from a previous version of these
dotfiles, you can uninstall it via:

```bash
bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/uninstall.sh)
```

### warp-terminal

For arch:

    sudo sh -c "echo -e '\n[warpdotdev]\nServer = https://releases.warp.dev/linux/pacman/\$repo/\$arch' >> /etc/pacman.conf"
    sudo pacman-key -r "linux-maintainers@warp.dev"
    sudo pacman-key --lsign-key "linux-maintainers@warp.dev"
    sudo pacman -Sy warp-terminal

For ubuntu:

    sudo apt-get install wget gpg
    wget -qO- https://releases.warp.dev/linux/keys/warp.asc | gpg --dearmor > warpdotdev.gpg
    sudo install -D -o root -g root -m 644 warpdotdev.gpg /etc/apt/keyrings/warpdotdev.gpg
    sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main" > /etc/apt/sources.list.d/warpdotdev.list'
    rm warpdotdev.gpg
    sudo apt update && sudo apt install warp-terminal

### tailscale

    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale completion zsh > "${fpath[1]}/_tailscale"

### delta

download current release .deb from [releases page](https://github.com/dandavison/delta/releases)

```bash
sudo dpkg -i ~/Downloads/git-delta_XXXX.deb
```

### getnf

```bash
curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash
```

#### To install the nerd fonts:

```bash
getnf -U    # update already installed fonts
getnf -i "DejaVuSansMono,FiraCode,Hack,JetBrainsMono,Meslo,NerdFontsSymbolsOnly,Noto,RobotoMono,SourceCodePro"
```

### eza

```bash
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
sudo apt update && sudo apt install -y eza
```

To install a custom theme, do the following:

```bash
# theme can be one of:
#    default,frosty,black,white,gruvbox-dark,gruvbox-light,
#    catppucin,one_dark,dracula, tokyonight
EZA_THEME=default
git clone https://github.com/eza-community/eza-themes.git
mkdir -p ~/.config/eza
ln -sf "$(pwd)/eza-themes/themes/$EZA_THEME.yml" ~/.config/eza/theme.yml
```

### nvm

Note that you probably want to change this URL to match the latest supported
version:

`curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash`
