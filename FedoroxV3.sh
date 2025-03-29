#!/bin/bash

# Fedora Setup Script
# This script installs and configures a comprehensive set of applications and tools for Fedora

# ----- Variables -----
ACTUAL_USER=$(logname)
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)
LOG_FILE="$ACTUAL_HOME/fedora_setup.log"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----- Helper Functions -----
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [SUCCESS] $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [WARNING] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] $1" >> "$LOG_FILE"
}

# ----- System Checks -----
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_fedora() {
    if ! grep -q "Fedora" /etc/os-release; then
        log_error "This script is designed for Fedora"
        exit 1
    fi
}

# ----- Installation Functions -----
setup_repositories() {
    log "Setting up repositories..."
    
    # Install DNF plugins
    dnf install -y dnf-plugins-core

    # Remove unwanted repositories
    log "Removing irrelevant repositories..."
    rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:phracek:PyCharm.repo
    rm -f /etc/yum.repos.d/google-chrome.repo
    rm -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
    rm -f /etc/yum.repos.d/rpmfusion-nonfree-steam.repo

    # Install RPM Fusion repositories
    log "Installing RPM Fusion repositories..."
    dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                   https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    
    # Setup Brave repository
    log "Setting up Brave browser repository..."
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
    
    # Setup Flatpak
    log "Setting up Flatpak..."
    dnf install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak repair --system
    flatpak update -y
    
    log_success "Repositories configured successfully"
}

setup_snapshots() {
    log "Setting up Snapper for system snapshots..."
    
    # Check if filesystem is BTRFS
    if [ "$(findmnt -no FSTYPE /)" != "btrfs" ]; then
        log_warning "Not using BTRFS filesystem, snapshots may not work correctly"
    fi
    
    # Install snapper
    dnf install -y snapper
    
    # Configure snapper
    DATE=$(date +%Y-%m-%d-%H-%M-%S)
    
    # Enable and start snapper services
    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    
    # Create configs if they don't exist
    if ! snapper -c root list &>/dev/null; then
        snapper -c root create-config /
    fi
    
    if ! snapper -c home list &>/dev/null; then
        snapper -c home create-config /home
    fi
    
    # Create initial snapshots
    snapper -c root create -d "${DATE}_RootFirst" 
    snapper -c home create -d "${DATE}_HomeFirst"
    log_success "Snapper configured and initial snapshots created"
}

optimize_system() {
    log "Optimizing system configuration..."
    
    # Set hostname
    hostnamectl set-hostname FedoroxV3
    
    # Optimize DNF
    log "Optimizing DNF configuration..."
    cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
    
    # Update DNF configuration
    if grep -q "^fastestmirror=" /etc/dnf/dnf.conf; then
        sed -i 's/^fastestmirror=.*/fastestmirror=True/' /etc/dnf/dnf.conf
    else
        echo "fastestmirror=True" >> /etc/dnf/dnf.conf
    fi
    
    if grep -q "^max_parallel_downloads=" /etc/dnf/dnf.conf; then
        sed -i 's/^max_parallel_downloads=.*/max_parallel_downloads=10/' /etc/dnf/dnf.conf
    else
        echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
    fi
    
    log_success "System optimization completed"
}

update_system() {
    log "Updating system packages..."
    dnf upgrade -y
    log_success "System updated successfully"
}

setup_multimedia() {
    log "Setting up multimedia support..."
    
    # Install multimedia codecs
    dnf swap -y ffmpeg-free ffmpeg --allowerasing
    dnf group install multimedia -y

    # Install hardware acceleration for Intel
    dnf install -y intel-media-driver libva-intel-driver
    
    # Install hardware acceleration for AMD
    dnf install -y libva-mesa-driver mesa-vdpau
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    
    # Install multimedia packages (fixed package names)
    dnf install -y gstreamer1-plugins-{good,base} gstreamer1-plugins-bad-free \
                   ffmpeg yt-dlp vlc mpv strawberry mediainfo flac lame \
                   libmpeg2 x264 x265
    
    log_success "Multimedia support installed"
}

