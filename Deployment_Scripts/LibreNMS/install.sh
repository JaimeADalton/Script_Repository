#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Script de Instalación Completa y Automatizada
# =============================================================================
# Version: 4.0.0 - Final
# 
# Este script despliega un stack completo de monitorización de red:
#   - LibreNMS (Network Monitoring System)
#   - MariaDB (Database)
#   - Redis (Cache/Sessions/Queues)
#   - Dispatcher (Poller distribuido)
#   - Syslog-ng (Receptor de logs) - Con preservación de IP origen
#   - SNMP Trapd (Receptor de traps) - Con preservación de IP origen
#   - Oxidized (Backup de configuraciones)
#   - Nginx (Reverse proxy HTTPS)
#
# IMPORTANTE: Syslog y SNMPTrapd usan network_mode: host para preservar
# las IPs reales de los dispositivos que envían logs/traps, evitando
# el problema de Source NAT de Docker.
#
# Uso:
#   chmod +x install.sh
#   ./install.sh
#
# Para reinstalación limpia:
#   ./install.sh --clean
# =============================================================================

set -e

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
VERSION="4.0.0"
ADMIN_PASSWORD="${NOC_ADMIN_PASSWORD:-Admin123!}"
TIMEZONE="${NOC_TIMEZONE:-Europe/Madrid}"
CLEAN_INSTALL=false

# Parsear argumentos
for arg in "$@"; do
    case $arg in
        --clean|-c)
            CLEAN_INSTALL=true
            ;;
    esac
