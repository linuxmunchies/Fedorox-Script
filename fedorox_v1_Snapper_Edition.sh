#!/bin/bash
# Fedora Setup Script

# Define variables for the actual user (not root/sudo)
ACTUAL_USER=$(logname || echo $SUDO_USER || echo $USER)
ACTUAL_HOME=$(getent passwd $ACTUAL_USER | cut -d: -f6)

# Installation category selection (default: all enabled)
INSTALL_ESSENTIALS=true
INSTALL_BROWSERS=true
INSTALL_OFFICE=true
INSTALL_CODING=true
INSTALL_MEDIA=true
INSTALL_GAMING=true
INSTALL_REMOTE=true
INSTALL_FILESHARING=true
INSTALL_SYSTEMTOOLS=true
INSTALL_CUSTOMIZATION=true

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$ACTUAL_HOME/fedora_setup.log"
}

# Error handling function
install_package() {
    local package=$1
    log_message "Installing $package..."
    if dnf install -y $package; then
        log_message "$package installed successfully"
    else
        log_message "ERROR: Failed to install $package"
    fi
}

# Setup repositories function
setup_repos() {
    log_message "Setting up repositories..."
    
    # Install DNF plugins
    install_package "dnf-plugins-core"
    
    # Remove unwanted repositories
    log_message "Removing irrelevant repositories..."
    sudo rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:phracek:PyCharm.repo
    sudo rm -f /etc/yum.repos.d/google-chrome.repo
    sudo rm -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
    sudo rm -f /etc/yum.repos.d/rpmfusion-nonfree-steam.repo
    
    # Install RPM Fusion repositories
    log_message "Installing RPM Fusion repositories..."
    dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    
    # Setup Flatpak and Flathub
    log_message "Setting up Flatpak and Flathub..."
    dnf install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    sudo flatpak repair
    flatpak update
    
    log_message "Repositories setup completed successfully"
}

# System upgrade function
system_upgrade() {
    log_message "Performing system upgrade... This may take a while..."
    # Create system snapshot before major changes
    log_message "Creating system snapshot before major changes..."
    DATE=$(date +%Y-%m-%d-%H-%M-%S)

    dnf install -y snapper

    # Enable the timers and services
    sudo systemctl enable --now snapper-timeline.timer
    sudo systemctl enable --now snapper-cleanup.timer
    sudo snapper -c root create-config /
    sudo snapper -c home create-config /home
    sudo snapper -c root create -d "${DATE}_RootFirst" 
    sudo snapper -c home create -d "${DATE}_HomeFirst" 

    echo "Snapshots created: root-$DATE, home-$DATE"

    # Perform system upgrade
    dnf upgrade -y
    log_message "System upgrade completed successfully"
}

# System configuration function
configure_system() {
    log_message "Configuring system..."
    
    # Set hostname
    log_message "Setting hostname..."
    hostnamectl set-hostname Fedorox
    
    # Optimize DNF
    log_message "Optimizing DNF configuration..."
    # Backup the original dnf.conf
    cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
    
    # Add or update fastestmirror and max_parallel_downloads settings
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
    
    log_message "DNF configuration updated successfully"
    
    # Check for firmware updates
    log_message "Checking for firmware updates..."
    fwupdmgr refresh --force
    fwupdmgr get-updates
    fwupdmgr update -y
    
    log_message "System configuration completed successfully"
}

# Setup CIFS mount function
setup_cifs_mount() {
    log_message "Setting up CIFS mount..."
    
    # Set mount details
    SHARE="//192.168.0.2/media"
    SHARE2="//192.168.0.2/archives"
    MOUNT_POINT="/mnt/media"
    MOUNT_POINT2="/mnt/archives"
    CREDENTIALS_FILE="/etc/cifs-credentials"
    FSTAB_ENTRY="$SHARE $MOUNT_POINT cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=$(id -u),gid=$(id -g),nofail 0 0"
    FSTAB_ENTRY2="$SHARE2 $MOUNT_POINT2 cifs credentials=$CREDENTIALS_FILE,vers=3.0,uid=$(id -u),gid=$(id -g),nofail 0 0"
    
    sudo dnf install -y cifs-utils
    
    # Prompt for username and password securely
    log_message "Setting up CIFS credentials..."
    read -rp "Enter CIFS username: " CIFS_USER
    read -rsp "Enter CIFS password: " CIFS_PASS
    
    # Create credentials file securely
    if ! echo -e "username=$CIFS_USER\npassword=$CIFS_PASS" | sudo tee "$CREDENTIALS_FILE" >/dev/null; then
        log_message "ERROR: Failed to create credentials file"
        return 1
    fi
    sudo chmod 600 "$CREDENTIALS_FILE"
    
    # Create mount point if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        if ! sudo mkdir -p "$MOUNT_POINT"; then
            log_message "ERROR: Failed to create mount point"
            return 1
        fi
    fi
    if [ ! -d "$MOUNT_POINT2" ]; then
        if ! sudo mkdir -p "$MOUNT_POINT2"; then
            log_message "ERROR: Failed to create mount point"
            return 1
        fi
    fi   
    # Mount the share
    log_message "Mounting CIFS share..."
    if ! sudo mount -t cifs "$SHARE" "$MOUNT_POINT" -o "credentials=$CREDENTIALS_FILE,vers=3.0,uid=$(id -u),gid=$(id -g),nofail"; then
        log_message "ERROR: Failed to mount CIFS share"
        return 1
    fi
     # Mount the share
    log_message "Mounting CIFS share2..."
    if ! sudo mount -t cifs "$SHARE2" "$MOUNT_POINT2" -o "credentials=$CREDENTIALS_FILE,vers=3.0,uid=$(id -u),gid=$(id -g),nofail"; then
        log_message "ERROR: Failed to mount CIFS share"
        return 1
    fi
   
    # Ensure the fstab entry exists
    if ! grep -q "$SHARE" /etc/fstab; then
        log_message "Adding to /etc/fstab for persistence..."
        if ! echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab >/dev/null; then
            log_message "ERROR: Failed to update fstab"
            return 1
        fi
    fi
    # Ensure the fstab entry exists
    if ! grep -q "$SHARE2" /etc/fstab; then
        log_message "Adding second share to /etc/fstab for persistence..."
        if ! echo "$FSTAB_ENTRY2" | sudo tee -a /etc/fstab >/dev/null; then
            log_message "ERROR: Failed to update fstab2"
            return 1
        fi
    fi   
    log_message "CIFS share 1 and share 2 mounted successfully and set up for auto-mount on boot"
}