install_system_tools() {
    log "Installing system utilities..."
    
    # Install system monitoring and utilities (removed amdgpu_top)
    dnf install -y snapper fwupd cifs-utils samba-client btop htop \
                   fastfetch p7zip unzip git vim neovim curl wget fzf \
                   rsync lsof zsh gcc make python3-pip duf inxi ncdu \
                   kitty bat wl-clipboard go tldr intel-gpu-tools
    
    
    # Install Rust
    log_message "Installing rust..."
    if ! (sudo -v && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh); then
	    log_message "Error: Failed to install rust!"
    fi
    log_success "System utilities installed"
}

setup_virtualization() {
    log "Setting up virtualization support..."
    
    # Install virtualization packages
    dnf install -y @virtualization
    
    # Enable and start libvirtd service
    systemctl enable libvirtd
    systemctl start libvirtd
    
    # Add user to libvirt group
    usermod -aG libvirt $ACTUAL_USER
    
    log_success "Virtualization support installed"
}

install_gaming() {
    log "Installing gaming support..."
    
    # Install gaming utilities (fixed package names for Fedora)
    dnf install -y mangohud goverlay gamemode steam vulkan-loader
    
    # ROCm packages if applicable - using correct Fedora package names
    if lspci | grep -i amd > /dev/null; then
        log "AMD GPU detected, checking for ROCm packages..."
        # Try to install ROCm core, which is more likely to be available
        if dnf list rocm-opencl 2>/dev/null; then
            log "Installing ROCm packages..."
            dnf install -y rocm-opencl rocm-hip-devel rocm-clinfo --allowerasing
        else
            log_warning "ROCm packages not found in repositories, skipping"
        fi
    fi
    
    log_success "Gaming support installed"
}

# Mkdirs for ProtonDrive Function
mkdir_proton() {
  mkdir -p $ACTUAL_HOME/ProtonDrive/Archives/{Discord,Obsidian} $ACTUAL_HOME/ProtonDrive/Career/MainDocs/
  chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/ProtonDrive
  log_success "ProtonDrive directories created successfully"
}

# Setup game drive mount function
setup_gamedrive_mount() {
  log "Setting up game drive mount..."

  # Set mount details
  GAME_DRIVE_UUID="6c52f6b5-b3f3-49c6-a7cc-2793741afe35"
  MOUNT_POINT="/mnt/gamedrive"
  MOUNT_OPTIONS="rw,relatime,compress=zstd:3,nofail"
  FSTAB_ENTRY="UUID=$GAME_DRIVE_UUID $MOUNT_POINT btrfs $MOUNT_OPTIONS 0 0"

  # Check if drive exists using UUID
  if ! blkid -U "$GAME_DRIVE_UUID" > /dev/null 2>&1; then
    log "Game drive with UUID $GAME_DRIVE_UUID not detected, skipping mount setup"
    return 0
  fi

  log "Game drive detected, proceeding with mount setup"

  # Create mount point if it doesn't exist
  if ! [ -d "$MOUNT_POINT" ]; then
    log "Creating mount point at $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
  fi

  # Mount the drive if not already mounted
  if ! mount | grep -q "$MOUNT_POINT"; then
    log "Mounting game drive to $MOUNT_POINT"
    mount -U "$GAME_DRIVE_UUID" "$MOUNT_POINT" -o "$MOUNT_OPTIONS"
    if [ $? -ne 0 ]; then
      log_error "Failed to mount game drive"
      return 1
    fi
  else
    log "Game drive already mounted to $MOUNT_POINT"
  fi

  # Add to fstab if not already there
  if ! grep -q "$GAME_DRIVE_UUID" /etc/fstab; then
    log "Adding game drive to /etc/fstab for auto-mount on boot"
    echo "$FSTAB_ENTRY" | tee -a /etc/fstab > /dev/null
  else
    log "Game drive already in /etc/fstab"
  fi
  
  # Reload systemd to recognize changes in fstab
  systemctl daemon-reload
  
  log "Game drive mounted successfully and set up for auto-mount on boot"
  return 0
}

