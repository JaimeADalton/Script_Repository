#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Configurar integración Oxidized-LibreNMS
# =============================================================================
# Uso: ./configure-oxidized.sh <API_TOKEN>
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Verificar argumento
if [[ -z "$1" ]]; then
    echo ""
    echo "Uso: $0 <API_TOKEN>"
    echo ""
    echo "El token API se obtiene de LibreNMS:"
    echo "  1. Accede a Settings > API > API Settings"
    echo "  2. Click en 'Create API access token'"
    echo "  3. Copia el token generado"
    echo ""
    exit 1
fi

API_TOKEN="$1"

echo ""
echo "============================================================================="
echo "  Configurando integración Oxidized-LibreNMS"
echo "============================================================================="
echo ""

# Validar que el token funciona
log_info "Validando token API..."
HTTP_CODE=$(docker compose exec -T librenms curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Auth-Token: $API_TOKEN" \
    "http://localhost:8000/api/v0/oxidized" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "Token válido - API accesible"
elif [[ "$HTTP_CODE" == "401" ]]; then
    log_error "Token inválido o sin permisos"
    exit 1
else
    log_error "No se pudo conectar a la API (HTTP $HTTP_CODE)"
    exit 1
fi

# Actualizar configuración de Oxidized
log_info "Actualizando configuración de Oxidized..."

cat > oxidized/config << EOF
# =============================================================================
# Oxidized Configuration - Integrado con LibreNMS
# =============================================================================
# Configurado automáticamente por configure-oxidized.sh
# =============================================================================
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

hooks: {}

model_map:
  cisco: ios
  ciscowlc: aireos
  juniper: junos
  junos: junos
  arista_eos: eos
  linux: linux
  procurve: procurve
  aruba-os: arubaos
  routeros: routeros
  vyos: vyos
  panos: panos
  fortinet: fortios
  huawei: vrp
  dell: powerconnect
  dlink: dlink
  edgeos: edgeos
  opnsense: opnsense
  pfsense: pfsense
  tplink: tplink
  ubiquiti: airos
  unifi: unifi
EOF

log_success "Configuración actualizada"

# Reiniciar Oxidized
log_info "Reiniciando Oxidized..."
docker compose restart oxidized

# Esperar a que arranque
sleep 10

# Verificar estado
log_info "Verificando estado de Oxidized..."
OXIDIZED_STATUS=$(docker compose exec -T oxidized curl -s http://localhost:8888/nodes 2>/dev/null | head -c 100 || echo "error")

if [[ "$OXIDIZED_STATUS" != "error" ]]; then
    log_success "Oxidized funcionando correctamente"
else
    log_error "Oxidized no responde - revisa los logs con: docker compose logs oxidized"
fi

echo ""
echo "============================================================================="
echo -e "  ${GREEN}✓ Integración configurada${NC}"
echo "============================================================================="
echo ""
echo "  Para habilitar Oxidized en dispositivos LibreNMS:"
echo "    1. Ve a Settings > Global Settings > External > Oxidized"
echo "    2. Activa 'Enable Oxidized support'"
echo "    3. URL: http://librenms_oxidized:8888"
echo "    4. Marca los grupos de dispositivos a incluir"
echo ""
echo "============================================================================="
