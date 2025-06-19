#!/bin/bash
# ============================================================================
# SCRIPT DE FORTIFICACIÓN DEL SISTEMA - PROTECCIÓN DEL HOST
# ============================================================================
# Protege el sistema operativo mientras permite desplegar web vulnerable
# Objetivo: Crear entorno seguro para el host, usuario aislado para la web
# ============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "██╗  ██╗ ██████╗ ███████╗████████╗    ███████╗ ██████╗ ██████╗ ████████╗██╗███████╗██╗   ██╗"
    echo "██║  ██║██╔═══██╗██╔════╝╚══██╔══╝    ██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝"
    echo "███████║██║   ██║███████╗   ██║       █████╗  ██║   ██║██████╔╝   ██║   ██║█████╗   ╚████╔╝ "
    echo "██╔══██║██║   ██║╚════██║   ██║       ██╔══╝  ██║   ██║██╔══██╗   ██║   ██║██╔══╝    ╚██╔╝  "
    echo "██║  ██║╚██████╔╝███████║   ██║       ██║     ╚██████╔╝██║  ██║   ██║   ██║██║        ██║   "
    echo "╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝       ╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝        ╚═╝   "
    echo -e "${NC}"
    echo -e "${YELLOW}SISTEMA DE FORTIFICACIÓN PARA ENTORNO DE PRUEBAS WAF${NC}"
    echo -e "${GREEN}Protege el host mientras permite vulnerabilidades de aplicación${NC}"
    echo ""
}

