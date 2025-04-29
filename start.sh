#!/bin/bash

# ==============================================================================
# สคริปต์ตั้งค่า Ubuntu 20.04 VPS เพื่อประสิทธิภาพสูงสุด (เน้น Network & RAM)
# คำเตือน: รันด้วยสิทธิ์ root (sudo) และทดสอบระบบหลังใช้งาน!
# ==============================================================================

# ตรวจสอบว่ารันด้วย root หรือไม่
if [ "$(id -u)" -ne 0 ]; then
   echo "กรุณารันสคริปต์นี้ด้วยสิทธิ์ root (ใช้ sudo)"
   exit 1
fi

echo ">>> เริ่มต้นการปรับแต่งประสิทธิภาพ Ubuntu 20.04..."
CURRENT_DATE=$(date "+%Y-%m-%d %H:%M:%S")
echo ">>> วันที่และเวลาปัจจุบัน: $CURRENT_DATE"

# --- 1. อัปเดตระบบและแพ็คเกจพื้นฐาน ---
echo
echo ">>> [1/6] กำลังอัปเดตระบบและแพ็คเกจ..."
apt update > /dev/null 2>&1
apt upgrade -y
apt autoremove -y
apt clean
echo ">>> ระบบอัปเดตเสร็จสิ้น"

# --- 2. ปรับแต่งค่า Kernel (Network Performance - TCP BBR & Buffers) ---
# ใช้ TCP BBR เป็น Congestion Control Algorithm ซึ่งมักให้ประสิทธิภาพดีกว่าบนลิงก์ที่มี Latency หรือ Packet Loss [1, 2]
# เพิ่มขนาด Buffer เพื่อรองรับการเชื่อมต่อความเร็วสูง [1, 2]
echo
echo ">>> [2/6] กำลังปรับแต่งค่า Kernel สำหรับ Network (TCP BBR & Buffers)..."
cat << EOF > /etc/sysctl.d/99-custom-network-tune.conf
# เปิดใช้งาน TCP BBR Congestion Control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# เพิ่มขนาด TCP Buffer ให้ใหญ่ขึ้น
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# ปรับแต่ง TCP Stack อื่นๆ เพื่อประสิทธิภาพและความทนทาน
net.ipv4.tcp_max_syn_backlog=8192       # เพิ่มขนาดคิว SYN backlog [2]
net.core.somaxconn=8192                 # เพิ่มขนาด backlog สูงสุดของ listening sockets [2]
net.core.netdev_max_backlog=16384       # เพิ่มขนาด backlog ของ network device queue [1]

net.ipv4.tcp_fin_timeout=20             # ลดเวลาสถานะ FIN-WAIT-2
net.ipv4.tcp_tw_reuse=1                 # อนุญาตให้ใช้ซ็อกเก็ต TIME-WAIT ซ้ำ (ระวังหากอยู่หลัง NAT ที่ซับซ้อน) [2]
# net.ipv4.tcp_tw_recycle=0             # ไม่แนะนำให้เปิดใช้งาน (อาจทำให้เกิดปัญหาหลัง NAT) [2]
net.ipv4.tcp_keepalive_time=600         # ลดเวลา Keepalive เพื่อตรวจจับการเชื่อมต่อที่ตายเร็วขึ้น
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=60

net.ipv4.tcp_syncookies=1               # เปิดใช้งาน SYN Cookies เพื่อป้องกัน SYN Flood Attack [2]
net.ipv4.tcp_rfc1337=1                   # ป้องกัน Time-Wait Assassination hazards

# การตั้งค่าเพิ่มเติม (อาจต้องทดสอบความเข้ากันได้กับแอปพลิเคชัน)
# net.ipv4.tcp_fastopen=3               # เปิดใช้งาน TCP Fast Open (Client & Server)
# net.ipv4.tcp_mtu_probing=1            # เปิดใช้งาน Path MTU Discovery probing

# เพิ่มประสิทธิภาพการส่งต่อ Packet (หากใช้เป็น Router/Gateway)
# net.ipv4.ip_forward=1
# net.ipv6.conf.all.forwarding=1

EOF
echo ">>> สร้างไฟล์ /etc/sysctl.d/99-custom-network-tune.conf เสร็จสิ้น"

