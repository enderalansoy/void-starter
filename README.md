# void-starter

This is a WIP!

This repository contains a comprehensive script designed to set up a Void Linux installation with various desktop environments and additional configurations for gaming. 

The script guides users through the process of updating their system, installing desktop environments, configuring audio, installing NVIDIA drivers, and setting up a gaming toolbox.

## Features
- Install and configure desktop environments (KDE, GNOME, Cinnamon)
- Set up Pipewire for audio management
- Install and configure NVIDIA drivers
- Add extra repositories
- Install a comprehensive gaming toolbox including wine libraries, Steam and Lutris.

## How to run

ONLY USE THIS SCRIPT ON A NEWLY INSTALLED BASE VOID LINUX SYSTEM! If you already have a DE installed there will be conflicts, and your setup might break afterwards.

1. Install dependencies: `sudo xbps-install -S openssl curl`

2. Run script: ```/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/enderalansoy/void-starter/main/setup-de.sh)"```

