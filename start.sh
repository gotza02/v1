#!/bin/bash

# Advanced VPS Performance Optimization Script for Ubuntu
# Version 2.0 - Enhanced Edition

# Configuration
LOG_FILE="/var/log/vps_optimization.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
BACKUP_DIR="/root/vps_optimization_backups"
CONFIG_BACKUP="$BACKUP_DIR/sysctl_$(date +%Y%m%d_%H%M%S).conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to install required tools
install_tools() {
    log_message "Installing optimization tools..."
    apt-get update -y || handle_error "Failed to update package lists"
    apt-get install -y sysstat htop net-tools dnsutils curl unzip linux-tools-common cpufrequtils || handle_error "Failed to install tools"
}

# Function to optimize RAM
optimize_ram() {
    log_message "${BLUE}Optimizing RAM...${NC}"
    
    # Advanced memory management
    sync
    echo 3 > /proc/sys/vm/drop_caches
    sysctl -w vm.swappiness=10 || handle_error "Failed to set swappiness"
    sysctl -w vm.vfs_cache_pressure=50 || handle_error "Failed to set vfs_cache_pressure"
    sysctl -w vm.dirty_ratio=10 || handle_error "Failed to set dirty_ratio"
    
    # Persist settings
    cat << EOF >> /etc/sysctl.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
EOF
    
    # Memory stats with more detail
    TOTAL_RAM=$(free -h | grep "Mem:" | awk '{print $2}')
    USED_RAM=$(free -h | grep "Mem:" | awk '{print $3}')
    FREE_RAM=$(free -h | grep "Mem:" | awk '{print $4}')
    CACHE=$(free -h | grep "Mem:" | awk '{print $6}')
    
    log_message "RAM Status - Total: $TOTAL_RAM | Used: $USED_RAM | Free: $FREE_RAM | Cache: $CACHE"
}

# Function to optimize CPU
optimize_cpu() {
    log_message "${BLUE}Optimizing CPU...${NC}"
    
    # Check available governors and set to best option
    if command -v cpufreq-set > /dev/null; then
        AVAILABLE_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
        if echo "$AVAILABLE_GOV" | grep -q "performance"; then
            cpufreq-set -r -g performance || log_message "${YELLOW}Warning: Failed to set performance governor${NC}"
            log_message "CPU governor set to performance"
        else
            cpufreq-set -r -g ondemand || log_message "${YELLOW}Warning: Using ondemand governor as fallback${NC}"
            log_message "CPU governor set to ondemand"
        fi
    fi
    
    # Adjust I/O scheduler
    for disk in /sys/block/sd*; do
        if [ -d "$disk" ]; then
            echo "noop" > "$disk/queue/scheduler" 2>/dev/null && log_message "Set I/O scheduler to noop for $(basename $disk)"
        fi
    done
    
    # Detailed CPU stats
    CPU_USAGE=$(mpstat 1 1 | awk '/Average:/ {print 100 - $NF"%"}')
    CPU_TEMP=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | awk '{print $1/1000 "°C"}')
    log_message "CPU Usage: $CPU_USAGE | Temperature: ${CPU_TEMP:-Not available}"
}

# Function to optimize network
optimize_network() {
    log_message "${BLUE}Optimizing Network...${NC}"
    
    # Backup sysctl.conf
    cp /etc/sysctl.conf "$CONFIG_BACKUP" || handle_error "Failed to backup sysctl.conf"
    
    # Advanced network optimizations
    cat << EOF >> /etc/sysctl.conf
# Advanced Network Optimizations
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
net.core.netdev_max_backlog=5000
net.core.somaxconn=1024
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_low_latency=1
net.ipv4.tcp_slow_start_after_idle=0
net.core.default_qdisc=fq
EOF
    
    # Apply and verify
    sysctl -p || handle_error "Failed to apply sysctl settings"
    
    # Enable BBR and verify
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
    sysctl net.ipv4.tcp_available_congestion_control | grep -q "bbr" && log_message "BBR successfully enabled"
    
    # Optimize DNS
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    
    # Network speed test
    if command -v curl > /dev/null; then
        SPEED=$(curl -s -o /dev/null -w "%{speed_download}" http://speedtest.ookla.com/speedtest/random4000x4000.jpg)
        SPEED_MBPS=$(echo "scale=2; $SPEED/125000" | bc)
        log_message "Download Speed: $SPEED_MBPS Mbps"
    fi
}

# Function to monitor and alert
monitor_system() {
    log_message "${BLUE}System Monitoring...${NC}"
    
    # Disk usage with threshold alert
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | cut -d'%' -f1)
    if [ "$DISK_USAGE" -gt 85 ]; then
        log_message "${RED}Warning: Disk usage at ${DISK_USAGE}% - Consider cleanup${NC}"
    else
        log_message "Disk Usage: ${DISK_USAGE}%"
    fi
    
    # Top processes
    HIGH_CPU=$(ps aux --sort=-%cpu | head -n 5)
    log_message "Top 5 CPU Processes:\n$HIGH_CPU"
    
    # Network stats
    ACTIVE_CONN=$(netstat -tunap 2>/dev/null | wc -l)
    log_message "Active Connections: $ACTIVE_CONN"
    
    # Check for OOM kills
    if dmesg | grep -i "out of memory" > /dev/null; then
        log_message "${YELLOW}Warning: Recent OOM kills detected${NC}"
    fi
}

# Function to clean up system
system_cleanup() {
    log_message "${BLUE}Performing system cleanup...${NC}"
    
    # Clean package cache
    apt-get autoremove -y && apt-get autoclean -y || log_message "${YELLOW}Warning: Cleanup partially failed${NC}"
    
    # Remove old logs
    find /var/log -type f -name "*.log" -mtime +7 -delete
    log_message "Removed logs older than 7 days"
}

# Main execution
clear
echo -e "${GREEN}=== Advanced VPS Optimization Script v2.0 ===${NC}"
log_message "Starting optimization process..."

# Execute all optimizations with error handling
install_tools || handle_error "Tool installation failed"
optimize_ram || handle_error "RAM optimization failed"
optimize_cpu || handle_error "CPU optimization failed"
optimize_network || handle_error "Network optimization failed"
monitor_system || handle_error "Monitoring failed"
system_cleanup || handle_error "Cleanup failed"

# Schedule maintenance (every 4 hours)
CRON_JOB="0 */4 * * * /bin/bash $(realpath $0)"
(crontab -l 2>/dev/null | grep -v "$(realpath $0)"; echo "$CRON_JOB") | crontab - || log_message "${YELLOW}Warning: Failed to update crontab${NC}"

# Final status
echo -e "\n${YELLOW}Final System Status:${NC}"
uptime
free -h | grep "Mem:"
log_message "${GREEN}Optimization completed successfully!${NC}"
