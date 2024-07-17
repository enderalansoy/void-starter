#!/bin/bash

# Function to enable a service
enable_service() {
  sudo ln -s /etc/sv/$1 /var/service
}

# Function to disable a service
disable_service() {
  sudo rm /var/service/$1
}

# Function to show filtered output in dialog without exit button
show_output() {
  local command="$1"
  local title="$2"
  local tempfile=$(mktemp)
  touch "$tempfile"

  # Run the command and output to tempfile in the background
  $command &> "$tempfile" &
  local pid=$!

  # Display the output in a dialog tailboxbg
  dialog --title "$title" --programbox "tail -f $tempfile" 20 70

  wait $pid
  rm "$tempfile"
}

# Function to add extra repositories
add_extra_repositories() {
  dialog --yesno "Do you want to add extra repositories to XBPS (required for gaming additions)? This may include nonfree software." 10 50
  if [[ $? -eq 0 ]]; then
    show_output "sudo xbps-install -Sy void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree" "Adding extra repositories"
  fi
}

# Function to setup Pipewire
setup_pipewire() {
  # Stop and remove PulseAudio if it is installed
  if xbps-query -l | grep -q 'pulseaudio'; then
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
    dialog --yesno "NVIDIA card detected. Do you want to install NVIDIA drivers?" 10 50
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
        return
      fi

      # Install the NVIDIA driver package
      show_output "sudo xbps-install -Sy $DRIVER_PACKAGE" "Installing NVIDIA drivers"

      # Load the NVIDIA kernel module
      sudo modprobe nvidia
    fi
  fi
}

# Function to install the gaming toolbox
install_gaming_toolbox() {
  add_extra_repositories

  # Ask the user to select their GPU type
  GPU=$(dialog --menu "Select your GPU type:" 15 50 5 \
    1 "NVIDIA recent (600/700/800+)" \
    2 "NVIDIA 400/500" \
    3 "NVIDIA legacy" \
    4 "AMD" \
    5 "Intel" 3>&1 1>&2 2>&3)

  # Install Steam dependencies common to all systems
  show_output "sudo xbps-install -Sy libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit" "Installing common Steam dependencies"

  case $GPU in
    1)
      show_output "sudo xbps-install -Sy nvidia-libs-32bit" "Installing NVIDIA recent 32-bit libraries"
      ;;
    2)
      show_output "sudo xbps-install -Sy nvidia390-libs-32bit" "Installing NVIDIA 400/500 32-bit libraries"
      ;;
    3)
      show_output "sudo xbps-install -Sy nvidia340-libs-32bit" "Installing NVIDIA legacy 32-bit libraries"
      ;;
    4)
      show_output "sudo xbps-install -Sy mesa-dri-32bit" "Installing AMD 32-bit libraries"
      ;;
    5)
      # Intel only requires the common packages, no additional packages needed
      ;;
    *)
      dialog --msgbox "Invalid choice. Exiting." 10 50
      return
      ;;
  esac

  # Install Steam and Mono
  show_output "sudo xbps-install -Sy mono steam" "Installing Steam and Mono"

  # Install Wine and Proton
  show_output "sudo xbps-install -Sy wine wine-common wine-devel wine-gecko wine-mono wine-tools winetricks wineasio" "Installing Wine (first batch)"
  show_output "sudo xbps-install -Sy libwine" "Installing Wine (second batch)"
  show_output "sudo xbps-install -Sy wine-32bit wine-devel-32bit wineasio-32bit" "Installing Wine (third batch)"
  show_output "sudo xbps-install -Sy libwine-32bit protontricks" "Installing Wine (fourth batch)"

  # Install additional GPU-related packages
  show_output "sudo xbps-install -Sy MangoHud MesaLib-devel Vulkan-Headers Vulkan-Tools Vulkan-ValidationLayers libspa-vulkan mesa mesa-vulkan-overlay-layer python3-glad vkBasalt vulkan-loader vulkan-loader-devel MangoHud-32bit MesaLib-devel-32bit Vulkan-ValidationLayers-32bit libspa-vulkan-32bit mesa-32bit mesa-vulkan-overlay-layer-32bit vkBasalt-32bit vulkan-loader-32bit vulkan-loader-devel-32bit" "Installing GPU-related packages"

  case $GPU in
    4)
      show_output "sudo xbps-install -Sy amdvlk amdvlk-32bit mesa-vulkan-radeon mesa-vulkan-radeon-32bit mesa-vaapi mesa-vdpau" "Installing AMD-specific packages"
      ;;
    5)
      show_output "sudo xbps-install -Sy mesa-vulkan-intel mesa-vulkan-intel-32bit" "Installing Intel-specific packages"
      ;;
    *)
      # NVIDIA does not need additional packages beyond the common ones
      ;;
  esac

  # Install Lutris
  show_output "sudo xbps-install -Sy lutris" "Installing Lutris"

  # Adjust ulimit for the user
  local username=$(whoami)
  local ulimit_val=$(ulimit -Hn)
  if [[ $ulimit_val -lt 524288 ]]; then
    sudo bash -c "echo '$username hard nofile 524288' >> /etc/security/limits.conf"
  fi
}

# Function to install desktop environment
install_desktop_environment() {
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
      return
      ;;
  esac

  # Install desktop environment and necessary packages
  show_output "sudo xbps-install -Sy xorg NetworkManager $PACKAGES" "Installing desktop environment"

  # Enable services
  dialog --infobox "Enabling services..." 10 50
  enable_service dbus
  enable_service NetworkManager

  # Disable wpa_supplicant service
  disable_service wpa_supplicant

  # Disable other display managers, if they are enabled
  disable_service sddm
  disable_service gdm
  disable_service lightdm
  disable_service xdm
  disable_service nodm
  disable_service stdm

  # Enable the display manager of choice
  enable_service $DISPLAY_MANAGER
}

# Main menu function
main_menu() {
  while true; do
    CHOICE=$(dialog --menu "Void Linux Setup Utility" 20 50 10 \
      1 "Add Extra Repositories" \
      2 "Setup Pipewire" \
      3 "Setup NVIDIA Drivers" \
      4 "Install Gaming Toolbox" \
      5 "Install Desktop Environment" \
      6 "Update System" \
      7 "Exit" 3>&1 1>&2 2>&3)
    
    case $CHOICE in
      1)
        add_extra_repositories
        ;;
      2)
        setup_pipewire
        ;;
      3)
        setup_nvidia
        ;;
      4)
        install_gaming_toolbox
        ;;
      5)
        install_desktop_environment
        ;;
      6)
        show_output "sudo xbps-install -Suy" "Updating the system"
        ;;
      7)
        clear
        exit 0
        ;;
      *)
        dialog --msgbox "Invalid choice. Exiting." 10 50
        clear
        exit 1
        ;;
    esac
  done
}

# Install dialog if not already installed
sudo xbps-install -Sy dialog >/dev/null 2>&1

# Run the main menu
main_menu
