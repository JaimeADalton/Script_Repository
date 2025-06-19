#!/bin/bash
# ============================================================================
# CONFIGURACIÓN DE FIREWALL PARA ENTORNO VULNWEB
# ============================================================================
# Configura iptables para permitir pruebas WAF desde redes autorizadas
# mientras protege el sistema host de accesos no autorizados
#
# Configuración de red esperada:
# - ens3: 192.168.255.119/24 (Red de gestión)
# - ens7: 192.168.0.119/22 (Red de laboratorio)
# - Gateway: 192.168.1.254
# ============================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "███████╗██╗██████╗ ███████╗██╗    ██╗ █████╗ ██╗     ██╗     "
    echo "██╔════╝██║██╔══██╗██╔════╝██║    ██║██╔══██╗██║     ██║     "
    echo "█████╗  ██║██████╔╝█████╗  ██║ █╗ ██║███████║██║     ██║     "
    echo "██╔══╝  ██║██╔══██╗██╔══╝  ██║███╗██║██╔══██║██║     ██║     "
    echo "██║     ██║██║  ██║███████╗╚███╔███╔╝██║  ██║███████╗███████╗"
    echo "╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}CONFIGURACIÓN DE FIREWALL PARA ENTORNO VULNWEB${NC}"
    echo -e "${GREEN}Protección del host + Acceso controlado para pruebas WAF${NC}"
    echo ""
}

