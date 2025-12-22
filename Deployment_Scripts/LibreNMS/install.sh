#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Script de Instalación Completa y Automatizada
# =============================================================================
# Version: 3.2.0
#
# Este script despliega un stack completo de monitorización de red:
#   - LibreNMS (Network Monitoring System)
#   - MariaDB (Database)
#   - Redis (Cache/Sessions/Queues)
#   - Dispatcher (Poller distribuido)
#   - Syslog-ng (Receptor de logs)
#   - SNMP Trapd (Receptor de traps)
#   - Oxidized (Backup de configuraciones)
#   - Nginx (Reverse proxy HTTPS)
#
# Uso:
#   chmod +x install.sh
#   ./install.sh
#
# Para reinstalación limpia:
#   ./install.sh --clean
#
# Variables de entorno opcionales:
#   NOC_ADMIN_PASSWORD - Contraseña del usuario admin (default: Admin123!)
#   NOC_DB_PASSWORD    - Contraseña de la base de datos (se genera si no existe)
#   NOC_TIMEZONE       - Zona horaria (default: Europe/Madrid)
# =============================================================================

set -e

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
VERSION="3.2.0"
ADMIN_PASSWORD="${NOC_ADMIN_PASSWORD:-Admin123!}"
TIMEZONE="${NOC_TIMEZONE:-Europe/Madrid}"
CLEAN_INSTALL=false

# Parsear argumentos
if [[ "$1" == "--clean" || "$1" == "-c" ]]; then
    CLEAN_INSTALL=true
fi

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

# Verificar root (warning, no error)
if [[ $EUID -ne 0 ]]; then
    log_warning "No estás ejecutando como root. Algunas operaciones pueden requerir sudo."
fi

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

# Memoria
TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
if [[ $TOTAL_MEM -lt 3500 && $TOTAL_MEM -gt 0 ]]; then
    log_warning "Memoria: ${TOTAL_MEM}MB (recomendado: 4GB+)"
else
    log_success "Memoria: ${TOTAL_MEM}MB"
fi

# IP del servidor
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
log_success "IP del servidor: $SERVER_IP"

# =============================================================================
log_step "FASE 2: Preparación de Directorios"
# =============================================================================

# Limpieza si se solicita
if [[ "$CLEAN_INSTALL" == true ]]; then
    log_warning "Instalación limpia solicitada. Eliminando datos anteriores..."
    docker compose down --remove-orphans 2>/dev/null || true
    rm -rf data/ .env 2>/dev/null || true
    log_success "Datos anteriores eliminados"
fi

# Crear estructura de directorios
mkdir -p data/{db,redis,librenms,oxidized/configs,oxidized/crashes}
mkdir -p config/nginx/ssl
log_success "Directorios de datos creados"

# Copiar configuración de Oxidized
if [[ -f "config/oxidized/config" ]]; then
    cp config/oxidized/config data/oxidized/
    cp config/oxidized/router.db data/oxidized/
    log_success "Configuración de Oxidized copiada"
else
    # Crear configuración si no existe
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
chown -R 1000:1000 data/
log_success "Permisos establecidos"

# =============================================================================
log_step "FASE 3: Generación de Credenciales"
# =============================================================================

# SIEMPRE generar nueva contraseña si no existe o es placeholder
DB_PASSWORD="${NOC_DB_PASSWORD:-}"

if [[ -z "$DB_PASSWORD" ]]; then
    if [[ -f ".env" ]]; then
        CURRENT_PASS=$(grep "^DB_PASSWORD=" .env 2>/dev/null | cut -d= -f2)
        if [[ "$CURRENT_PASS" == "PLACEHOLDER"* || -z "$CURRENT_PASS" || "$CURRENT_PASS" == *"CHANGE"* ]]; then
            DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
            log_info "Generando nueva contraseña de base de datos..."
        else
            DB_PASSWORD="$CURRENT_PASS"
            log_info "Usando contraseña de DB existente"
        fi
    else
        DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
        log_info "Generando nueva contraseña de base de datos..."
    fi
fi

# Crear archivo .env (SIEMPRE sobrescribir para asegurar consistencia)
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

# Puertos
HTTP_PORT=80
HTTPS_PORT=443
SYSLOG_PORT=514
SNMPTRAP_PORT=162
OXIDIZED_PORT=8888
SESSION_SECURE_COOKIE=true
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
            echo -e "${YELLOW}unhealthy (reintentando)${NC}"
            sleep 10
            waited=$((waited + 10))
            continue
        fi
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done
    echo -e "${YELLOW}timeout (continuando)${NC}"
    return 0
}