log_step() {
    echo -e "${GREEN}[PASO $1/12]${NC} $2"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner

# Verificar ejecución como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root"
   exit 1
fi

log_step "1" "Actualizando sistema y instalando dependencias de seguridad..."

# Actualizar sistema
apt update
apt upgrade -y

# Instalar herramientas de seguridad esenciales
apt install -y \
    fail2ban \
    ufw \
    auditd \
    rkhunter \
    chkrootkit \
    logwatch \
    psad \
    apparmor \
    apparmor-utils \
    aide \
    acct

log_info "Sistema actualizado y herramientas de seguridad instaladas"

log_step "2" "Creando usuario aislado para servicios web vulnerables..."

# Crear grupo específico para servicios vulnerables
if ! getent group vulnweb >/dev/null; then
    groupadd -r vulnweb
    log_info "Grupo 'vulnweb' creado"
fi

# Crear usuario dedicado sin privilegios especiales
if ! id "vulnweb" &>/dev/null; then
    useradd -r -g vulnweb -s /bin/false -d /var/www/vulnweb -c "Vulnerable Web Service User" vulnweb
    log_info "Usuario 'vulnweb' creado sin shell ni privilegios"
else
    # Asegurar configuración correcta si ya existe
    usermod -g vulnweb -s /bin/false -d /var/www/vulnweb vulnweb
    log_info "Usuario 'vulnweb' reconfigurado"
fi

# Asegurar que vulnweb NO esté en grupos privilegiados
usermod -G vulnweb vulnweb
gpasswd -d vulnweb sudo 2>/dev/null || true
gpasswd -d vulnweb admin 2>/dev/null || true
gpasswd -d vulnweb wheel 2>/dev/null || true

# Crear directorio home con permisos restrictivos
mkdir -p /var/www/vulnweb
chown vulnweb:vulnweb /var/www/vulnweb
chmod 750 /var/www/vulnweb

log_info "Usuario vulnweb aislado correctamente"

log_step "3" "Configurando restricciones de sistema para usuario vulnweb..."

# Configurar límites estrictos en /etc/security/limits.conf
cat << 'EOF' >> /etc/security/limits.conf

# Límites para usuario vulnweb (aplicación vulnerable)
vulnweb soft nproc 50
vulnweb hard nproc 100
vulnweb soft nofile 1024
vulnweb hard nofile 2048
vulnweb soft cpu 120
vulnweb hard cpu 180
vulnweb soft as 1048576
vulnweb hard as 2097152
vulnweb soft memlock 32768
vulnweb hard memlock 65536
EOF

# Configurar restricciones adicionales en systemd
mkdir -p /etc/systemd/system/user-vulnweb.slice.d
cat << 'EOF' > /etc/systemd/system/user-vulnweb.slice.d/50-limits.conf
[Slice]
CPUQuota=30%
MemoryMax=512M
TasksMax=50
DeviceAllow=/dev/null rw
DeviceAllow=/dev/zero rw
DeviceAllow=/dev/random r
DeviceAllow=/dev/urandom r
DevicePolicy=strict
NoNewPrivileges=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
EOF

systemctl daemon-reload

log_info "Límites de recursos configurados para vulnweb"

log_step "4" "Fortificando kernel y configuraciones del sistema..."

# Configuraciones de seguridad del kernel
cat << 'EOF' > /etc/sysctl.d/99-security-hardening.conf
# Protección de red
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Protección de memoria
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.perf_event_paranoid = 2

# Protección del sistema de archivos
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Protección adicional
net.core.bpf_jit_harden = 2
kernel.unprivileged_bpf_disabled = 1
EOF

sysctl -p /etc/sysctl.d/99-security-hardening.conf

log_info "Configuraciones de seguridad del kernel aplicadas"

log_step "5" "Configurando auditoría del sistema..."

# Configurar auditd para monitorear actividades críticas
cat << 'EOF' > /etc/audit/rules.d/99-vulnweb-monitoring.rules
# Monitorear actividades del usuario vulnweb
-a always,exit -F arch=b64 -S execve -F uid=vulnweb -k vulnweb_exec
-a always,exit -F arch=b32 -S execve -F uid=vulnweb -k vulnweb_exec

# Monitorear cambios en archivos críticos del sistema
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k ssh_config_changes

# Monitorear intentos de escalada de privilegios
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation

# Monitorear cambios en configuraciones de red
-w /etc/hosts -p wa -k network_changes
-w /etc/resolv.conf -p wa -k network_changes

# Monitorear creación de archivos SUID/SGID
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F exit=0 -k suid_sgid_changes
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F exit=0 -k suid_sgid_changes
EOF

# Reiniciar auditd
systemctl restart auditd
systemctl enable auditd

log_info "Sistema de auditoría configurado"

log_step "6" "Configurando fail2ban para protección contra ataques..."

# Configurar fail2ban con reglas específicas
cat << 'EOF' > /etc/fail2ban/jail.d/vulnweb-protection.conf
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*error.log
findtime = 600
bantime = 7200
maxretry = 10

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/*access.log
maxretry = 6
bantime = 86400

[vulnweb-command-injection]
enabled = true
filter = vulnweb-command-injection
action = iptables-multiport[name=VulnWebCmdInj, port="http,https", protocol=tcp]
logpath = /var/log/nginx/*access.log
maxretry = 2
bantime = 86400
EOF

# Crear filtro personalizado para detectar command injection
cat << 'EOF' > /etc/fail2ban/filter.d/vulnweb-command-injection.conf
[Definition]
failregex = ^<HOST> .* "(GET|POST).*[;&|`$(){}[\]\\].*" \d+ \d+ .*$
            ^<HOST> .* "(GET|POST).*(cat|ls|pwd|whoami|id|uname|wget|curl|nc|netcat|sh|bash).*" \d+ \d+ .*$
            ^<HOST> .* "(GET|POST).*\.\./.*" \d+ \d+ .*$

ignoreregex =
EOF

systemctl restart fail2ban
systemctl enable fail2ban

log_info "Fail2ban configurado con protecciones específicas"

log_step "7" "Configurando AppArmor para confinamiento de servicios..."

# Crear perfil AppArmor para Nginx
cat << 'EOF' > /etc/apparmor.d/usr.sbin.nginx
#include <tunables/global>

/usr/sbin/nginx {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  capability dac_override,
  capability setgid,
  capability setuid,
  capability net_bind_service,

  /usr/sbin/nginx mr,
  /var/log/nginx/** w,
  /var/www/vulnweb/** r,
  /var/cache/nginx/** rw,
  /var/lib/nginx/** rw,
  /run/nginx.pid rw,
  /etc/nginx/** r,
  /etc/ssl/certs/** r,
  /etc/ssl/private/** r,
  /run/php/php*-fpm*.sock rw,

  # Denegar acceso a archivos críticos del sistema
  deny /etc/passwd r,
  deny /etc/shadow r,
  deny /etc/group r,
  deny /root/** rwmix,
  deny /home/** rwmix,
  deny /var/log/auth.log r,
  deny /var/log/syslog r,
}
EOF

# Crear perfil AppArmor para PHP-FPM
cat << 'EOF' > /etc/apparmor.d/usr.sbin.php-fpm8.3
#include <tunables/global>

/usr/sbin/php-fpm8.3 {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/php>

  capability setgid,
  capability setuid,

  /usr/sbin/php-fpm8.3 mr,
  /etc/php/8.3/** r,
  /var/log/php8.3-fpm.log w,
  /run/php/php8.3-fpm.pid rw,
  /run/php/php8.3-fpm-vulnweb.sock rw,
  /var/www/vulnweb/** rw,
  /tmp/** rw,
  /dev/urandom r,

  # Permitir binarios básicos para funcionalidad vulnerable
  /bin/bash ix,
  /bin/sh ix,
  /bin/cat ix,
  /bin/ls ix,
  /bin/pwd ix,
  /usr/bin/whoami ix,
  /usr/bin/id ix,
  /bin/uname ix,
  /bin/ping ix,
  /usr/bin/nslookup ix,

  # Denegar acceso crítico del sistema
  deny /etc/passwd w,
  deny /etc/shadow rw,
  deny /etc/group w,
  deny /etc/sudoers rw,
  deny /root/** rwmix,
  deny /home/** rwmix,
  deny /var/log/auth.log rw,
  deny /var/log/syslog rw,
  deny /boot/** rwmix,
  deny /sys/** w,
  deny /proc/sys/** w,
}
EOF

# Cargar perfiles AppArmor
apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx 2>/dev/null || log_warning "AppArmor para nginx no se pudo cargar"
apparmor_parser -r /etc/apparmor.d/usr.sbin.php-fpm8.3 2>/dev/null || log_warning "AppArmor para PHP-FPM no se pudo cargar"

log_info "Perfiles AppArmor creados (se aplicarán cuando se instalen los servicios)"

log_step "8" "Configurando monitoreo de seguridad automatizado..."

# Script de monitoreo de seguridad
cat << 'EOF' > /usr/local/bin/vulnweb-security-monitor.sh
#!/bin/bash
# Monitor de seguridad para entorno vulnweb

LOG_FILE="/var/log/vulnweb-security.log"
ALERT_FILE="/var/log/vulnweb-alerts.log"

log_alert() {
    echo "[$(date)] SECURITY-ALERT: $1" >> $LOG_FILE
    echo "[$(date)] ALERT: $1" >> $ALERT_FILE
    logger -t vulnweb-monitor "SECURITY-ALERT: $1"
}

log_info() {
    echo "[$(date)] INFO: $1" >> $LOG_FILE
}

# Verificar escalada de privilegios
check_privilege_escalation() {
    # Procesos de vulnweb como root
    if ps -ef | grep -v grep | grep vulnweb | awk '$1=="root"' | grep -q .; then
        log_alert "Procesos de vulnweb ejecutándose como root detectados"
    fi

    # Verificar grupos del usuario vulnweb
    local vulnweb_groups=$(id vulnweb 2>/dev/null | grep -o 'groups=[^)]*' | tr ',' ' ')
    if echo "$vulnweb_groups" | grep -qE "(sudo|admin|wheel|root)"; then
        log_alert "Usuario vulnweb ha ganado grupos privilegiados: $(id vulnweb)"
    fi

    # Archivos SUID creados por vulnweb
    if find /var/www/vulnweb -user vulnweb -perm -4000 2>/dev/null | grep -q .; then
        log_alert "Archivos SUID creados por vulnweb detectados"
    fi

    # Modificaciones en archivos críticos del sistema
    if find /etc /root -user vulnweb 2>/dev/null | grep -q .; then
        log_alert "Usuario vulnweb ha modificado archivos del sistema"
    fi
}

# Verificar intentos de persistencia
check_persistence() {
    # Cronjobs del usuario vulnweb
    if crontab -u vulnweb -l >/dev/null 2>&1; then
        log_alert "Usuario vulnweb tiene cronjobs configurados"
    fi

    # Servicios systemd relacionados con vulnweb
    local vulnweb_services=$(systemctl list-units --all | grep vulnweb | grep -v php | wc -l)
    if [ $vulnweb_services -gt 0 ]; then
        log_alert "Servicios systemd adicionales relacionados con vulnweb detectados"
    fi

    # SSH keys
    if [ -d "/var/www/vulnweb/.ssh" ] || [ -f "/var/www/vulnweb/.ssh/authorized_keys" ]; then
        log_alert "SSH keys detectadas para usuario vulnweb"
    fi

    # Shells inversos
    if netstat -tulpn | grep vulnweb | grep -qE "(nc|netcat|bash|sh)"; then
        log_alert "Posibles shells inversos del usuario vulnweb detectados"
    fi
}

# Verificar integridad del sistema
check_system_integrity() {
    # Cambios en archivos críticos
    if [ -f /var/lib/aide/aide.db ]; then
        if ! aide --check 2>/dev/null | grep -q "All files match AIDE database"; then
            log_alert "Cambios en integridad del sistema detectados por AIDE"
        fi
    fi

    # Verificar rootkits con rkhunter
    if rkhunter --check --sk 2>/dev/null | grep -q "Warning"; then
        log_alert "Posibles rootkits detectados por rkhunter"
    fi
}

# Verificar uso de recursos
check_resource_usage() {
    # CPU del usuario vulnweb
    local cpu_usage=$(ps -u vulnweb -o %cpu --no-headers | awk '{sum+=$1} END {print sum}')
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        log_alert "Uso de CPU elevado por vulnweb: ${cpu_usage}%"
    fi

    # Memoria del usuario vulnweb
    local mem_usage=$(ps -u vulnweb -o %mem --no-headers | awk '{sum+=$1} END {print sum}')
    if (( $(echo "$mem_usage > 50" | bc -l) )); then
        log_alert "Uso de memoria elevado por vulnweb: ${mem_usage}%"
    fi

    # Procesos activos
    local proc_count=$(ps -u vulnweb --no-headers | wc -l)
    if [ $proc_count -gt 50 ]; then
        log_alert "Número elevado de procesos para vulnweb: $proc_count"
    fi
}

# Ejecutar todas las verificaciones
log_info "Iniciando verificaciones de seguridad"
check_privilege_escalation
check_persistence
check_system_integrity
check_resource_usage
log_info "Verificaciones de seguridad completadas"
EOF

chmod +x /usr/local/bin/vulnweb-security-monitor.sh

# Configurar cron para monitoreo cada 2 minutos
echo "*/2 * * * * root /usr/local/bin/vulnweb-security-monitor.sh" > /etc/cron.d/vulnweb-security-monitor

log_info "Monitoreo de seguridad automatizado configurado"

log_step "9" "Configurando respuesta a incidentes automatizada..."

# Script de respuesta a emergencias
cat << 'EOF' > /usr/local/bin/vulnweb-emergency-response.sh
#!/bin/bash
# Respuesta automatizada a incidentes de seguridad

LOG_FILE="/var/log/vulnweb-emergency.log"

log_emergency() {
    echo "[$(date)] EMERGENCY: $1" >> $LOG_FILE
    logger -t vulnweb-emergency "EMERGENCY: $1"
}

# Detener todos los servicios web
emergency_stop() {
    log_emergency "Iniciando parada de emergencia de servicios web"

    systemctl stop nginx 2>/dev/null || true
    systemctl stop php8.3-fpm 2>/dev/null || true

    # Matar todos los procesos del usuario vulnweb
    pkill -9 -u vulnweb 2>/dev/null || true

    # Bloquear tráfico web temporalmente
    iptables -I INPUT 1 -p tcp --dport 80 -j DROP 2>/dev/null || true
    iptables -I INPUT 1 -p tcp --dport 443 -j DROP 2>/dev/null || true

    log_emergency "Servicios web detenidos y tráfico bloqueado"
}

# Aislar usuario vulnweb
isolate_user() {
    log_emergency "Aislando usuario vulnweb"

    # Bloquear login del usuario
    usermod -s /bin/false vulnweb 2>/dev/null || true

    # Matar todas las sesiones
    pkill -9 -u vulnweb 2>/dev/null || true

    # Limpiar archivos temporales
    find /tmp -user vulnweb -delete 2>/dev/null || true
    find /var/tmp -user vulnweb -delete 2>/dev/null || true

    log_emergency "Usuario vulnweb aislado"
}

# Crear snapshot del estado actual
create_forensic_snapshot() {
    local snapshot_dir="/var/log/vulnweb-forensics/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$snapshot_dir"

    # Procesos activos
    ps aux > "$snapshot_dir/processes.txt"

    # Conexiones de red
    netstat -tulpn > "$snapshot_dir/network_connections.txt"

    # Archivos recientes del usuario vulnweb
    find /var/www/vulnweb -user vulnweb -mtime -1 > "$snapshot_dir/recent_files.txt"

    # Logs del sistema
    tail -n 500 /var/log/auth.log > "$snapshot_dir/auth.log" 2>/dev/null || true
    tail -n 500 /var/log/syslog > "$snapshot_dir/syslog" 2>/dev/null || true

    log_emergency "Snapshot forense creado en $snapshot_dir"
}

case "${1:-stop}" in
    "stop")
        emergency_stop
        ;;
    "isolate")
        isolate_user
        ;;
    "snapshot")
        create_forensic_snapshot
        ;;
    "full")
        create_forensic_snapshot
        isolate_user
        emergency_stop
        ;;
    *)
        echo "Uso: $0 {stop|isolate|snapshot|full}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/vulnweb-emergency-response.sh

