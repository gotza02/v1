#!/bin/bash

# Advanced VPS Performance Optimization Script
# Customized with interactive mode selection

# Configuration
LOG_FILE="/var/log/vps_optimization.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
BACKUP_DIR="/root/vps_optimization_backups"
CONFIG_BACKUP="$BACKUP_DIR/sysctl_$(date +%Y%m%d_%H%M%S).conf"
NETWORK_BACKUP="$BACKUP_DIR/network_$(date +%Y%m%d_%H%M%S).conf"
RESOLV_BACKUP="$BACKUP_DIR/resolv_$(date +%Y%m%d_%H%M%S).conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script requires root privileges. Please run with sudo.${NC}"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Function to handle errors
handle_error() {
    log_message "${RED}Error: $1${NC}"
    exit 1
}

# Function to backup configurations
backup_configs() {
    log_message "Backing up configurations..."
    cp /etc/sysctl.conf "$CONFIG_BACKUP" || handle_error "Failed to backup sysctl.conf"
    cp /etc/network/interfaces "$NETWORK_BACKUP" || handle_error "Failed to backup network interfaces"
    cp /etc/resolv.conf "$RESOLV_BACKUP" || handle_error "Failed to backup resolv.conf"
}

# Function to restore configurations
restore_configs() {
    log_message "Restoring configurations..."
    cp "$CONFIG_BACKUP" /etc/sysctl.conf || handle_error "Failed to restore sysctl.conf"
    cp "$  "$NETWORK_BACKUP" /etc/network/interfaces || handle_error "Failed to restore network interfaces"
    cp "$RESOLV_BACKUP" /etc/resolv.conf || handle_error "Failed to restore resolv.conf"
    sysctl -p || handle_error "Failed to apply restored sysctl settings"
}

# Function to manage swap
manage_swap() {
    log_message "Managing Swap..."
    if [ ! -f /swapfile ]; then
        log_message "Creating 4GB swap file..."
        fallocate -l 4G /swapfile || handle_error "Failed to create swap file"
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    else
        log_message "Swap file already exists. Skipping."
    fi
}

# Function to optimize CPU
optimize_cpu() {
    log_message "Optimizing CPU..."
    # Set governor to performance
    if command -v cpufreq-set > /dev/null; then
        cpufreq-set -r -g performance || log_message "${YELLOW}Warning: Failed to set performance governor${NC}"
    fi
    # Install and enable irqbalance
    apt-get install -y irqbalance || handle_error "Failed to install irqbalance"
    systemctl enable irqbalance
    systemctl start irqbalance
    # Log CPU cores
    CPU_CORES=$(nproc)
    log_message "CPU Cores: $CPU_CORES"
}

# Function to optimize network
optimize_network() {
    log_message "Optimizing Network..."
    # Add Quad9 DNS
    echo "nameserver 9.9.9.9" >> /etc/resolv.conf
    # Set MTU to 1400 for VPN
    IFACE=$(ip route | grep default | awk '{print $5}')
    ip link set dev $IFACE mtu 1400 || log_message "${YELLOW}Warning: Failed to set MTU${NC}"
    # Test network speed
    if command -v curl > /dev/null; then
        SPEED=$(curl -s -o /dev/null -w "%{speed_download}" http://speedtest.ookla.com/speedtest/random4000x4000.jpg)
        SPEED_MBPS=$(echo "scale=2; $SPEED/125000" | bc)
        log_message "Download Speed: $SPEED_MBPS Mbps"
    fi
}

# Function to set cron job
set_cron_job() {
    CRON_JOB="0 3 * * * /bin/bash $(realpath $0) optimize"
    (crontab -l 2>/dev/null | grep -v "$(realpath $0)"; echo "$CRON_JOB") | crontab - || log_message "${YELLOW}Warning: Failed to set cron job${NC}"
}

# Main execution with interactive menu
clear
echo -e "${GREEN}=== VPS Optimization Script ===${NC}"
echo "Select an option:"
echo "1) Optimize VPS"
echo "2) Restore from Backup"
read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        log_message "Starting optimization..."
        backup_configs
        manage_swap
        optimize_cpu
        optimize_network
        set_cron_job
        log_message "${GREEN}Optimization completed!${NC}"
        ;;
    2)
        log_message "Starting restore..."
        restore_configs
        log_message "${GREEN}Restore completed!${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice. Please run again and select 1 or 2.${NC}"
        exit 1
        ;;
esac