log_step() {
    echo -e "${GREEN}[PASO $1/10]${NC} $2"
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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_banner

# Verificar ejecución como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root"
   exit 1
fi

# Verificar que los scripts anteriores se hayan ejecutado
if ! id vulnweb >/dev/null 2>&1; then
   log_error "Usuario 'vulnweb' no encontrado. Ejecutar primero: 01-fortify-system.sh"
   exit 1
fi

if ! systemctl is-active --quiet nginx; then
   log_error "Nginx no está activo. Ejecutar primero: 02-deploy-vulnerable-web.sh"
   exit 1
fi

log_step "1" "Detectando configuración de red..."

# Detectar interfaces de red
INTERFACES=$(ip link show | grep -E '^[0-9]+:' | grep -v lo | awk -F': ' '{print $2}' | cut -d'@' -f1)
log_info "Interfaces detectadas: $INTERFACES"

# Detectar gateway
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
log_info "Gateway detectado: $GATEWAY"

# Detectar IPs locales
LOCAL_IPS=$(ip addr show | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
log_info "IPs locales detectadas:"
for ip in $LOCAL_IPS; do
    echo "  - $ip"
done

# Configuración de redes autorizadas
SSH_ALLOWED_NET="192.168.252.50/32"          # IP específica para SSH
WAF_TESTING_NET="212.4.96.0/19"              # Red autorizada para pruebas WAF
MANAGEMENT_NET="192.168.255.0/24"            # Red de gestión (ens3)
LAB_NET="192.168.0.0/22"                     # Red de laboratorio (ens7)
LOCAL_NETS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"  # Redes privadas locales

log_step "2" "Respaldando configuración actual de iptables..."

# Crear directorio de backups
mkdir -p /etc/iptables/backups
BACKUP_FILE="/etc/iptables/backups/iptables-backup-$(date +%Y%m%d_%H%M%S).rules"

# Respaldar reglas actuales
iptables-save > "$BACKUP_FILE"
log_info "Backup creado: $BACKUP_FILE"

log_step "3" "Instalando herramientas de firewall necesarias..."

# Instalar herramientas si no están presentes
apt update
apt install -y iptables iptables-persistent netfilter-persistent

# Verificar que fail2ban esté configurado (del script anterior)
if systemctl is-active --quiet fail2ban; then
    log_info "Fail2ban detectado y activo"
else
    log_warning "Fail2ban no está activo - instalar desde 01-fortify-system.sh"
fi

log_step "4" "Limpiando reglas existentes..."

# Limpiar todas las reglas existentes
iptables -F
iptables -X
iptables -Z
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

log_info "Todas las reglas de iptables limpiadas"

log_step "5" "Estableciendo políticas por defecto..."

# Políticas por defecto - DENEGAR TODO excepto OUTPUT temporalmente
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT  # Temporal para no perder conectividad

log_success "Políticas por defecto establecidas (INPUT: DROP, FORWARD: DROP, OUTPUT: ACCEPT)"

log_step "6" "Configurando reglas básicas de conectividad..."

# ===== REGLAS BÁSICAS DE CONECTIVIDAD =====

# Permitir tráfico loopback (esencial para funcionamiento del sistema)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Permitir conexiones establecidas y relacionadas
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

log_success "Reglas básicas de conectividad configuradas"

log_step "7" "Configurando acceso SSH restringido..."

# ===== ACCESO SSH RESTRINGIDO =====

# SSH solo desde IP específica de gestión
iptables -A INPUT -p tcp -s $SSH_ALLOWED_NET --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT

# Protección adicional contra fuerza bruta SSH (complementa fail2ban)
iptables -A INPUT -p tcp --dport 22 -m recent --set --name SSH_ATTEMPT
iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 60 --hitcount 3 --name SSH_ATTEMPT -j LOG --log-prefix "SSH_BRUTE_FORCE: "
iptables -A INPUT -p tcp --dport 22 -m recent --update --seconds 60 --hitcount 3 --name SSH_ATTEMPT -j DROP

log_success "Acceso SSH configurado desde: $SSH_ALLOWED_NET"

log_step "8" "Configurando acceso web para pruebas WAF..."

# ===== ACCESO WEB PARA PRUEBAS WAF =====

# HTTP (puerto 80) desde red autorizada para pruebas WAF
iptables -A INPUT -p tcp -s $WAF_TESTING_NET --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT

# HTTPS (puerto 443) desde red autorizada para pruebas WAF
iptables -A INPUT -p tcp -s $WAF_TESTING_NET --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT

# Rate limiting específico para proteger contra DoS masivos (protege el host, no las aplicaciones)
iptables -A INPUT -p tcp --dport 80 -m limit --limit 100/sec --limit-burst 200 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m limit --limit 100/sec --limit-burst 200 -j ACCEPT

# Acceso web desde redes locales (gestión y laboratorio) con rate limiting más permisivo
iptables -A INPUT -p tcp -s $MANAGEMENT_NET --dport 80 -m limit --limit 50/sec --limit-burst 100 -j ACCEPT
iptables -A INPUT -p tcp -s $LAB_NET --dport 80 -m limit --limit 50/sec --limit-burst 100 -j ACCEPT

log_success "Acceso web configurado:"
log_info "  - Desde $WAF_TESTING_NET (pruebas WAF): 100 req/sec"
log_info "  - Desde $MANAGEMENT_NET (gestión): 50 req/sec"
log_info "  - Desde $LAB_NET (laboratorio): 50 req/sec"

log_step "9" "Configurando restricciones de salida y protecciones..."

# ===== CONFIGURAR OUTPUT CON RESTRICCIONES =====

# Primero, cambiar política OUTPUT a DROP y configurar explícitamente
iptables -P OUTPUT DROP

# Permitir DNS hacia servidores conocidos
iptables -A OUTPUT -p udp --dport 53 -d $GATEWAY -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d $GATEWAY -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -d 8.8.8.8 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 8.8.8.8 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -d 8.8.4.4 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 8.8.4.4 -j ACCEPT

# Permitir NTP para sincronización de tiempo
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

# Permitir actualizaciones del sistema (HTTP/HTTPS a repositorios)
iptables -A OUTPUT -p tcp --dport 80 -m owner --uid-owner root -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner root -j ACCEPT

# ===== RESTRICCIONES ESPECÍFICAS PARA USUARIO VULNWEB =====

# Permitir al usuario vulnweb hacer requests HTTP/HTTPS limitados (para funcionalidad vulnerable)
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 80 -m limit --limit 10/min --limit-burst 20 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 443 -m limit --limit 10/min --limit-burst 20 -j ACCEPT

# Bloquear intentos de reverse shell o tunneling del usuario vulnweb
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 22 -j LOG --log-prefix "VULNWEB_SSH_BLOCKED: "
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 22 -j DROP
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 23 -j DROP
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 3389 -j DROP
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 4444 -j DROP
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 1337 -j DROP
iptables -A OUTPUT -m owner --uid-owner vulnweb -p tcp --dport 8080 -j DROP

# Log y bloquear otras conexiones salientes no autorizadas del usuario vulnweb
iptables -A OUTPUT -m owner --uid-owner vulnweb -m limit --limit 5/min -j LOG --log-prefix "VULNWEB_OUT_BLOCKED: "
iptables -A OUTPUT -m owner --uid-owner vulnweb -j DROP

log_success "Restricciones de salida configuradas:"
log_info "  - DNS permitido a servidores conocidos"
log_info "  - NTP permitido para sincronización"
log_info "  - Usuario vulnweb: HTTP/HTTPS limitado (10/min)"
log_info "  - Usuario vulnweb: Reverse shells bloqueados"

# ===== PROTECCIONES ADICIONALES CONTRA ATAQUES COMUNES =====

# Protección contra ataques de red comunes
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL_PACKET: "
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j LOG --log-prefix "XMAS_PACKET: "
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN_FIN_PACKET: "
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j LOG --log-prefix "SYN_RST_PACKET: "
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

# Protección contra ping flood
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/sec --limit-burst 2 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j LOG --log-prefix "PING_FLOOD: "
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# Permitir ICMP echo-reply (respuestas a ping salientes)
iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT

log_success "Protecciones contra ataques comunes configuradas"

log_step "10" "Configurando logging y finalizando..."

# ===== LOGGING AVANZADO =====

# Loguear conexiones web exitosas para análisis (con rate limiting)
iptables -I INPUT -p tcp --dport 80 -m state --state NEW -m limit --limit 10/min -j LOG --log-prefix "WEB_ACCESS: " --log-level 4
iptables -I INPUT -p tcp --dport 443 -m state --state NEW -m limit --limit 10/min -j LOG --log-prefix "WEB_SSL_ACCESS: " --log-level 4

# Log de paquetes rechazados (con rate limiting para evitar spam)
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FW_INPUT_DROP: " --log-level 4
iptables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "FW_OUTPUT_DROP: " --log-level 4
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "FW_FORWARD_DROP: " --log-level 4

# ===== GUARDAR CONFIGURACIÓN =====

# Crear directorio para reglas permanentes
mkdir -p /etc/iptables

# Guardar reglas para sistemas basados en Debian/Ubuntu
if [ -f /etc/debian_version ]; then
    iptables-save > /etc/iptables/rules.v4
    log_success "Reglas guardadas en /etc/iptables/rules.v4"

    # Configurar para cargar al arranque
    systemctl enable netfilter-persistent

# Para sistemas basados en RedHat/CentOS
elif [ -f /etc/redhat-release ]; then
    service iptables save
    log_success "Reglas guardadas via service iptables"
    chkconfig iptables on
fi

# Crear script de restauración rápida
cat << 'EOF' > /usr/local/bin/vulnweb-firewall-restore.sh
#!/bin/bash
# Script de restauración rápida del firewall

LOG_FILE="/var/log/vulnweb-firewall.log"

log_action() {
    echo "[$(date)] $1" >> $LOG_FILE
    echo "$1"
}

if [ -f /etc/iptables/rules.v4 ]; then
    log_action "Restaurando reglas de firewall..."
    iptables-restore < /etc/iptables/rules.v4
    log_action "Reglas de firewall restauradas exitosamente"
else
    log_action "ERROR: No se encontró archivo de reglas /etc/iptables/rules.v4"
    exit 1
fi

# Verificar que los servicios críticos estén corriendo
if ! systemctl is-active --quiet nginx; then
    log_action "WARNING: Nginx no está activo"
fi

if ! systemctl is-active --quiet php8.3-fpm; then
    log_action "WARNING: PHP-FPM no está activo"
fi

log_action "Verificación de firewall completada"
EOF

chmod +x /usr/local/bin/vulnweb-firewall-restore.sh

# Crear script de monitoreo de firewall
cat << 'EOF' > /usr/local/bin/vulnweb-firewall-monitor.sh
#!/bin/bash
# Monitor de actividad del firewall

STATS_FILE="/var/log/vulnweb-firewall-stats.log"

# Estadísticas de iptables
echo "=== Firewall Statistics $(date) ===" >> $STATS_FILE
iptables -L -n -v >> $STATS_FILE
echo "" >> $STATS_FILE

# Top IPs bloqueadas
echo "=== Top Blocked IPs ===" >> $STATS_FILE
grep "FW_INPUT_DROP" /var/log/syslog | tail -100 | awk '{print $NF}' | cut -d'=' -f2 | sort | uniq -c | sort -nr | head -10 >> $STATS_FILE
echo "" >> $STATS_FILE

# Conexiones web recientes
echo "=== Recent Web Access ===" >> $STATS_FILE
grep "WEB_ACCESS" /var/log/syslog | tail -20 >> $STATS_FILE
echo "" >> $STATS_FILE

# Intentos de salida bloqueados del usuario vulnweb
echo "=== Vulnweb Blocked Outbound ===" >> $STATS_FILE
grep "VULNWEB_OUT_BLOCKED" /var/log/syslog | tail -10 >> $STATS_FILE
echo "" >> $STATS_FILE
EOF

chmod +x /usr/local/bin/vulnweb-firewall-monitor.sh

# Configurar cron para monitoreo
echo "0 * * * * root /usr/local/bin/vulnweb-firewall-monitor.sh" > /etc/cron.d/vulnweb-firewall-monitor

log_success "Scripts de administración de firewall creados"

# ===== MOSTRAR RESUMEN FINAL =====
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}     FIREWALL CONFIGURADO EXITOSAMENTE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}🌐 CONFIGURACIÓN DE RED DETECTADA:${NC}"
for ip in $LOCAL_IPS; do
    echo "  - IP Local: $ip"