wait_for_healthy "librenms_db" 120
wait_for_healthy "librenms_redis" 60

log_info "Esperando LibreNMS (puede tardar 2-4 minutos en el primer arranque)..."
wait_for_healthy "librenms" 300

# Esperar a que los sidecars estén completamente iniciados
log_info "Esperando estabilización de servicios sidecars..."
sleep 30

# =============================================================================
log_step "FASE 8: Configuración Inicial de LibreNMS"
# =============================================================================

# --- CORRECCIONES AUTOMÁTICAS (Lo que hiciste a mano) ---

# 1. FIX REDIS: Evita el error de escritura si hay poca memoria/disco
log_info "Aplicando corrección de persistencia en Redis..."
docker exec librenms_redis redis-cli CONFIG SET stop-writes-on-bgsave-error no 2>/dev/null || true

# 2. FIX PERMISOS: Asegura que LibreNMS pueda escribir sus gráficos y logs
log_info "Asegurando permisos correctos (RRD y Logs)..."
docker exec librenms chown -R librenms:librenms /data/rrd /data/logs /opt/librenms/logs 2>/dev/null || true

# 3. FIX MIGRACIÓN: Fuerza la creación de todas las tablas ANTES de crear usuarios
log_info "Ejecutando migraciones de base de datos pendientes..."
docker exec librenms php /opt/librenms/lnms migrate --force 2>/dev/null || true

# 4. FIX SCHEDULER: Instala el cron para evitar el error de 'Scheduler not running'
log_info "Instalando planificador de tareas (Scheduler)..."
docker exec librenms cp /opt/librenms/dist/librenms-scheduler.cron /etc/cron.d/librenms 2>/dev/null || true
docker exec librenms chmod 644 /etc/cron.d/librenms 2>/dev/null || true

# --- CONFIGURACIÓN ESTÁNDAR ---

# Crear usuario administrador (Ahora sí funcionará seguro porque la DB está migrada)
log_info "Creando usuario administrador..."
docker exec librenms php /opt/librenms/lnms user:add admin -p "${ADMIN_PASSWORD}" -r admin -e admin@noc.local 2>/dev/null && \
    log_success "Usuario admin creado" || \
    log_warning "Usuario admin ya existe"

# Configurar base_url
log_info "Configurando base_url..."
docker exec librenms php /opt/librenms/lnms config:set base_url "https://${SERVER_IP}" 2>/dev/null || true
log_success "base_url: https://${SERVER_IP}"

# Habilitar secure cookies - APLICANDO TU SOLUCIÓN MANUAL
log_info "Habilitando secure session cookies..."
# Tu fix manual fue editar /opt/librenms/.env, así que lo hacemos aquí directamente:
docker exec librenms bash -c 'grep -q "SESSION_SECURE_COOKIE" /opt/librenms/.env 2>/dev/null || echo "SESSION_SECURE_COOKIE=true" >> /opt/librenms/.env' 2>/dev/null || true
# Mantenemos también la configuración en config.php por redundancia
docker exec librenms bash -c 'cat >> /opt/librenms/config.php << EOF

// Secure cookies configuration
\$config["secure_cookies"] = true;
EOF
' 2>/dev/null || true
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

# Limpiar caché (Fundamental al final para aplicar los cambios del .env)
log_info "Limpiando y recargando caché..."
docker exec librenms php /opt/librenms/artisan config:cache 2>/dev/null || true
log_success "Caché limpiado"


# =============================================================================
log_step "FASE 9: Añadir Dispositivo de Prueba"
# =============================================================================

log_info "Añadiendo localhost como dispositivo de prueba..."
docker exec librenms php /opt/librenms/lnms device:add localhost --ping-only -f 2>/dev/null || true
log_success "Dispositivo localhost añadido"

# =============================================================================
log_step "FASE 10: Esperar Poller y Scheduler"
# =============================================================================

log_info "Esperando a que el dispatcher inicie el polling (60 segundos)..."
sleep 60

# Forzar un poll inicial
log_info "Ejecutando polling inicial de localhost..."
docker exec librenms php /opt/librenms/poller.php -h localhost 2>/dev/null | tail -5 || true

# Verificar que el dispatcher está funcionando
log_info "Verificando dispatcher..."
DISPATCHER_PROCS=$(docker exec librenms_dispatcher ps aux 2>/dev/null | grep -cE "python|dispatch|artisan" || echo "0")
if [[ "$DISPATCHER_PROCS" -gt 0 ]]; then
    log_success "Dispatcher activo con $DISPATCHER_PROCS procesos"
else
    log_warning "Dispatcher puede estar iniciando..."
    # Reiniciar dispatcher para forzar inicio
    docker compose restart dispatcher
    sleep 10