# Add user to important groups for hardware access
setup_user_groups() {
  log "Adding user to important system groups..."
  
  # Check if render group exists
  if getent group render > /dev/null; then
    usermod -a -G render $ACTUAL_USER
    log "Added user to render group"
  else
    log_warning "render group not found"
  fi
  
  # Check if video group exists
  if getent group video > /dev/null; then
    usermod -a -G video $ACTUAL_USER
    log "Added user to video group"
  else
    log_warning "video group not found"
  fi
  
  # Additional useful groups
  for GROUP in input dialout plugdev; do
    if getent group $GROUP > /dev/null; then
      usermod -a -G $GROUP $ACTUAL_USER
      log "Added user to $GROUP group"
    fi
  done
  
  log_success "User groups setup completed"
}

# Install nerd fonts for programming and terminal use
install_nerd_fonts() {
  log "Installing Nerd Fonts..."
  
  # Create fonts directory if it doesn't exist
  FONTS_DIR="$ACTUAL_HOME/.local/share/fonts"
  mkdir -p "$FONTS_DIR"
  
  # Temporary directory for downloads
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  # Download and install Hack Nerd Font
  log "Downloading Hack Nerd Font..."
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Hack.zip
  if [ -f "Hack.zip" ]; then
    unzip -q Hack.zip -d "$FONTS_DIR/Hack"
    log "Installed Hack Nerd Font"
  else
    log_error "Failed to download Hack Nerd Font"
  fi
  
  # Download and install FiraCode Nerd Font
  log "Downloading FiraCode Nerd Font..."
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip
  if [ -f "FiraCode.zip" ]; then
    unzip -q FiraCode.zip -d "$FONTS_DIR/FiraCode"
    log "Installed FiraCode Nerd Font"
  else
    log_error "Failed to download FiraCode Nerd Font"
  fi
  
  # Download and install JetBrainsMono Nerd Font (as an additional font)
  log "Downloading JetBrainsMono Nerd Font..."
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip
  if [ -f "JetBrainsMono.zip" ]; then
    unzip -q JetBrainsMono.zip -d "$FONTS_DIR/JetBrainsMono"
    log "Installed JetBrainsMono Nerd Font"
  else
    log_error "Failed to download JetBrainsMono Nerd Font"
  fi
  
  # Download and install CascadiaCode Nerd Font (as an additional font)
  log "Downloading CascadiaCode Nerd Font..."
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip
  if [ -f "CascadiaCode.zip" ]; then
    unzip -q CascadiaCode.zip -d "$FONTS_DIR/CascadiaCode"
    log "Installed CascadiaCode Nerd Font"
  else
    log_error "Failed to download CascadiaCode Nerd Font"
  fi
  
  # Clean up
  cd - > /dev/null
  rm -rf "$TEMP_DIR"
  
  # Update font cache
  fc-cache -f
  
  # Fix ownership
  chown -R $ACTUAL_USER:$ACTUAL_USER "$FONTS_DIR"
  
  log_success "Nerd Fonts installed successfully"
}

# Install system fonts for better web and document support
install_system_fonts() {
  log "Installing system fonts..."
  
  # Install Google fonts
  dnf install -y google-noto-sans-fonts google-noto-serif-fonts google-noto-cjk-fonts google-noto-emoji-fonts
  
  # Install common system fonts
  dnf install -y liberation-fonts dejavu-fonts-all
  
  # Install Microsoft compatible fonts
  dnf install -y fontconfig-font-replacements cabextract
  rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
  
  # Install other useful fonts
  dnf install -y ibm-plex-fonts-all mozilla-fira-fonts-common mozilla-fira-sans-fonts mozilla-fira-mono-fonts
  
  # Install international fonts
  dnf install -y wqy-zenhei-fonts vlgothic-fonts smc-fonts-common lohit-assamese-fonts lohit-bengali-fonts
  
  log_success "System fonts installed successfully"
}