log_info "Sistema de respuesta a emergencias configurado"

log_step "10" "Configurando hardening de SSH..."

# Backup de configuración SSH original
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Aplicar configuración SSH endurecida
cat << 'EOF' > /etc/ssh/sshd_config
# SSH Configuration - Security Hardened
Port 22
Protocol 2

# Autenticación
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Límites de sesión
MaxAuthTries 3
MaxStartups 2:30:10
MaxSessions 2
LoginGraceTime 60

# Configuraciones de seguridad
X11Forwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no

# Algoritmos seguros
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Usuarios y grupos permitidos
AllowUsers root
DenyUsers vulnweb
DenyGroups vulnweb

# Logging
SyslogFacility AUTHPRIV
LogLevel VERBOSE

# Banner
Banner /etc/issue.net
EOF

# Crear banner de advertencia
cat << 'EOF' > /etc/issue.net
*******************************************************************************
                            SISTEMA RESTRINGIDO
*******************************************************************************

ADVERTENCIA: Este sistema está configurado para pruebas de seguridad
controladas. Todo acceso está monitoreado y registrado.

Acceso autorizado únicamente.

*******************************************************************************
EOF

# Reiniciar SSH con nueva configuración
systemctl restart ssh

log_info "Configuración SSH endurecida aplicada"

