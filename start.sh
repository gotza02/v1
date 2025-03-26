#!/bin/bash

# รันด้วยสิทธิ์ root
if [ "$EUID" -ne 0 ]; then
  echo "กรุณารันสคริปต์นี้ด้วยสิทธิ์ root (sudo)"
  exit 1
fi

# 1. อัปเดตระบบให้ทันสมัย
echo "กำลังอัปเดตระบบ..."
apt update && apt upgrade -y

# 2. ตั้งค่า Swap File ขนาด 2GB เพื่อป้องกัน RAM เต็ม
echo "ตรวจสอบและตั้งค่า Swap..."
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap File ขนาด 2GB ถูกสร้างและเปิดใช้งานแล้ว"
else
    echo "Swap File มีอยู่แล้ว ข้ามขั้นตอนนี้"
fi

# 3. ปรับแต่ง RAM และ Kernel Parameters
echo "ปรับแต่งการจัดการ RAM และ Kernel..."
cat <<EOF > /etc/sysctl.d/99-optimize.conf
# ลดการใช้ Swap เน้น RAM
vm.swappiness=10
# เพิ่มประสิทธิภาพ I/O
vm.dirty_ratio=10
vm.dirty_background_ratio=5
# ปรับแต่ง TCP และ Network
net.core.somaxconn=1024
net.ipv4.tcp_max_syn_backlog=2048
net.core.netdev_max_backlog=2000
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
# ปรับแต่ง CPU
kernel.sched_autogroup_enabled=1
EOF
sysctl -p /etc/sysctl.d/99-optimize.conf
echo "ตั้งค่า sysctl เสร็จสิ้น"

# 4. เปลี่ยน I/O Scheduler เป็น deadline เพื่อเพิ่มประสิทธิภาพดิสก์
echo "ปรับแต่ง I/O Scheduler..."
for disk in /sys/block/sd*/queue/scheduler; do
    if [ -f "$disk" ]; then
        echo "deadline" > "$disk"
        echo "ตั้งค่า I/O Scheduler เป็น deadline สำหรับ $disk"
    fi
done

# 5. เปิดใช้งาน TCP BBR (ถ้ายังไม่เปิด)
echo "เปิดใช้งาน TCP BBR..."
if ! sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi
sysctl -w net.ipv4.tcp_congestion_control=bbr
echo "TCP BBR ถูกเปิดใช้งาน"

# 6. ลบ Snap Packages ที่ไม่จำเป็น (ถ้าไม่ใช้ LXD)
echo "ตรวจสอบและลบ Snap Packages ที่ไม่จำเป็น..."
if snap list lxd > /dev/null 2>&1; then
    read -p "คุณต้องการลบ LXD และ Snap Packages อื่นๆ หรือไม่? (y/N): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        snap remove lxd
        snap remove core20
        snap remove snapd
        apt purge snapd -y
        echo "Snap Packages ถูกลบเรียบร้อย"
    else
        echo "ข้ามการลบ Snap Packages"
    fi
else
    echo "ไม่พบ LXD Snap Package ข้ามขั้นตอนนี้"
fi

# 7. ล้างแคชและรีบูตระบบ
echo "ล้างแคชและรีบูตระบบ..."
sync
echo 3 > /proc/sys/vm/drop_caches
echo "ระบบจะรีบูตใน 5 วินาที..."
sleep 5
reboot
