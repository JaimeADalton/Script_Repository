#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Instalación Completa
# =============================================================================
# Este script crea toda la estructura y despliega el stack completo
# 
# Uso: curl -sSL <url> | bash
#  o:  bash install.sh
#
# Requisitos:
#   - Ubuntu 22.04/24.04 o similar
#   - Docker + Docker Compose v2
#   - openssl
#   - 4GB RAM mínimo recomendado
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"; }

# Configuración
INSTALL_DIR="${NOC_INSTALL_DIR:-/opt/noc-isp}"
ADMIN_PASSWORD="${NOC_ADMIN_PASSWORD:-Admin123!}"
DB_PASSWORD="${NOC_DB_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 24)}"

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}║   ${GREEN}NOC-ISP Stack${CYAN}                                                          ║${NC}"
echo -e "${CYAN}║   LibreNMS + Oxidized + Nginx                                             ║${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
log_step "FASE 1: Verificación de Prerrequisitos"
# =============================================================================

# Verificar root o sudo
if [[ $EUID -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
        log_error "Este script requiere permisos de root. Ejecuta con sudo."
    fi
    SUDO="sudo"
else
    SUDO=""
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker no está instalado. Instálalo primero:\n  curl -fsSL https://get.docker.com | sh"
fi
log_success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# Verificar Docker Compose
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose v2 no está disponible"
fi
log_success "Docker Compose: $(docker compose version --short)"

# Verificar OpenSSL
if ! command -v openssl &> /dev/null; then
    log_error "openssl no está instalado"
fi
log_success "OpenSSL disponible"

# Verificar memoria
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
if [[ $TOTAL_MEM -lt 3500 ]]; then
    log_warning "Memoria disponible: ${TOTAL_MEM}MB (recomendado: 4GB+)"
else
    log_success "Memoria: ${TOTAL_MEM}MB"
fi

# =============================================================================
log_step "FASE 2: Creación de Estructura de Directorios"
# =============================================================================

log_info "Directorio de instalación: $INSTALL_DIR"

$SUDO mkdir -p "$INSTALL_DIR"/{librenms,db,redis,nginx/ssl,oxidized}
cd "$INSTALL_DIR"
log_success "Directorios creados"

# =============================================================================
log_step "FASE 3: Generación de Archivos de Configuración"
# =============================================================================

# --- .env ---
log_info "Creando .env..."
cat > .env << EOF
TZ=Europe/Madrid
PUID=1000
PGID=1000
DB_HOST=db
DB_DATABASE=librenms
DB_USER=librenms
DB_PASSWORD=${DB_PASSWORD}
REDIS_HOST=redis
LIBRENMS_BASE_URL=https://localhost
DISPATCHER_NODE_ID=dispatcher-node-01
EOF
log_success ".env creado"

# --- librenms.env ---
log_info "Creando librenms.env..."
cat > librenms.env << 'EOF'
MEMORY_LIMIT=512M
MAX_INPUT_VARS=1000
UPLOAD_MAX_SIZE=100M
OPCACHE_MEM_SIZE=128
REAL_IP_FROM=0.0.0.0/0
REAL_IP_HEADER=X-Forwarded-For
LOG_IP_VAR=remote_addr
CACHE_DRIVER=redis
SESSION_DRIVER=redis
REDIS_HOST=redis
LIBRENMS_SNMP_COMMUNITY=public
LIBRENMS_WEATHERMAP=false
LOG_LEVEL=info
EOF
log_success "librenms.env creado"

# --- docker-compose.yml ---
log_info "Creando docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE_EOF'
name: noc-isp

services:
  db:
    image: mariadb:10.11
    container_name: librenms_db
    hostname: db
    restart: always
    command:
      - "mysqld"
      - "--innodb-file-per-table=1"
      - "--lower-case-table-names=0"
      - "--character-set-server=utf8mb4"
      - "--collation-server=utf8mb4_unicode_ci"
      - "--innodb-buffer-pool-size=512M"
      - "--innodb-flush-log-at-trx-commit=2"
      - "--innodb-log-file-size=128M"
      - "--max-connections=300"
    volumes:
      - "./db:/var/lib/mysql"
    environment:
      TZ: ${TZ}
      MARIADB_RANDOM_ROOT_PASSWORD: "yes"
      MYSQL_DATABASE: ${DB_DATABASE}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - noc-internal

  redis:
    image: redis:7.2-alpine
    container_name: librenms_redis
    hostname: redis
    restart: always
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - "./redis:/data"
    environment:
      TZ: ${TZ}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - noc-internal

  librenms:
    image: librenms/librenms:latest
    container_name: librenms
    hostname: librenms
    restart: always
    cap_add:
      - NET_ADMIN
      - NET_RAW
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - "./librenms:/data"
    env_file:
      - "./librenms.env"
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
      DB_HOST: ${DB_HOST}
      DB_NAME: ${DB_DATABASE}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_TIMEOUT: 60
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/login", "-o", "/dev/null", "-s", "-w", "%{http_code}", "--max-time", "5"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    networks:
      - noc-internal

  dispatcher:
    image: librenms/librenms:latest
    container_name: librenms_dispatcher
    hostname: librenms-dispatcher
    restart: always
    cap_add:
      - NET_ADMIN
      - NET_RAW
    depends_on:
      librenms:
        condition: service_healthy
    volumes:
      - "./librenms:/data"
    env_file:
      - "./librenms.env"
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
      DB_HOST: ${DB_HOST}
      DB_NAME: ${DB_DATABASE}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_TIMEOUT: 60
      DISPATCHER_NODE_ID: ${DISPATCHER_NODE_ID}
      SIDECAR_DISPATCHER: 1
    networks:
      - noc-internal

  syslogng:
    image: librenms/librenms:latest
    container_name: librenms_syslogng
    hostname: librenms-syslogng
    restart: always
    cap_add:
      - NET_ADMIN
      - NET_RAW
    depends_on:
      librenms:
        condition: service_healthy
    ports:
      - "514:514/tcp"
      - "514:514/udp"
    volumes:
      - "./librenms:/data"
    env_file:
      - "./librenms.env"
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
      DB_HOST: ${DB_HOST}
      DB_NAME: ${DB_DATABASE}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_TIMEOUT: 60
      SIDECAR_SYSLOGNG: 1
    networks:
      - noc-internal

  snmptrapd:
    image: librenms/librenms:latest
    container_name: librenms_snmptrapd
    hostname: librenms-snmptrapd
    restart: always
    cap_add:
      - NET_ADMIN
      - NET_RAW
    depends_on:
      librenms:
        condition: service_healthy
    ports:
      - "162:162/tcp"
      - "162:162/udp"
    volumes:
      - "./librenms:/data"
    env_file:
      - "./librenms.env"
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
      DB_HOST: ${DB_HOST}
      DB_NAME: ${DB_DATABASE}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_TIMEOUT: 60
      SIDECAR_SNMPTRAPD: 1
    networks:
      - noc-internal

  oxidized:
    image: oxidized/oxidized:latest
    container_name: librenms_oxidized
    hostname: oxidized
    restart: always
    depends_on:
      librenms:
        condition: service_healthy
    volumes:
      - "./oxidized:/home/oxidized/.config/oxidized"
    ports:
      - "8888:8888"
    networks:
      - noc-internal

  nginx:
    image: nginx:alpine
    container_name: librenms_proxy
    hostname: proxy
    restart: always
    depends_on:
      librenms:
        condition: service_healthy
    volumes:
      - "./nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
      - "./nginx/ssl:/etc/nginx/ssl:ro"
    ports:
      - "80:80"
      - "443:443"
    networks:
      - noc-internal

networks:
  noc-internal:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
COMPOSE_EOF
log_success "docker-compose.yml creado"

# --- nginx.conf ---
log_info "Creando nginx/nginx.conf..."
cat > nginx/nginx.conf << 'NGINX_EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript 
               application/rss+xml application/atom+xml image/svg+xml;

    upstream librenms_backend {
        server librenms:8000;
        keepalive 32;
    }

    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name _;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:50m;

        client_max_body_size 100M;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        location / {
            proxy_pass http://librenms_backend;
        }

        location /api/ {
            proxy_pass http://librenms_backend;
            proxy_read_timeout 600s;
        }
    }
}
NGINX_EOF
log_success "nginx.conf creado"

