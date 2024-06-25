#!/bin/bash

# Function to enable a service
enable_service() {
  sudo ln -s /etc/sv/$1 /var/service
}

# Function to disable a service
disable_service() {
  sudo rm /var/service/$1
}

# Function to show output in a dialog box
show_output() {
  local command="$1"
  local title="$2"
  local tempfile=$(mktemp)
  touch "$tempfile"
  tail -f "$tempfile" | dialog --title "$title" --tailbox - 20 70 &
  local pid=$!
  $command &> "$tempfile"
  kill $pid
  rm "$tempfile"
}

# Function to setup Pipewire
setup_pipewire() {
  # Stop and remove PulseAudio if it is installed
  if xbps-query -l | grep -q '^ii.*pulseaudio'; then
    sudo sv stop pulseaudio
    disable_service pulseaudio
    show_output "sudo xbps-remove -Ry pulseaudio" "Removing PulseAudio"
  fi

  # Install Pipewire and related packages
  show_output "sudo xbps-install -Sy pipewire wireplumber alsa-pipewire libspa-bluetooth" "Installing Pipewire"

  # Enable Pipewire configuration
  sudo mkdir -p /etc/pipewire/pipewire.conf.d
  sudo ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
  sudo ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/
  sudo mkdir -p /etc/alsa/conf.d
  sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/
  sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/

  # Add the startup script to the user's session autostart
  mkdir -p ~/.config/autostart
  echo -e "[Desktop Entry]\nType=Application\nExec=pipewire & pipewire-pulse\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\nName=Pipewire" > ~/.config/autostart/pipewire.desktop
}

# Function to setup NVIDIA drivers
setup_nvidia() {
  # Detect NVIDIA card
  NVIDIA_CARD=$(lspci | grep -i 'NVIDIA')

  if [[ -n $NVIDIA_CARD ]]; then
    dialog --yesno "NVIDIA card detected. Do you want to install NVIDIA drivers? This requires addition of Void's NONFREE repository" 10 50
    if [[ $? -eq 0 ]]; then
      # Add the nonfree repository
      show_output "sudo xbps-install -Sy void-repo-nonfree" "Adding nonfree repository"

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
      show_output "sudo xbps-install -Sy $DRIVER_PACKAGE" "Installing NVIDIA drivers"

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
  show_output "sudo xbps-install -Suy" "Updating the system"
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
show_output "sudo xbps-install -Sy xorg NetworkManager $PACKAGES" "Installing desktop environment"

# Setup Pipewire
setup_pipewire

# Setup NVIDIA drivers
setup_nvidia

# Enable services
dialog --infobox "Enabling services..." 10 50
enable_service dbus
enable_service NetworkManager

# Disable wpa_supplicant service
disable_service wpa_supplicant

# Lastly, enable the display manager
enable_service $DISPLAY_MANAGER

# Prompt for reboot
dialog --yesno "Installation complete. Would you like to reboot now?" 10 50
if [[ $? -eq 0 ]]; then
  sudo reboot
else
  dialog --msgbox "Please reboot your system manually to apply the changes." 10 50
fi