# --- 3. ปรับแต่งค่า Kernel (Memory Management - Swappiness & Cache Pressure) ---
# ลดค่า Swappiness เพื่อให้ระบบใช้ RAM จริงมากขึ้น ก่อนจะเริ่มใช้ Swap [3]
# ลดค่า VFS Cache Pressure เพื่อให้ Kernel เก็บ Cache ของ Filesystem ไว้นานขึ้น [3]
echo
echo ">>> [3/6] กำลังปรับแต่งค่า Kernel สำหรับ Memory Management..."
cat << EOF > /etc/sysctl.d/99-custom-memory-tune.conf
# ลดการใช้งาน Swap (แนะนำ 10 สำหรับ Server ทั่วไป, อาจลดเหลือ 1 หาก RAM เยอะมากและไม่ต้องการ Swap เลย)
vm.swappiness=10

# ลดแรงกดดันในการเคลียร์ VFS cache (ช่วยรักษา cache ของ inode/dentry)
vm.vfs_cache_pressure=50

# ปกป้องหน่วยความจำขั้นต่ำ (เป็น Bytes) ไม่ให้ Kernel ใช้จนหมดเกลี้ยง
# vm.min_free_kbytes=65536 # (ยกเลิกการคอมเมนต์หากจำเป็นจริงๆ และปรับค่าตามขนาด RAM)

EOF
echo ">>> สร้างไฟล์ /etc/sysctl.d/99-custom-memory-tune.conf เสร็จสิ้น"

# --- 4. ปิดการใช้งาน Transparent Huge Pages (THP) ---
# THP มักทำให้เกิด Latency Spike กับบางแอปพลิเคชัน (เช่น Databases) การปิดใช้งานมักจะให้ประสิทธิภาพที่เสถียรกว่า [4]
echo
echo ">>> [4/6] กำลังปิดการใช้งาน Transparent Huge Pages (THP) อย่างถาวร..."
if ! grep -q "transparent_hugepage=never" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 transparent_hugepage=never"/' /etc/default/grub
    update-grub
    echo ">>> เพิ่ม transparent_hugepage=never ใน GRUB และทำการ update-grub (ต้องรีบูตเพื่อให้มีผล)"
else
    echo ">>> Transparent Huge Pages ถูกปิดใช้งานใน GRUB แล้ว"
fi

# สร้าง Service เพื่อให้แน่ใจว่า THP ถูกปิดตั้งแต่เริ่ม Boot (เผื่อกรณี GRUB ไม่ทำงาน หรือต้องการความแน่นอน)
cat << EOF > /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable --now disable-thp.service > /dev/null 2>&1
echo ">>> สร้างและเปิดใช้งาน systemd service 'disable-thp.service' เสร็จสิ้น"

# --- 5. เพิ่มขีดจำกัด File Descriptors ---
# เพิ่มจำนวนไฟล์สูงสุดที่ User หรือ Process สามารถเปิดได้พร้อมกัน สำคัญมากสำหรับ Web Server หรือ Service ที่มีการเชื่อมต่อสูง [5]
echo
echo ">>> [5/6] กำลังเพิ่มขีดจำกัด File Descriptors..."
LIMITS_CONF="/etc/security/limits.conf"
PAM_COMMON_SESSION="/etc/pam.d/common-session"
PAM_COMMON_SESSION_NONINTERACTIVE="/etc/pam.d/common-session-noninteractive"

# เพิ่มค่าใน limits.conf หากยังไม่มี
grep -q "* soft nofile 65536" "$LIMITS_CONF" || echo "* soft nofile 65536" >> "$LIMITS_CONF"
grep -q "* hard nofile 131072" "$LIMITS_CONF" || echo "* hard nofile 131072" >> "$LIMITS_CONF"
grep -q "root soft nofile 65536" "$LIMITS_CONF" || echo "root soft nofile 65536" >> "$LIMITS_CONF"
grep -q "root hard nofile 131072" "$LIMITS_CONF" || echo "root hard nofile 131072" >> "$LIMITS_CONF"