log_step "11" "Configurando sistema de archivos seguro..."

# Proteger archivos críticos del sistema
chattr +i /etc/passwd /etc/shadow /etc/group /etc/sudoers 2>/dev/null || log_warning "No se pudo aplicar atributo inmutable"

# Configurar permisos restrictivos en directorios críticos
chmod 700 /root
chmod 755 /etc
chmod 640 /etc/shadow
chmod 644 /etc/passwd

# Crear directorio de trabajo aislado para vulnweb
mkdir -p /var/www/vulnweb/{public,tmp,logs,uploads}
chown -R vulnweb:vulnweb /var/www/vulnweb
chmod 750 /var/www/vulnweb
chmod 755 /var/www/vulnweb/public
chmod 777 /var/www/vulnweb/tmp
chmod 755 /var/www/vulnweb/logs
chmod 777 /var/www/vulnweb/uploads

# Configurar montajes seguros
echo "tmpfs /var/www/vulnweb/tmp tmpfs defaults,nodev,nosuid,noexec,uid=vulnweb,gid=vulnweb,mode=1777,size=100M 0 0" >> /etc/fstab

# Remount con nuevas opciones
mount -a 2>/dev/null || log_warning "No se pudo montar tmpfs para /var/www/vulnweb/tmp"

log_info "Sistema de archivos configurado de forma segura"