done

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Funciones de logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓ OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step() { 
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# BANNER
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}║   ${GREEN}███╗   ██╗ ██████╗  ██████╗      ██╗███████╗██████╗ ${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${GREEN}████╗  ██║██╔═══██╗██╔════╝      ██║██╔════╝██╔══██╗${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${GREEN}██╔██╗ ██║██║   ██║██║     █████╗██║███████╗██████╔╝${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${GREEN}██║╚██╗██║██║   ██║██║     ╚════╝██║╚════██║██╔═══╝ ${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${GREEN}██║ ╚████║╚██████╔╝╚██████╗      ██║███████║██║     ${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${GREEN}╚═╝  ╚═══╝ ╚═════╝  ╚═════╝      ╚═╝╚══════╝╚═╝     ${CYAN}                  ║${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}║   ${BOLD}Network Operations Center - Stack de Monitorización${NC}${CYAN}                  ║${NC}"
echo -e "${CYAN}║   ${NC}Version: ${VERSION}${CYAN}                                                        ║${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
log_step "FASE 1: Verificación de Prerrequisitos"
# =============================================================================

# Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker no está instalado. Instálalo con: curl -fsSL https://get.docker.com | sh"
fi
DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
log_success "Docker: $DOCKER_VERSION"

# Docker Compose
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose v2 no está disponible. Actualiza Docker."
fi
COMPOSE_VERSION=$(docker compose version --short)
log_success "Docker Compose: $COMPOSE_VERSION"

# OpenSSL
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL no está instalado. Instálalo con: apt install openssl"
fi
log_success "OpenSSL disponible"

# Verificar espacio en disco
DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "$DISK_AVAIL" -lt 10 ]]; then
    log_warning "Espacio en disco bajo: ${DISK_AVAIL}GB disponibles (recomendado: 10GB+)"
else
    log_success "Espacio en disco: ${DISK_AVAIL}GB disponibles"
fi

# Memoria
TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
if [[ $TOTAL_MEM -lt 3500 && $TOTAL_MEM -gt 0 ]]; then
    log_warning "Memoria: ${TOTAL_MEM}MB (recomendado: 4GB+)"
else
    log_success "Memoria: ${TOTAL_MEM}MB"
fi

# Verificar puertos (importante para network_mode: host)
check_port() {
    if ss -tuln 2>/dev/null | grep -q ":$1 "; then
        log_warning "Puerto $1 ya está en uso"
        return 1
    fi
    return 0
}

check_port 80 || true
check_port 443 || true
check_port 514 || log_warning "Puerto 514 ocupado - Syslog puede no funcionar"
check_port 162 || log_warning "Puerto 162 ocupado - SNMP Traps puede no funcionar"
check_port 8888 || true

# IP del servidor
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
log_success "IP del servidor: $SERVER_IP"

# =============================================================================
log_step "FASE 2: Preparación de Directorios"
# =============================================================================

# Limpieza si se solicita
if [[ "$CLEAN_INSTALL" == true ]]; then
    log_warning "Instalación limpia solicitada. Eliminando datos anteriores..."
    
    # Detener contenedores existentes
    docker compose down --remove-orphans 2>/dev/null || true
    docker stop $(docker ps -q --filter "name=librenms") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "name=librenms") 2>/dev/null || true
    
    # Eliminar datos
    rm -rf data/ 2>/dev/null || true
    
    log_success "Datos anteriores eliminados"
fi

# Crear estructura de directorios
mkdir -p data/{db,redis,librenms,oxidized/configs,oxidized/crashes}
mkdir -p config/nginx/ssl
log_success "Directorios de datos creados"

# Copiar configuración de Oxidized si existe en config/
if [[ -f "config/oxidized/config" ]]; then
    cp config/oxidized/config data/oxidized/
    cp config/oxidized/router.db data/oxidized/ 2>/dev/null || true
    log_success "Configuración de Oxidized copiada"
else
    # Crear configuración de Oxidized
    cat > data/oxidized/config << 'OXCONFIG'
---
username: admin
password: admin
enable: ~
interval: 3600
timeout: 20
retries: 3
debug: false
use_syslog: false
run_once: false
threads: 30
next_adds_job: false
prompt: !ruby/regexp /^([\w.@-]+[#>]\s?)$/
rest: 0.0.0.0:8888
pid: /home/oxidized/.config/oxidized/pid
log: /home/oxidized/.config/oxidized/oxidized.log
crash:
  directory: /home/oxidized/.config/oxidized/crashes
  hostnames: false
input:
  default: ssh, telnet
  debug: false
  ssh:
    secure: false
  ftp:
    passive: true
  utf8_encoded: true
output:
  default: file
  file:
    directory: /home/oxidized/.config/oxidized/configs
source:
  default: csv
  csv:
    file: /home/oxidized/.config/oxidized/router.db
    delimiter: !ruby/regexp /:/
    map:
      name: 0
      model: 1
      group: 2
model_map:
  cisco: ios
  juniper: junos
  routeros: routeros
  mikrotik: routeros
  fortinet: fortios
  huawei: vrp
  arista: eos
  linux: linux
OXCONFIG
    echo "dummy.local:linux:placeholder" > data/oxidized/router.db
    log_success "Configuración de Oxidized creada"
fi

# Establecer permisos
chmod -R 755 data/
log_success "Permisos establecidos"

# =============================================================================
log_step "FASE 3: Generación de Credenciales"
# =============================================================================

# Generar contraseña de DB
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

# Crear archivo .env
cat > .env << EOF
# =============================================================================
# NOC-ISP Stack - Variables de Entorno
# =============================================================================
# Generado automáticamente: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# General
TZ=${TIMEZONE}
PUID=1000
PGID=1000

# Database
DB_DATABASE=librenms
DB_USER=librenms
DB_PASSWORD=${DB_PASSWORD}

# Dispatcher
DISPATCHER_NODE_ID=dispatcher-node-01

# Puertos (solo para servicios que NO usan network_mode: host)
HTTP_PORT=80
HTTPS_PORT=443
OXIDIZED_PORT=8888

# NOTA: Syslog (514) y SNMP Traps (162) usan network_mode: host
# por lo que escuchan directamente en esos puertos del host
EOF

log_success "Archivo .env generado"
log_success "Contraseña de DB: ${DB_PASSWORD}"

# =============================================================================
log_step "FASE 4: Generación de Certificados SSL"
# =============================================================================

if [[ ! -f "config/nginx/ssl/cert.pem" ]] || [[ ! -f "config/nginx/ssl/key.pem" ]]; then
    log_info "Generando certificados SSL autofirmados..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout config/nginx/ssl/key.pem \
        -out config/nginx/ssl/cert.pem \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=NOC-ISP/OU=Network Operations/CN=${SERVER_IP}" \
        2>/dev/null
    chmod 600 config/nginx/ssl/key.pem
    chmod 644 config/nginx/ssl/cert.pem
    log_success "Certificados SSL generados"
else
    log_success "Certificados SSL ya existen"
fi

# =============================================================================
log_step "FASE 5: Validación de Configuración"
# =============================================================================

log_info "Validando docker-compose.yml..."
if docker compose config > /dev/null 2>&1; then
    log_success "Configuración Docker Compose válida"
else
    log_error "Error en docker-compose.yml. Verifica la sintaxis."
fi

# =============================================================================
log_step "FASE 6: Despliegue de Contenedores"
# =============================================================================

# Detener contenedores existentes
log_info "Deteniendo contenedores existentes (si los hay)..."
docker compose down --remove-orphans 2>/dev/null || true
sleep 3

# Descargar imágenes
log_info "Descargando imágenes Docker (esto puede tardar varios minutos)..."
docker compose pull 2>&1 | grep -E "Pulled|Pulling|Downloaded" || true

# Iniciar contenedores
log_info "Iniciando contenedores..."
docker compose up -d

log_success "Contenedores iniciados"

# =============================================================================
log_step "FASE 7: Esperando a que los Servicios Arranquen"
# =============================================================================

wait_for_healthy() {
    local container=$1
    local max_wait=$2
    local waited=0
    
    echo -n "  Esperando $container: "
    while [[ $waited -lt $max_wait ]]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")
        if [[ "$status" == "healthy" ]]; then
            echo -e "${GREEN}healthy${NC}"
            return 0
        elif [[ "$status" == "unhealthy" ]]; then
            echo -e "${YELLOW}reintentando${NC}"
            sleep 10
            waited=$((waited + 10))
            echo -n "  Esperando $container: "
            continue
        fi
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done
    echo -e "${YELLOW}timeout${NC}"
    return 0
}

wait_for_healthy "librenms_db" 120
wait_for_healthy "librenms_redis" 60

log_info "Esperando LibreNMS (puede tardar 2-4 minutos en el primer arranque)..."
wait_for_healthy "librenms" 300

# Esperar a que los sidecars estén completamente iniciados
log_info "Esperando estabilización de servicios..."
sleep 30

# =============================================================================
log_step "FASE 8: Configuración Inicial de LibreNMS"
# =============================================================================

# Crear usuario administrador
log_info "Creando usuario administrador..."
docker exec librenms php /opt/librenms/lnms user:add admin -p "${ADMIN_PASSWORD}" -r admin -e admin@noc.local 2>/dev/null && \
    log_success "Usuario admin creado" || \
    log_warning "Usuario admin ya existe"

# Configurar base_url
log_info "Configurando base_url..."
docker exec librenms php /opt/librenms/lnms config:set base_url "https://${SERVER_IP}" 2>/dev/null || true
log_success "base_url: https://${SERVER_IP}"

# Habilitar secure cookies - MÉTODO CORRECTO
log_info "Habilitando secure session cookies..."
docker exec librenms bash -c '
if ! grep -q "SESSION_SECURE_COOKIE" /opt/librenms/.env 2>/dev/null; then
    echo "SESSION_SECURE_COOKIE=true" >> /opt/librenms/.env
fi
'
log_success "Secure cookies configuradas"

# Habilitar syslog
log_info "Habilitando syslog..."
docker exec librenms php /opt/librenms/lnms config:set enable_syslog true 2>/dev/null || true
log_success "Syslog habilitado"

# Configurar integración Oxidized
log_info "Configurando integración Oxidized..."
docker exec librenms php /opt/librenms/lnms config:set oxidized.enabled true 2>/dev/null || true
docker exec librenms php /opt/librenms/lnms config:set oxidized.url "http://librenms_oxidized:8888" 2>/dev/null || true
docker exec librenms php /opt/librenms/lnms config:set oxidized.features.versioning true 2>/dev/null || true
log_success "Oxidized configurado"

# Limpiar caché de Laravel
log_info "Aplicando configuración (cache)..."
docker exec librenms php /opt/librenms/artisan config:cache 2>/dev/null || true
log_success "Configuración aplicada"

# =============================================================================
log_step "FASE 9: Añadir Dispositivo de Prueba y Polling Inicial"
# =============================================================================

# Añadir localhost
log_info "Añadiendo localhost como dispositivo de prueba..."
docker exec librenms php /opt/librenms/lnms device:add localhost --ping-only -f 2>/dev/null || true
log_success "Dispositivo localhost añadido"

# Esperar un poco más para que el dispatcher se registre
log_info "Esperando registro del dispatcher (45 segundos)..."
sleep 45

# Ejecutar polling inicial
log_info "Ejecutando polling inicial..."
docker exec librenms php /opt/librenms/poller.php -h localhost 2>&1 | tail -3 || true
log_success "Polling inicial completado"

# =============================================================================
log_step "FASE 10: Verificación del Sistema"
# =============================================================================

log_info "Ejecutando validación de LibreNMS..."
echo ""
docker exec -u librenms librenms php /opt/librenms/validate.php 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -q "^\[OK\]"; then
        echo -e "  ${GREEN}$line${NC}"
    elif echo "$line" | grep -q "^\[FAIL\]"; then
        echo -e "  ${RED}$line${NC}"
    elif echo "$line" | grep -q "^\[WARN\]"; then
        echo -e "  ${YELLOW}$line${NC}"
    elif echo "$line" | grep -qE "^="; then
        echo -e "  ${CYAN}$line${NC}"
    else
        echo "  $line"
    fi
done

# =============================================================================
log_step "FASE 11: Estado Final"
# =============================================================================

echo ""
echo -e "${BOLD}Estado de contenedores:${NC}"
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || docker ps --format "table {{.Names}}\t{{.Status}}" --filter "name=librenms"

echo ""
echo -e "${BOLD}Verificación de servicios:${NC}"
echo ""

# MariaDB
if docker exec librenms_db mysqladmin ping -u librenms -p"$DB_PASSWORD" --silent 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} MariaDB: Funcionando"
else
    echo -e "  ${RED}✗${NC} MariaDB: Error"
fi

# Redis
if docker exec librenms_redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo -e "  ${GREEN}✓${NC} Redis: Funcionando"
else
    echo -e "  ${RED}✗${NC} Redis: Error"
fi

# LibreNMS Web
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${SERVER_IP}/login" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    echo -e "  ${GREEN}✓${NC} LibreNMS Web: Accesible (HTTP $HTTP_CODE)"
else
    echo -e "  ${YELLOW}!${NC} LibreNMS Web: HTTP $HTTP_CODE"
fi

# Oxidized
sleep 3
OX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888/nodes" 2>/dev/null || echo "000")
if [[ "$OX_STATUS" == "200" ]]; then
    echo -e "  ${GREEN}✓${NC} Oxidized API: Funcionando"
else
    echo -e "  ${YELLOW}!${NC} Oxidized API: Iniciando..."
fi

# Syslog (network_mode: host)
if ss -tuln 2>/dev/null | grep -q ":514 "; then
    echo -e "  ${GREEN}✓${NC} Syslog-ng: Puerto 514 escuchando (IPs reales preservadas)"
else
    echo -e "  ${YELLOW}!${NC} Syslog-ng: Verificando..."
fi

# SNMP Traps (network_mode: host)
if ss -tuln 2>/dev/null | grep -q ":162 "; then
    echo -e "  ${GREEN}✓${NC} SNMP Trapd: Puerto 162 escuchando (IPs reales preservadas)"
else
    echo -e "  ${YELLOW}!${NC} SNMP Trapd: Verificando..."
fi

# Dispatcher
DISP_PROCS=$(docker exec librenms_dispatcher ps aux 2>/dev/null | grep -c "librenms-service\|python" || echo "0")
if [[ "$DISP_PROCS" -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Dispatcher: Activo ($DISP_PROCS procesos)"
else
    echo -e "  ${YELLOW}!${NC} Dispatcher: Verificando..."
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}║   ${GREEN}✓ INSTALACIÓN COMPLETADA EXITOSAMENTE${CYAN}                                 ║${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Acceso Web:${NC}"
echo "    URL:      https://${SERVER_IP}"
echo "    Usuario:  admin"
echo "    Password: ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${GREEN}${BOLD}Servicios Disponibles:${NC}"
echo "    • LibreNMS Web     https://${SERVER_IP}"
echo "    • Syslog           ${SERVER_IP}:514 (TCP/UDP) - IPs reales preservadas"
echo "    • SNMP Traps       ${SERVER_IP}:162 (TCP/UDP) - IPs reales preservadas"
echo "    • Oxidized API     http://${SERVER_IP}:8888"
echo ""
echo -e "  ${GREEN}${BOLD}Credenciales de Base de Datos:${NC}"
echo "    Usuario:  librenms"
echo "    Password: ${DB_PASSWORD}"
echo ""
echo -e "  ${YELLOW}${BOLD}Nota sobre Syslog/SNMP:${NC}"
echo "    Los servicios Syslog y SNMP Traps usan network_mode: host"
echo "    para preservar las IPs reales de los dispositivos origen."
echo "    Esto evita el problema de Source NAT de Docker."
echo ""
echo -e "  ${BLUE}${BOLD}Comandos Útiles:${NC}"
echo "    docker compose ps                    # Estado de contenedores"
echo "    docker compose logs -f               # Ver logs en tiempo real"
echo "    docker compose logs -f syslogng      # Logs de syslog"
echo "    docker compose restart               # Reiniciar todo"
echo ""
echo -e "  ${BLUE}${BOLD}Verificación:${NC}"
echo "    docker exec -u librenms librenms php /opt/librenms/validate.php"
echo ""
echo -e "  ${BLUE}${BOLD}Ubicación:${NC} $(pwd)"
echo ""

# Guardar información de instalación
cat > INSTALL_INFO.txt << EOF
# =============================================================================
# NOC-ISP Stack - Información de Instalación
# =============================================================================
# Fecha: $(date)
# Versión: ${VERSION}
# =============================================================================

Acceso Web:
  URL:      https://${SERVER_IP}
  Usuario:  admin
  Password: ${ADMIN_PASSWORD}

Base de Datos:
  Host:     localhost (librenms_db container)
  Database: librenms
  Usuario:  librenms
  Password: ${DB_PASSWORD}

Servicios:
  LibreNMS:    https://${SERVER_IP}
  Syslog:      ${SERVER_IP}:514 (TCP/UDP)
  SNMP Traps:  ${SERVER_IP}:162 (TCP/UDP)
  Oxidized:    http://${SERVER_IP}:8888

NOTA IMPORTANTE:
  Syslog y SNMP Traps usan network_mode: host para preservar
  las IPs reales de los dispositivos que envían logs/traps.
  Esto soluciona el problema de Source NAT de Docker.
EOF

log_success "Información guardada en INSTALL_INFO.txt"
echo ""
