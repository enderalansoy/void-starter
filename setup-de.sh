#!/bin/bash

# Function to enable a service
enable_service() {
  sudo ln -s /etc/sv/$1 /var/service
}

# Function to disable a service
disable_service() {
  sudo rm /var/service/$1
}

# Function to show progress bar
show_progress() {
  {
    $1 2>&1 | while read -r line; do
      if [[ "$line" =~ \([0-9]+%\) ]]; then
        percent=$(echo "$line" | grep -oP '\(\K[0-9]+(?=%\))')
        echo $percent
        echo "XXX"
        echo "Progress: $percent%"
        echo "XXX"
      fi
    done
  } | dialog --title "$2" --gauge "$3" 10 70 0
}

# Function to setup Pipewire
setup_pipewire() {
  # Stop and remove PulseAudio if it is installed
  if xbps-query -l | grep -q '^ii.*pulseaudio'; then
    sudo sv stop pulseaudio
    disable_service pulseaudio
    show_progress "sudo xbps-remove -Ry pulseaudio" "Removing PulseAudio" "Please wait..."
  fi

  # Install Pipewire and related packages
  show_progress "sudo xbps-install -Sy pipewire wireplumber alsa-pipewire libspa-bluetooth pipewire-pulse" "Installing Pipewire" "Please wait..."

  # Enable Pipewire configuration
  sudo mkdir -p /etc/pipewire/pipewire.conf.d
  sudo ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
  sudo ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/
  sudo mkdir -p /etc/alsa/conf.d
  sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/
  sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/

  # Create a startup script for Pipewire
  sudo bash -c 'echo -e "#!/bin/bash\npipewire &\npipewire-pulse &" > /usr/local/bin/start-pipewire.sh'
  sudo chmod +x /usr/local/bin/start-pipewire.sh

  # Add the startup script to the user's session autostart
  mkdir -p ~/.config/autostart
  echo -e "[Desktop Entry]\nType=Application\nExec=pipewire & pipewire-pulse\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\nName=Pipewire" > ~/.config/autostart/pipewire.desktop
}

# Function to setup NVIDIA drivers
setup_nvidia() {
  # Detect NVIDIA card
  NVIDIA_CARD=$(lspci | grep -i 'NVIDIA')

  if [[ -n $NVIDIA_CARD ]]; then
    dialog --yesno "NVIDIA card detected. Do you want to install NVIDIA drivers?" 10 50
    if [[ $? -eq 0 ]]; then
      # Add the nonfree repository
      show_progress "sudo xbps-install -Sy void-repo-nonfree" "Adding nonfree repository" "Please wait..."

      # Determine the correct driver package
      if echo $NVIDIA_CARD | grep -E 'GTX [8-9]|RTX|Tesla [P-Q]|Quadro [P-Q]|TITAN'; then
        DRIVER_PACKAGE="nvidia"
      elif echo $NVIDIA_CARD | grep -E 'GTX [6-7]'; then
        DRIVER_PACKAGE="nvidia470"
      elif echo $NVIDIA_CARD | grep -E 'GT[4-5]|GTX [4-5]'; then
        DRIVER_PACKAGE="nvidia390"
      else
        dialog --msgbox "Unsupported NVIDIA card. Exiting." 10 50
        exit 1
      fi

      # Install the NVIDIA driver package
      show_progress "sudo xbps-install -Sy $DRIVER_PACKAGE" "Installing NVIDIA drivers" "Please wait..."

      # Load the NVIDIA kernel module
      sudo modprobe nvidia
    fi
  fi
}

# Install dialog if not already installed
sudo xbps-install -Sy dialog >/dev/null 2>&1

# Ask if the user wants to update the system
dialog --yesno "Do you want to update the system first?" 10 50
if [[ $? -eq 0 ]]; then
  show_progress "sudo xbps-install -Suy" "Updating the system" "Please wait..."
fi

# Choose desktop environment
DE=$(dialog --menu "Choose a desktop environment to install:" 15 50 3 \
  1 "KDE" \
  2 "GNOME" \
  3 "Cinnamon" 3>&1 1>&2 2>&3)

case $DE in
  1)
    DE="KDE"
    PACKAGES="kde5 kde5-baseapps sddm"
    DISPLAY_MANAGER="sddm"
    ;;
  2)
    DE="GNOME"
    PACKAGES="gnome gdm"
    DISPLAY_MANAGER="gdm"
    ;;
  3)
    DE="Cinnamon"
    PACKAGES="cinnamon-all lightdm"
    DISPLAY_MANAGER="lightdm"
    ;;
  *)
    dialog --msgbox "Invalid choice. Exiting." 10 50
    exit 1
    ;;
esac

# Install desktop environment and necessary packages
show_progress "sudo xbps-install -Sy xorg NetworkManager $PACKAGES" "Installing desktop environment" "Please wait..."

# Enable services
dialog --infobox "Enabling services..." 10 50
enable_service dbus
enable_service $DISPLAY_MANAGER
enable_service NetworkManager

# Disable wpa_supplicant service
disable_service wpa_supplicant

# Setup Pipewire
setup_pipewire

# Setup NVIDIA drivers
setup_nvidia

# Prompt for reboot
dialog --yesno "Installation complete. Would you like to reboot now?" 10 50
if [[ $? -eq 0 ]]; then
  sudo reboot
else
  dialog --msgbox "Please reboot your system manually to apply the changes." 10 50
fi