done
echo "  - Gateway: $GATEWAY"
echo ""

echo -e "${YELLOW}🔐 ACCESOS PERMITIDOS:${NC}"
echo -e "  - ${GREEN}SSH${NC}: Desde ${RED}$SSH_ALLOWED_NET${NC} únicamente"
echo -e "  - ${GREEN}HTTP/HTTPS${NC}: Desde ${RED}$WAF_TESTING_NET${NC} (pruebas WAF)"
echo -e "  - ${GREEN}HTTP${NC}: Desde redes locales con rate limiting"
echo -e "  - ${GREEN}DNS${NC}: Hacia gateway y DNS públicos (8.8.8.8, 8.8.4.4)"
echo -e "  - ${GREEN}NTP${NC}: Para sincronización de tiempo"
echo ""

echo -e "${YELLOW}🚫 RESTRICCIONES APLICADAS:${NC}"
echo -e "  - ${RED}TODO EL RESTO DEL TRÁFICO BLOQUEADO${NC}"
echo -e "  - Usuario vulnweb: HTTP/HTTPS limitado (10 req/min)"
echo -e "  - Usuario vulnweb: Reverse shells bloqueados"
echo -e "  - Rate limiting: 100 req/sec para WAF testing"
echo -e "  - Protección contra ataques de red comunes"
echo ""

