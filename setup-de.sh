#!/bin/bash

# Function to enable a service
enable_service() {
  sudo ln -s /etc/sv/$1 /var/service
}

# Function to disable a service
disable_service() {
  sudo rm /var/service/$1
}

# Function to setup Pipewire
setup_pipewire() {
  # Stop and remove PulseAudio if it is installed
  if xbps-query -l | grep -q '^ii.*pulseaudio'; then
    sudo sv stop pulseaudio
    disable_service pulseaudio
    sudo xbps-remove -Ry pulseaudio
  fi

  # Install Pipewire and related packages
  sudo xbps-install -Sy pipewire wireplumber alsa-pipewire libspa-bluetooth pipewire-pulse

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
  echo -e "[Desktop Entry]\nType=Application\nExec=/usr/local/bin/start-pipewire.sh\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\nName=Pipewire" > ~/.config/autostart/pipewire.desktop

  if [[ $DE == "KDE" ]]; then
    mkdir -p ~/.config/autostart-scripts
    cp /usr/local/bin/start-pipewire.sh ~/.config/autostart-scripts/
  elif [[ $DE == "Cinnamon" ]]; then
    mkdir -p ~/.config/autostart
    cp ~/.config/autostart/pipewire.desktop ~/.config/autostart/
  fi
}

# Function to setup NVIDIA drivers
setup_nvidia() {
  # Detect NVIDIA card
  NVIDIA_CARD=$(lspci | grep -i 'NVIDIA')

  if [[ -n $NVIDIA_CARD ]]; then
    read -n 1 -p "NVIDIA card detected. Do you want to install NVIDIA drivers? (y/n): " install_nvidia
    if [[ "$install_nvidia" =~ ^[Yy]$ ]]; then
      # Add the nonfree repository
      sudo xbps-install -Sy void-repo-nonfree

      # Determine the correct driver package
      if echo $NVIDIA_CARD | grep -E 'GTX [8-9]|RTX|Tesla [P-Q]|Quadro [P-Q]|TITAN'; then
        DRIVER_PACKAGE="nvidia"
      elif echo $NVIDIA_CARD | grep -E 'GTX [6-7]'; then
        DRIVER_PACKAGE="nvidia470"
      elif echo $NVIDIA_CARD | grep -E 'GT[4-5]|GTX [4-5]'; then
        DRIVER_PACKAGE="nvidia390"
      else
        echo "Unsupported NVIDIA card. Exiting."
        exit 1
      fi

      # Install the NVIDIA driver package
      sudo xbps-install -Sy $DRIVER_PACKAGE

      # Load the NVIDIA kernel module
      sudo modprobe nvidia
    fi
  fi
}

# Ask if the user wants to update the system
read -n 1 -p "Do you want to update the system first? (y/n): " update_choice
if [[ "$update_choice" =~ ^[Yy]$ ]]; then
  sudo xbps-install -Suy
fi

# Choose desktop environment
echo "Choose a desktop environment to install:"
echo "1) KDE"
echo "2) GNOME"
echo "3) Cinnamon"
read -n 1 -p "Enter the number of your choice: " choice

case $choice in
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
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

# Install desktop environment and necessary packages
sudo xbps-install -Sy xorg NetworkManager $PACKAGES

# Enable services
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
read -n 1 -p "Installation complete. Would you like to reboot now? (y/n): " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
  sudo reboot
else
  echo "Please reboot your system manually to apply the changes."
fi