# --- SSL Certificates ---
log_info "Generando certificados SSL..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/key.pem \
    -out nginx/ssl/cert.pem \
    -subj "/C=ES/ST=Madrid/L=Madrid/O=NOC-ISP/OU=Network Operations/CN=librenms.local" \
    2>/dev/null
log_success "Certificados SSL generados"

# --- Oxidized config ---
log_info "Creando oxidized/config..."
cat > oxidized/config << 'OXIDIZED_EOF'
---
username: admin
password: admin
enable: ~
interval: 3600
use_syslog: false
debug: false
threads: 30
timeout: 20
retries: 3
prompt: !ruby/regexp /^([\w.@-]+[#>]\s?)$/
rest: 0.0.0.0:8888
next_adds_job: false
vars:
  enable: ~
groups: {}
models: {}
pid: "/home/oxidized/.config/oxidized/pid"
log: "/home/oxidized/.config/oxidized/oxidized.log"
crash:
  directory: "/home/oxidized/.config/oxidized/crashes"
  hostnames: false
input:
  default: ssh, telnet
  debug: false
  ssh:
    secure: false
output:
  default: git
  git:
    user: Oxidized
    email: oxidized@noc.local
    repo: "/home/oxidized/.config/oxidized/git-repos/default.git"
source:
  default: csv
  csv:
    file: "/home/oxidized/.config/oxidized/router.db"
    delimiter: !ruby/regexp /:/
    map:
      name: 0
      model: 1
      group: 2
model_map:
  cisco: ios
  juniper: junos
  huawei: vrp
  routeros: routeros
  fortinet: fortios
  arista_eos: eos
OXIDIZED_EOF

# Router.db vacío
cat > oxidized/router.db << 'EOF'
# hostname:model:group
# router1.example.com:ios:core
EOF
log_success "Oxidized configurado"

# =============================================================================
log_step "FASE 4: Despliegue de Servicios"
# =============================================================================

log_info "Descargando imágenes Docker..."
docker compose pull --quiet 2>&1 | grep -v "^$" || true

log_info "Iniciando contenedores..."
docker compose up -d

# =============================================================================
log_step "FASE 5: Esperando Servicios"
# =============================================================================

wait_healthy() {
    local container=$1
    local max_wait=$2
    local waited=0
    echo -n "  $container: "
    while [[ $waited -lt $max_wait ]]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")
        if [[ "$status" == "healthy" ]]; then
            echo -e "${GREEN}healthy${NC}"
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
        echo -n "."
    done
    echo -e "${YELLOW}timeout (puede seguir iniciando)${NC}"
    return 0
}

wait_healthy "librenms_db" 60
wait_healthy "librenms_redis" 30
log_info "Esperando LibreNMS (2-3 minutos)..."
wait_healthy "librenms" 180

# =============================================================================
log_step "FASE 6: Configuración Inicial"
# =============================================================================

sleep 10
log_info "Creando usuario administrador..."
if docker compose exec -T librenms lnms user:add admin -p "${ADMIN_PASSWORD}" -r admin -e admin@noc.local 2>/dev/null; then
    log_success "Usuario admin creado"
else
    log_warning "Usuario admin ya existe o error en creación"
fi

# =============================================================================
log_step "FASE 7: Verificación Final"
# =============================================================================

echo ""
echo "Estado de contenedores:"
docker compose ps --format "table {{.Name}}\t{{.Status}}"

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}║   ${GREEN}✓ INSTALACIÓN COMPLETADA${CYAN}                                              ║${NC}"
echo -e "${CYAN}║                                                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Acceso Web:${NC}"
echo "    URL:      https://$(hostname -I | awk '{print $1}')"
echo "    Usuario:  admin"
echo "    Password: ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${GREEN}Servicios:${NC}"
echo "    HTTPS:      puerto 443"
echo "    Syslog:     puerto 514 (TCP/UDP)"
echo "    SNMP Traps: puerto 162 (TCP/UDP)"
echo "    Oxidized:   puerto 8888"
echo ""
echo -e "  ${GREEN}Directorio:${NC} ${INSTALL_DIR}"
echo ""
echo -e "  ${YELLOW}Próximos pasos:${NC}"
echo "    1. Accede a la web y cambia la contraseña"
echo "    2. Configura Oxidized:"
echo "       - Genera token API en Settings > API > API Settings"
echo "       - Edita ${INSTALL_DIR}/oxidized/config"
echo "       - Cambia 'source: csv' por 'source: http' con el token"
echo "       - docker compose restart oxidized"
echo ""
echo "  Comandos útiles:"
echo "    cd ${INSTALL_DIR}"
echo "    docker compose logs -f          # Ver logs"
echo "    docker compose restart          # Reiniciar"
echo "    docker compose down             # Detener"
echo ""