echo -e "${YELLOW}🛡️ PROTECCIONES ACTIVAS:${NC}"
echo -e "  - Anti-spoofing (NULL, XMAS, SYN-FIN packets)"
echo -e "  - Protección SSH contra fuerza bruta"
echo -e "  - Rate limiting en servicios web"
echo -e "  - Logging de actividad sospechosa"
echo -e "  - Bloqueo de reverse shells desde vulnweb"
echo ""

echo -e "${YELLOW}📊 COMANDOS DE MONITOREO:${NC}"
echo -e "  - Ver reglas activas: ${GREEN}iptables -L -n -v${NC}"
echo -e "  - Ver logs del firewall: ${GREEN}tail -f /var/log/syslog | grep 'FW_'${NC}"
echo -e "  - Estadísticas: ${GREEN}cat /var/log/vulnweb-firewall-stats.log${NC}"
echo -e "  - Restaurar reglas: ${GREEN}/usr/local/bin/vulnweb-firewall-restore.sh${NC}"
echo -e "  - Monitor automático: ${GREEN}/usr/local/bin/vulnweb-firewall-monitor.sh${NC}"
echo ""

echo -e "${YELLOW}🔧 ADMINISTRACIÓN:${NC}"
echo -e "  - Backup de reglas: ${GREEN}$BACKUP_FILE${NC}"
echo -e "  - Reglas activas: ${GREEN}/etc/iptables/rules.v4${NC}"
echo -e "  - Logs de firewall: ${GREEN}/var/log/vulnweb-firewall.log${NC}"
echo ""

