# dotfiles README

## Bluefin-DX or Bazzite/Bazzite-DX

1. Install your preferred image and boot into it. Be sure to use the -nvidia variant if appropriate. I recommend using encrypted BTRFS.

2. If you didn't change your hostname from the default during OS setup, you can change your hostname with `sudo hostnamectl hostname <change_me_PLEASE>`.

3. Go through the post-install setup wizard, if it runs automatically.

4. Click the `Show Apps` button in the doc, run `System Update`.

    Alternatively, run `ujust update`.

    IRun `ujust bazzite-cli` or `ujust bluefin-cli` as appropriate.

    Reboot.

5. Add the flatpak repos we need from fedora and flathub (preset on bazzite at least):

   ```bash
   flatpak remote-add --if-not-exists fedora oci+https://registry.fedoraproject.org
   flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
   flatpak update --appstream
   ```

6. Install bitwarden flatpak and its CLI:

   ```bash
    sudo flatpak install bitwarden
    brew install bitwarden-cli
    bw login        # enter account email and password
   ```

7. To turn off password entry when using sudo, run the `sudo visudo` command, then search for the line that looks like:

   ```bash
   #%wheel         ALL = (ALL) NOPASSWD: ALL
   ```

   Uncoment that line, then comment the one above it that says `ALL` instead of `NOPASSWORD: ALL`. Save and exit the editor.

8. Copy ssh folder to your home directory. Set the permissions properly:
    * all .pub files should be mode 644
    * all other files should be 640
    * the .ssh directory and the hosts directory should be 755

    Alternatively, you can copy it from a machine on your network that already has your keys. This will only work if the other host is set up to allow password auth. Most hosts aren't setup this way. Note that the permissions above shoud already be set using this command, but double-check and fix if needed.

    ```bash
    scp -r ashebanow@HOSTAME.cattivi.internal:/var/home/ashebanow/.ssh ~/
    ```

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