# Setup multimedia codecs function
setup_multimedia() {
    log_message "Setting up multimedia support..."
    
    # Install multimedia codecs
    log_message "Installing multimedia codecs..."
    dnf swap ffmpeg-free ffmpeg --allowerasing -y
    dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y
    dnf update @sound-and-video -y
    
    # Install Hardware Accelerated Codecs for Intel
    log_message "Installing Intel Hardware Accelerated Codecs..."
    dnf -y install intel-media-driver
    
    # Install Hardware Accelerated Codecs for AMD
    log_message "Installing AMD Hardware Accelerated Codecs..."
    dnf swap mesa-va-drivers mesa-va-drivers-freeworld -y
    dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld -y
    
    log_message "Multimedia setup completed successfully"
}

# Setup virtualization function
setup_virtualization() {
    log_message "Setting up virtualization..."
    
    # Install virtualization package group
    install_package "@virtualization"
    
    # Enable and start libvirtd service
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    # Add user to libvirt group
    sudo usermod -aG libvirt $ACTUAL_USER
    
    log_message "Virtualization setup completed successfully. Please log out and back in for the group changes to take effect."
}

# Install essential applications function
install_essentials() {
    if [ "$INSTALL_ESSENTIALS" != "true" ]; then
        log_message "Skipping essential applications installation as per configuration"
        return
    fi
    
    log_message "Installing essential applications..."
    
    # Install packages in a single command
    dnf install -y btop htop rsync inxi fzf ncdu tmux fastfetch git wget curl neovim bat make unzip gcc go tldr

    # Install rclone
    log_message "Installing rclone..."
    if ! (sudo -v && curl https://rclone.org/install.sh | sudo bash); then
        log_message "ERROR: Failed to install rclone"
    fi
    
    # Install Rust
    log_message "Installing rust..."
    if ! (sudo -v && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh); then
	    log_message "Error: Failed to install rust!"
    fi
    log_message "Essential applications installed successfully"
}

# Install browser applications function
install_browsers() {
    if [ "$INSTALL_BROWSERS" != "true" ]; then
        log_message "Skipping browser applications installation as per configuration"
        return
    fi
    
    log_message "Installing Internet & Communication applications..."
    
    # Install Brave browser
    log_message "Installing Brave..."
    dnf install -y dnf-plugins-core
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
    install_package "brave-browser"
    
    # Install Flatpak browsers and communication apps
    log_message "Installing browsers and communication apps from Flathub..."
    flatpak install -y flathub io.gitlab.librewolf-community app.zen_browser.zen im.riot.Riot org.telegram.desktop
    
    log_message "Browser applications installed successfully"
}

# Install office applications function
install_office() {
    if [ "$INSTALL_OFFICE" != "true" ]; then
        log_message "Skipping office applications installation as per configuration"
        return
    fi
    
    log_message "Installing Office & Productivity applications..."
    
    # Install Office apps from Flathub
    flatpak install -y flathub org.onlyoffice.desktopeditors md.obsidian.Obsidian
    
    log_message "Office applications installed successfully"
}

# Install coding applications function
install_coding() {
    if [ "$INSTALL_CODING" != "true" ]; then
        log_message "Skipping coding applications installation as per configuration"
        return
    fi
    
    log_message "Installing Coding & DevOps applications..."
    
    # Install Docker
    log_message "Installing Docker..."
    dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine --noautoremove
    dnf -y install dnf-plugins-core
    dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start Docker services
    if ! systemctl enable --now docker; then
        log_message "ERROR: Failed to enable Docker service"
    fi
    if ! systemctl enable --now containerd; then
        log_message "ERROR: Failed to enable containerd service"
    fi
    
    # Add user to Docker group
    groupadd docker 2>/dev/null || true
    usermod -aG docker $ACTUAL_USER
    rm -rf $ACTUAL_HOME/.docker
    
    log_message "Docker installed successfully. Please log out and back in for the group changes to take effect."
}

# Install media applications function
install_media() {
    if [ "$INSTALL_MEDIA" != "true" ]; then
        log_message "Skipping media applications installation as per configuration"
        return
    fi
    
    log_message "Installing Media & Graphics applications..."
    
    # Install GIMP using dnf
    install_package "gimp"
    
    # Install media apps from Flathub
    flatpak install -y flathub org.videolan.VLC com.spotify.Client org.blender.Blender com.obsproject.Studio org.kde.kdenlive
    
    log_message "Media applications installed successfully"
}

# Install gaming applications function
install_gaming() {
    if [ "$INSTALL_GAMING" != "true" ]; then
        log_message "Skipping gaming applications installation as per configuration"
        return
    fi
    
    log_message "Installing Gaming & Emulation applications..."
    
    # Install Steam
    install_package "steam"
    

    # Install mangohud and goverlay
    install_package "mangohud goverlay"
    
    # Install gaming apps from Flathub
    flatpak install -y flathub net.lutris.Lutris com.heroicgameslauncher.hgl
    
    log_message "Gaming applications installed successfully"
}

# Install remote networking applications function
install_remote() {
    if [ "$INSTALL_REMOTE" != "true" ]; then
        log_message "Skipping remote networking applications installation as per configuration"
        return
    fi
    
    log_message "Installing Remote Networking applications..."
    
    # Install remote apps from Flathub
    flatpak install -y flathub org.remmina.Remmina com.rustdesk.RustDesk
    
    log_message "Remote networking applications installed successfully"
}

# Install file sharing applications function
install_filesharing() {
    if [ "$INSTALL_FILESHARING" != "true" ]; then
        log_message "Skipping file sharing applications installation as per configuration"
        return
    fi
    
    log_message "Installing File Sharing & Download applications..."
    
    # Install file sharing apps from Flathub
    flatpak install -y flathub org.qbittorrent.qBittorrent com.github.unrud.VideoDownloader
    
    log_message "File sharing applications installed successfully"
}

# Install system tools function
install_systemtools() {
    if [ "$INSTALL_SYSTEMTOOLS" != "true" ]; then
        log_message "Skipping system tools installation as per configuration"
        return
    fi
    
    log_message "Installing System Tools applications..."
    
    # Install system tools from Flathub
    flatpak install -y flathub io.missioncenter.MissionCenter com.github.tchx84.Flatseal com.mattjakeman.ExtensionManager com.usebottles.bottles net.davidotek.pupgui2 it.mijorus.gearlever org.gnome.DejaDup org.gnome.World.PikaBackup net.nokyan.Resources
    
    log_message "System tools installed successfully"
}

# Install customization function
install_customization() {
    if [ "$INSTALL_CUSTOMIZATION" != "true" ]; then
        log_message "Skipping customization installation as per configuration"
        return
    fi
    
    log_message "Installing customization items..."
    
    # Install Microsoft fonts
    log_message "Installing Microsoft Fonts (core)..."
    dnf install -y curl cabextract xorg-x11-font-utils fontconfig
    rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
    
    # Install Google fonts with user confirmation
    log_message "Installing Google Fonts..."
    if confirm_action "This will download a large file (800+ MB). Continue?"; then
        wget -O /tmp/google-fonts.zip https://github.com/google/fonts/archive/main.zip
        mkdir -p $ACTUAL_HOME/.local/share/fonts/google
        unzip /tmp/google-fonts.zip -d $ACTUAL_HOME/.local/share/fonts/google
        rm -f /tmp/google-fonts.zip
        fc-cache -fv
        log_message "Google Fonts installed successfully"
    else
        log_message "Skipping Google fonts installation"
    fi
    
    log_message "Customization completed successfully"
}

# Cleanup function
cleanup() {
    log_message "Performing cleanup..."
    
    # Clean up package cache
    dnf clean packages
    
    # Remove unused Flatpak runtimes
    flatpak uninstall --unused -y
    
    log_message "Cleanup completed successfully"
}

# Generate summary function
generate_summary() {
    log_message "Generating setup summary..."
    
    echo "=== Setup Summary ==="
    echo "Hostname: $(hostname)"
    echo "Setup completed at: $(date)"
    echo "Created with ❤️ for Open Source"
    
    # Display system info
    fastfetch
}

# Main script execution
log_message "Starting Fedora setup script..."

# Execute functions in sequence
system_upgrade
setup_repos
configure_system
setup_cifs_mount
setup_multimedia
setup_virtualization
install_essentials
install_browsers
install_office
install_coding
install_media
install_gaming
install_remote
install_filesharing
install_systemtools
install_customization
cleanup
generate_summary

log_message "Fedora setup script completed successfully"

