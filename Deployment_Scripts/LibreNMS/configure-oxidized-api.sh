#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Configurar Integración Oxidized-LibreNMS
# =============================================================================
# Este script configura Oxidized para usar la API de LibreNMS como fuente
# de dispositivos en lugar del archivo CSV estático.
#
# Uso:
#   ./configure-oxidized-api.sh <TOKEN_API>
#
# El token API se obtiene de LibreNMS:
#   1. Settings → API → API Settings
#   2. Click en "Create API access token"
#   3. Copia el token generado
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
log_success() { echo -e "${GREEN}[✓ OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Verificar argumento
if [[ -z "$1" ]]; then
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   Configurar Integración Oxidized-LibreNMS                                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Uso:${NC} $0 <TOKEN_API>"
    echo ""
    echo "El token API se obtiene de LibreNMS:"
    echo "  1. Settings → API → API Settings"
    echo "  2. Click en 'Create API access token'"
    echo "  3. Copia el token generado"
    echo ""
    exit 1
fi

API_TOKEN="$1"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Configurando integración Oxidized-LibreNMS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Verificar que LibreNMS está corriendo
log_info "Verificando que LibreNMS está disponible..."
if ! docker compose ps librenms 2>/dev/null | grep -q "healthy\|running"; then
    log_error "LibreNMS no está corriendo. Ejecuta primero: docker compose up -d"
fi
log_success "LibreNMS está disponible"

# Validar token
log_info "Validando token API..."
HTTP_CODE=$(docker exec librenms curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Auth-Token: $API_TOKEN" \
    "http://localhost:8000/api/v0/oxidized" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "Token válido"
elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
    log_error "Token inválido o sin permisos. Verifica el token."
else
    log_warning "No se pudo validar el token (HTTP $HTTP_CODE). Continuando..."
fi

# Crear nueva configuración de Oxidized
log_info "Generando nueva configuración de Oxidized..."

cat > data/oxidized/config << EOF
# =============================================================================
# Oxidized Configuration - Integrado con LibreNMS API
# =============================================================================
# Configurado automáticamente: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================
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
use_max_threads: false
next_adds_job: false

prompt: !ruby/regexp /^([\w.@-]+[#>]\s?)$/

rest: 0.0.0.0:8888

vars:
  enable: ~

groups: {}
models: {}

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

# Integración con LibreNMS API
source:
  default: http
  http:
    url: http://librenms:8000/api/v0/oxidized
    scheme: http
    map:
      name: hostname
      model: os
      group: group
    headers:
      X-Auth-Token: '$API_TOKEN'

model_map:
  cisco: ios
  ciscowlc: aireos
  iosxe: iosxe
  iosxr: iosxr
  nxos: nxos
  asa: asa
  juniper: junos
  junos: junos
  arista_eos: eos
  arista: eos
  linux: linux
  procurve: procurve
  aruba-os: arubaos
  routeros: routeros
  mikrotik: routeros
  vyos: vyos
  panos: panos
  fortinet: fortios
  fortigate: fortios
  huawei: vrp
  dell: powerconnect
  dlink: dlink
  edgeos: edgeos
  opnsense: opnsense
  pfsense: pfsense
  tplink: tplink
  ubiquiti: airos
  unifi: unifi
  opengear: opengear
  nokia: sros
  comware: comware
  hp: procurve
  hpe: procurve
EOF

log_success "Configuración generada"

# Reiniciar Oxidized
log_info "Reiniciando Oxidized..."
docker compose restart oxidized
sleep 10

# Verificar
log_info "Verificando estado de Oxidized..."
if docker logs --tail=5 librenms_oxidized 2>&1 | grep -qE "Loaded|Starting"; then
    log_success "Oxidized reiniciado correctamente"
else
    log_warning "Verifica los logs: docker compose logs oxidized"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Integración configurada${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Para habilitar Oxidized en LibreNMS:"
echo "    1. Settings → External → Oxidized Integration"
echo "    2. Enable Oxidized support: ✓"
echo "    3. Oxidized URL: http://librenms_oxidized:8888"
echo "    4. Guarda los cambios"
echo ""
echo "  Los dispositivos con 'Config' habilitado aparecerán en Oxidized."
echo ""
echo "  Verificar estado:"
echo "    curl http://localhost:8888/nodes"
echo "    docker compose logs oxidized"
echo ""