log_step "12" "Configurando logging y rotación..."

# Configurar logrotate para logs de vulnweb
cat << 'EOF' > /etc/logrotate.d/vulnweb
/var/log/vulnweb-*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    copytruncate
    notifempty
    create 644 root root
}

/var/www/vulnweb/logs/*.log {
    daily
    missingok
    rotate 3
    compress
    delaycompress
    copytruncate
    notifempty
    create 644 vulnweb vulnweb
}
EOF

# Configurar rsyslog para logs centralizados
cat << 'EOF' > /etc/rsyslog.d/50-vulnweb.conf
# Logs de vulnweb en archivo separado
:programname, isequal, "vulnweb-monitor" /var/log/vulnweb-security.log
:programname, isequal, "vulnweb-emergency" /var/log/vulnweb-emergency.log
& stop
EOF

systemctl restart rsyslog

log_info "Sistema de logging configurado"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           FORTIFICACIÓN DEL SISTEMA COMPLETADA${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}🔒 SISTEMA FORTIFICADO:${NC}"
echo -e "   ✅ Usuario aislado 'vulnweb' creado"
echo -e "   ✅ Límites de recursos aplicados"
echo -e "   ✅ Kernel endurecido"
echo -e "   ✅ Auditoría del sistema activada"
echo -e "   ✅ Fail2ban configurado"
echo -e "   ✅ AppArmor preparado"
echo -e "   ✅ SSH endurecido"
echo -e "   ✅ Sistema de archivos protegido"
echo -e "   ✅ Monitoreo automatizado activo"
echo -e "   ✅ Respuesta a incidentes configurada"
echo ""

echo -e "${YELLOW}🛠️ COMANDOS ADMINISTRATIVOS:${NC}"
echo -e "   • Monitoreo manual: ${GREEN}/usr/local/bin/vulnweb-security-monitor.sh${NC}"
echo -e "   • Emergencia total: ${GREEN}/usr/local/bin/vulnweb-emergency-response.sh full${NC}"
echo -e "   • Parar servicios: ${GREEN}/usr/local/bin/vulnweb-emergency-response.sh stop${NC}"
echo -e "   • Ver logs: ${GREEN}tail -f /var/log/vulnweb-security.log${NC}"
echo -e "   • Estado fail2ban: ${GREEN}fail2ban-client status${NC}"
echo ""

echo -e "${YELLOW}📊 VERIFICACIONES:${NC}"
if id vulnweb >/dev/null 2>&1; then
    echo -e "   ✅ Usuario vulnweb: $(id vulnweb)"
else
    echo -e "   ❌ Usuario vulnweb no encontrado"
fi

if systemctl is-active --quiet auditd; then
    echo -e "   ✅ Auditoría del sistema activa"
else
    echo -e "   ❌ Auditoría del sistema inactiva"
fi

if systemctl is-active --quiet fail2ban; then
    echo -e "   ✅ Fail2ban activo"
else
    echo -e "   ❌ Fail2ban inactivo"
fi

echo ""
echo -e "${GREEN}🎯 SISTEMA LISTO PARA DESPLIEGUE DE WEB VULNERABLE${NC}"
echo ""