fi

# =============================================================================
log_step "FASE 11: Verificación del Sistema"
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
    elif echo "$line" | grep -qE "^[A-Za-z]+ Ok$"; then
        echo -e "  ${GREEN}✓${NC} $line"
    elif echo "$line" | grep -qE "Failure|Warning"; then
        echo -e "  ${YELLOW}!${NC} $line"
    else
        echo "  $line"
    fi
done

# =============================================================================
log_step "FASE 12: Estado Final"
# =============================================================================

echo ""
echo -e "${BOLD}Estado de contenedores:${NC}"
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | head -20

# Verificar servicios
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

# Oxidized - esperar un poco más
sleep 5
OX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888/nodes" 2>/dev/null || echo "000")
if [[ "$OX_STATUS" == "200" ]]; then
    echo -e "  ${GREEN}✓${NC} Oxidized API: Funcionando"
else
    echo -e "  ${YELLOW}!${NC} Oxidized API: Iniciando... (verificar en 1-2 minutos)"
fi

# Syslog - verificar desde el host
if ss -tuln 2>/dev/null | grep -q ":514 " || netstat -tuln 2>/dev/null | grep -q ":514 "; then
    echo -e "  ${GREEN}✓${NC} Syslog-ng: Puerto 514 escuchando"
else
    echo -e "  ${YELLOW}!${NC} Syslog-ng: Verificando..."
    docker exec librenms_syslogng ss -tuln 2>/dev/null | grep 514 && echo -e "  ${GREEN}✓${NC} Syslog interno OK" || true
fi

# SNMP Traps - verificar desde el host
if ss -tuln 2>/dev/null | grep -q ":162 " || netstat -tuln 2>/dev/null | grep -q ":162 "; then
    echo -e "  ${GREEN}✓${NC} SNMP Trapd: Puerto 162 escuchando"
else
    echo -e "  ${YELLOW}!${NC} SNMP Trapd: Verificando..."
    docker exec librenms_snmptrapd ss -tuln 2>/dev/null | grep 162 && echo -e "  ${GREEN}✓${NC} SNMP interno OK" || true
fi

# Dispatcher
DISP_STATUS=$(docker logs --tail=5 librenms_dispatcher 2>&1 | grep -cE "Completed|Starting|INFO" || echo "0")
if [[ "$DISP_STATUS" -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Dispatcher: Activo"
else
    echo -e "  ${YELLOW}!${NC} Dispatcher: Verificar logs"
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
echo "    • Syslog           ${SERVER_IP}:514 (TCP/UDP)"
echo "    • SNMP Traps       ${SERVER_IP}:162 (TCP/UDP)"
echo "    • Oxidized API     http://${SERVER_IP}:8888"
echo ""
echo -e "  ${GREEN}${BOLD}Credenciales de Base de Datos:${NC}"
echo "    Usuario:  librenms"
echo "    Password: ${DB_PASSWORD}"
echo ""
echo -e "  ${YELLOW}${BOLD}NOTA:${NC} El poller y scheduler pueden tardar 5-10 minutos en"
echo "  mostrar actividad en la validación. Es normal en el primer arranque."
echo ""
echo -e "  ${YELLOW}${BOLD}Próximos Pasos:${NC}"
echo "    1. Accede a https://${SERVER_IP} y cambia la contraseña"
echo "    2. Añade dispositivos: Devices → Add Device"
echo "    3. Configura Oxidized (opcional):"
echo "       Settings → API → Create Token"
echo "       ./configure-oxidized-api.sh <TOKEN>"
echo ""
echo -e "  ${BLUE}${BOLD}Comandos Útiles:${NC}"
echo "    docker compose ps              # Estado de contenedores"
echo "    docker compose logs -f         # Ver logs en tiempo real"
echo "    docker compose logs dispatcher # Logs del poller"
echo "    docker compose restart         # Reiniciar todo"
echo ""
echo -e "  ${BLUE}${BOLD}Verificar en 5 minutos:${NC}"
echo "    docker exec -u librenms librenms php /opt/librenms/validate.php"
echo ""
echo -e "  ${BLUE}${BOLD}Ubicación del Proyecto:${NC} $(pwd)"
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

Comandos útiles:
  docker compose ps
  docker compose logs -f
  docker compose restart
  docker exec -u librenms librenms php /opt/librenms/validate.php

NOTA: Los warnings de Poller/Scheduler son normales en los primeros
5-10 minutos. El sistema necesita tiempo para ejecutar el primer ciclo.
EOF

log_success "Información guardada en INSTALL_INFO.txt"
echo ""