install_flatpaks() {
    log "Installing Flatpak applications..."
    
    # Productivity apps
    flatpak install -y flathub org.onlyoffice.desktopeditors md.obsidian.Obsidian \
                             org.gimp.GIMP net.ankiweb.Anki
    
    # Browsers and communication
    flatpak install -y flathub io.gitlab.librewolf-community app.zen_browser.zen \
                             im.riot.Riot org.telegram.desktop dev.vencord.Vesktop
    
    # Media applications
    flatpak install -y flathub com.github.iwalton3.jellyfin-media-player \
                             tv.plex.PlexDesktop com.plexamp.Plexamp \
                             org.kde.gwenview com.obsproject.Studio \
                             org.nickvision.tubeconverter \
                             org.kde.kdenlive org.blender.Blender org.kde.krita
    
    # Gaming
    flatpak install -y flathub net.lutris.Lutris com.heroicgameslauncher.hgl \
                             org.yuzu_emu.yuzu
    
    # System utilities
    flatpak install -y flathub com.github.tchx84.Flatseal com.usebottles.bottles \
                             net.nokyan.Resources io.github.dimtpap.coppwr \
                             org.nickvision.cavalier com.rustdesk.RustDesk \
                             com.github.unrud.VideoDownloader org.kde.kwalletmanager5
    
    log_success "Flatpak applications installed"
}

install_brave_browser() {
    log "Installing Brave Browser..."
    dnf install -y brave-browser
    log_success "Brave Browser installed"
}

setup_cifs_mount() {
    log "Setting up CIFS mounts..."
    
    # Ask if user wants to set up CIFS mounts
    read -p "Do you want to set up CIFS/SMB network shares? (y/n): " setup_cifs
    
    if [[ "$setup_cifs" != "y" && "$setup_cifs" != "Y" ]]; then
        log "Skipping CIFS mount setup"
        return
    fi
    
    # Set mount details
    read -p "Enter server IP address (e.g., 192.168.0.2): " SERVER_IP
    read -p "Enter share name (e.g., media): " SHARE_NAME
    read -p "Enter mount point (e.g., /mnt/media): " MOUNT_POINT
    
    SHARE="//$SERVER_IP/$SHARE_NAME"
    CREDENTIALS_FILE="/etc/cifs-credentials"
    FSTAB_ENTRY="$SHARE $MOUNT_POINT cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=$ACTUAL_USER,gid=$ACTUAL_USER,nofail 0 0"
    
    # Prompt for username and password securely
    read -p "Enter CIFS username: " CIFS_USER
    read -s -p "Enter CIFS password: " CIFS_PASS
    echo ""
    
    # Create credentials file securely
    echo -e "username=$CIFS_USER\npassword=$CIFS_PASS" > "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    
    # Create mount point if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT"
    fi
    
    # Mount the share
    mount -t cifs "$SHARE" "$MOUNT_POINT" -o "credentials=$CREDENTIALS_FILE,vers=3.0,uid=$ACTUAL_USER,gid=$ACTUAL_USER,nofail"
    
    # Add to fstab if not already present
    if ! grep -q "$SHARE" /etc/fstab; then
        echo "$FSTAB_ENTRY" >> /etc/fstab
    fi
    
    # Reload systemd to recognize changes in fstab
    systemctl daemon-reload
    
    log_success "CIFS share mounted and set up for auto-mount on boot"
}

install_kickstart_nvim() {
    log "Setting up Kickstart Neovim..."
    
    # Make sure git is installed
    if ! command -v git &>/dev/null; then
        log "Git not found, installing..."
        dnf install -y git
    fi
    
    # Define Neovim config directory
    NVIM_CONFIG_DIR="$ACTUAL_HOME/.config/nvim"
    
    # Backup existing configuration if it exists
    if [ -d "$NVIM_CONFIG_DIR" ]; then
        BACKUP_DIR="$NVIM_CONFIG_DIR.backup.$(date +%Y%m%d%H%M%S)"
        mv "$NVIM_CONFIG_DIR" "$BACKUP_DIR"
    fi
    
    # Clean any existing Neovim data
    rm -rf $ACTUAL_HOME/.local/share/nvim $ACTUAL_HOME/.local/state/nvim $ACTUAL_HOME/.cache/nvim
    
    # Install kickstart.nvim
    mkdir -p "$NVIM_CONFIG_DIR"
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$NVIM_CONFIG_DIR"
    chown -R $ACTUAL_USER:$ACTUAL_USER "$NVIM_CONFIG_DIR"
    
    log_success "Kickstart Neovim configured successfully"
}

