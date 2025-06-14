# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_flatpaks ]; then
  return;
fi
sourced_install_flatpaks=true

function install_flatpak_if_needed {
	if command -v flatpak; then
		# make sure that flathub content is available
		flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
		return
	fi

	if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
		sudo pacman -S flatpak
	elif [[ $ID == *"ubuntu"* || $ID == *"debian"* || $ID_LIKE == *"debian"* ]]; then
		sudo apt install flatpak
	elif [[ $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
		if command -v dnf5; then
			sudo dnf5 install flatpak
		else
			sudo dnf install flatpak
		fi
	else
		# give up for now
		log_error "Unsupported/unknown linux variant, cannot install flatpak"
		exit 1
	fi

	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	flatpak update --appstream
}

function install_flatpak_apps {
	readarray -t flatpaks_list <"{{- .chezmoi.config.sourceDir -}}/Flatfile"
	flatpak install --user -y --noninteractive --or-update "${flatpaks_list[@]}"
}
