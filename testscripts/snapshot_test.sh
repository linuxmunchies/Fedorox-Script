# Function to check if a subvolume exists
check_subvol() {
    sudo btrfs subvolume list / | grep -q -E " path ($1|@$1|@var_$1|var_$1)$"
}

snapshot_function() {
    # Check critical directories
    log_is_subvol=$(check_subvol "log" && echo "yes" || echo "no")
    cache_is_subvol=$(check_subvol "cache" && echo "yes" || echo "no")

    # Warn if not subvolumes
    if [[ "$log_is_subvol" == "no" || "$cache_is_subvol" == "no" ]]; then
        echo "WARNING: These directories are not BTRFS subvolumes:"
        [[ "$log_is_subvol" == "no" ]] && echo "- /var/log"
        [[ "$cache_is_subvol" == "no" ]] && echo "- /var/cache"
        echo "This will make snapshots larger and may cause issues during rollbacks."
        
        read -p "Continue anyway? (yes/no): " answer
        if [[ "$answer" != "yes" ]]; then
            echo "Script terminated."
            exit 1
        fi
    fi

    # Create snapshots
    echo "Creating system snapshots..."
    DATE=$(date +%Y-%m-%d-%H-%M-%S)

    # Install packages and set up snapper
    sudo dnf install -y snapper libdnf5-plugin-actions
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    sudo snapper -c root create-config /
    sudo snapper -c home create-config /home
    sudo snapper -c root create -d "${DATE}_RootFirst" 
    sudo snapper -c home create -d "${DATE}_HomeFirst" 

    echo "Snapshots created: root-$DATE, home-$DATE"
}

snapshot_function