change_to_zsh() {
    log "Setting up Zsh..."
    
    # Check if zsh is installed, if not install it
    if ! command -v zsh &>/dev/null; then
        log "Zsh not found, installing..."
        dnf install -y zsh
    fi
    
    # Install Oh My Zsh
    su - $ACTUAL_USER -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    
    # Download .zshrc from GitHub
    log "Downloading custom .zshrc from GitHub..."
    curl -fsSL https://raw.githubusercontent.com/linuxmunchies/.zshrc/main/.zshrc -o "/tmp/.zshrc"
    
    # Back up existing .zshrc if it exists
    if [ -f "$ACTUAL_HOME/.zshrc" ]; then
        mv "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
        log "Backed up existing .zshrc file"
    fi
    
    # Move downloaded .zshrc to user's home directory
    mv "/tmp/.zshrc" "$ACTUAL_HOME/.zshrc"
    chown $ACTUAL_USER:$ACTUAL_USER "$ACTUAL_HOME/.zshrc"
    chmod 644 "$ACTUAL_HOME/.zshrc"
    
    # Get full path to zsh
    ZSH_PATH=$(which zsh)
    
    # Change default shell for user only if zsh path is valid
    if [ -n "$ZSH_PATH" ]; then
        chsh -s "$ZSH_PATH" $ACTUAL_USER
        log_success "Zsh configured as default shell with custom .zshrc"
    else
        log_error "Could not find zsh path. Shell not changed."
    fi
}

setup_kde_dark_mode() {
    log "Setting up KDE dark mode..."
    
    # Check if KDE is installed
    if ! rpm -q plasma-desktop &>/dev/null; then
        log_warning "KDE Plasma not detected, skipping dark mode setup"
        return
    fi
    
    # Set dark mode and theme for the user using lookandfeeltool
    if command -v lookandfeeltool &>/dev/null; then
        su - $ACTUAL_USER -c 'lookandfeeltool -a org.kde.breezedark.desktop'
        log_success "KDE dark mode configured"
    else
        log_warning "lookandfeeltool not found, skipping KDE dark mode setup"
    fi
}

cleanup() {
    log "Performing cleanup..."
    
    # Clean up package cache
    dnf clean packages
    
    # Remove unused Flatpak runtimes
    flatpak uninstall --unused -y
    
    log_success "Cleanup completed"
}

generate_summary() {
    log "Generating setup summary..."
    
    echo "======================================"
    echo "       Fedora Setup Complete!         "
    echo "======================================"
    echo "Hostname: $(hostname)"
    echo "Setup completed at: $(date)"
    echo "Log file: $LOG_FILE"
    echo "======================================"
    
    # Display system info if fastfetch is available
    if command -v fastfetch &> /dev/null; then
        fastfetch
    fi
}

# ----- Main Execution -----
main() {
    log "Starting Fedora setup script..."
    
    check_root
    check_fedora
    
    # Create log file
    touch "$LOG_FILE"
    chown $ACTUAL_USER:$ACTUAL_USER "$LOG_FILE"
    
    setup_repositories
    update_system
    setup_snapshots
    optimize_system
    install_system_tools
    setup_virtualization
    setup_multimedia
    install_gaming
    install_brave_browser
    install_flatpaks
    setup_cifs_mount
    mkdir_proton
    setup_gamedrive_mount
    setup_user_groups
    install_nerd_fonts
    install_system_fonts
    setup_system_optimizations
    install_kickstart_nvim
    change_to_zsh
    setup_kde_dark_mode
    cleanup
    generate_summary
    
    log "Fedora setup completed successfully!"
    echo "Please reboot your system to apply all changes."
}

# Run the main function
main