# ตรวจสอบและเพิ่ม pam_limits.so ใน PAM configuration หากยังไม่มี
PAM_LIMITS_LINE="session required pam_limits.so"
grep -q "$PAM_LIMITS_LINE" "$PAM_COMMON_SESSION" || echo "$PAM_LIMITS_LINE" >> "$PAM_COMMON_SESSION"
grep -q "$PAM_LIMITS_LINE" "$PAM_COMMON_SESSION_NONINTERACTIVE" || echo "$PAM_LIMITS_LINE" >> "$PAM_COMMON_SESSION_NONINTERACTIVE"

echo ">>> เพิ่มการตั้งค่า File Descriptors ใน $LIMITS_CONF และตรวจสอบ PAM configuration"
echo ">>> (การเปลี่ยนแปลงนี้จะมีผลกับการ Login Session ใหม่ หรือหลังจากรีบูต)"

# --- 6. ใช้การตั้งค่า Kernel ทันที ---
echo
echo ">>> [6/6] กำลังใช้การตั้งค่า Kernel (sysctl)..."
sysctl -p /etc/sysctl.d/99-custom-network-tune.conf > /dev/null 2>&1
sysctl -p /etc/sysctl.d/99-custom-memory-tune.conf > /dev/null 2>&1
echo ">>> ใช้การตั้งค่า sysctl เสร็จสิ้น"

# --- คำแนะนำเพิ่มเติม ---
echo
echo "=============================================================================="
echo ">>> การปรับแต่งเบื้องต้นเสร็จสมบูรณ์!"
echo
echo "คำแนะนำเพิ่มเติมเพื่อประสิทธิภาพสูงสุด:"
echo "  1.  **รีบูตเซิร์ฟเวอร์:** เพื่อให้การตั้งค่าทั้งหมด (โดยเฉพาะ GRUB และ limits.conf) มีผลสมบูรณ์"
echo "      # sudo reboot"
echo "  2.  **ตรวจสอบ I/O Scheduler:** สำหรับ SSD/NVMe ใน VPS แนะนำให้ใช้ 'none' หรือ 'mq-deadline'."
echo "      ตรวจสอบตัวปัจจุบัน: # cat /sys/block/sdX/queue/scheduler (เปลี่ยน sdX เป็นชื่อดิสก์ของคุณ)"
echo "      ตั้งค่าถาวรโดยแก้ /etc/default/grub เพิ่ม 'elevator=none' (หรือ mq-deadline) ใน GRUB_CMDLINE_LINUX แล้วรัน 'sudo update-grub' และรีบูต"
echo "  3.  **ติดตั้งและตั้งค่า Firewall (ufw):** เพื่อความปลอดภัย"
echo "      # sudo apt install ufw"
echo "      # sudo ufw default deny incoming"
echo "      # sudo ufw default allow outgoing"
echo "      # sudo ufw allow ssh"
echo "      # sudo ufw allow http"
echo "      # sudo ufw allow https"
echo "      # sudo ufw enable"
echo "  4.  **ปิด Services ที่ไม่จำเป็น:** ตรวจสอบ service ที่รันอยู่ด้วย 'systemctl list-units --type=service --state=running' และ disable อันที่ไม่ต้องการ"
echo "      # sudo systemctl disable <ชื่อ-service>"
echo "      # sudo systemctl stop <ชื่อ-service>"
echo "  5.  **ติดตั้ง Nginx/Web Server อื่นๆ และ PHP/Database (ถ้าต้องการ):** ปรับแต่ง Configuration ของ Service เหล่านั้นเพิ่มเติม (เช่น worker_processes, worker_connections ใน Nginx; memory limits ใน PHP-FPM; buffer pool ใน MySQL/MariaDB)"
echo "  6.  **ตั้งค่า VPN (ถ้าต้องการ):** เลือกใช้ Protocol ที่มีประสิทธิภาพ เช่น WireGuard และปรับแต่งค่าเฉพาะของ VPN Server เพิ่มเติม"
echo "  7.  **Monitoring:** ติดตั้งเครื่องมือ Monitoring (เช่น htop, netdata, Prometheus+Grafana) เพื่อติดตามผลและหาจุดคอขวดเพิ่มเติม"
echo
echo "!!! โปรดจำไว้ว่าต้องทดสอบระบบอย่างละเอียดหลังการเปลี่ยนแปลง !!!"
echo "=============================================================================="

exit 0