echo -e "${YELLOW}🧪 TESTING DE CONECTIVIDAD:${NC}"
echo -e "  - Desde ${WAF_TESTING_NET}:"
echo -e "    curl http://$(echo $LOCAL_IPS | awk '{print $1}')"
echo -e "  - SSH desde ${SSH_ALLOWED_NET}:"
echo -e "    ssh $(echo $LOCAL_IPS | awk '{print $1}')"
echo ""

# Verificaciones finales
echo -e "${YELLOW}✅ VERIFICACIONES FINALES:${NC}"

# Verificar que iptables esté funcionando
if iptables -L >/dev/null 2>&1; then
    echo -e "  ✅ Iptables funcionando correctamente"
else
    echo -e "  ❌ Problemas con iptables"
fi

# Verificar persistencia
if [ -f /etc/iptables/rules.v4 ]; then
    echo -e "  ✅ Reglas guardadas para persistencia"
else
    echo -e "  ❌ Reglas no guardadas"
fi

# Verificar servicios web
if systemctl is-active --quiet nginx && systemctl is-active --quiet php8.3-fpm; then
    echo -e "  ✅ Servicios web funcionando"
else
    echo -e "  ❌ Problemas con servicios web"
fi

# Verificar fail2ban
if systemctl is-active --quiet fail2ban; then
    echo -e "  ✅ Fail2ban activo y funcionando"
else
    echo -e "  ⚠️  Fail2ban no detectado"
fi

# Contar reglas activas
RULES_COUNT=$(iptables -L | grep -c "Chain\|target")
echo -e "  ✅ Reglas de firewall activas: $RULES_COUNT"

echo ""
echo -e "${GREEN}🎉 CONFIGURACIÓN COMPLETA DEL ENTORNO VULNWEB${NC}"
echo -e "${GREEN}   ✅ Sistema fortificado (01-fortify-system.sh)${NC}"
echo -e "${GREEN}   ✅ Web vulnerable desplegada (02-deploy-vulnerable-web.sh)${NC}"
echo -e "${GREEN}   ✅ Firewall configurado (03-configure-firewall.sh)${NC}"
echo ""
echo -e "${GREEN}🚀 ENTORNO LISTO PARA PRUEBAS WAF${NC}"
echo -e "${GREEN}   El sistema está protegido pero permite pruebas controladas${NC}"
echo ""
echo -e "${RED}⚠️  ADVERTENCIA FINAL:${NC}"
echo -e "${RED}   - Solo accesible desde redes autorizadas${NC}"
echo -e "${RED}   - Usuario vulnweb confinado y monitoreado${NC}"
echo -e "${RED}   - Todas las conexiones están logueadas${NC}"
echo -e "${RED}   - Usar solo en entornos aislados${NC}"
echo ""
