#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Configurar Integración Oxidized-LibreNMS
# =============================================================================
# Uso: ./configure-oxidized-api.sh <TOKEN_API>
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ -z "$1" ]]; then
    echo ""
    echo -e "${CYAN}Uso:${NC} $0 <TOKEN_API>"
    echo ""
    echo "El token API se obtiene de LibreNMS:"
    echo "  1. Settings → API → API Settings"
    echo "  2. Click en 'Create API access token'"
    echo "  3. Copia el token generado"
    echo ""
    exit 1
fi

API_TOKEN="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${CYAN}Configurando integración Oxidized-LibreNMS${NC}"
echo ""

# Crear configuración
cat > data/oxidized/config << EOF
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
  juniper: junos
  routeros: routeros
  mikrotik: routeros
  fortinet: fortios
  huawei: vrp
  arista: eos
  linux: linux
EOF

echo -e "${GREEN}[✓]${NC} Configuración generada"

# Reiniciar Oxidized
docker compose restart oxidized
sleep 10

echo -e "${GREEN}[✓]${NC} Oxidized reiniciado"
echo ""
echo "Configura en LibreNMS:"
echo "  Settings → External → Oxidized Integration"
echo "  Enable: ✓"
echo "  URL: http://librenms_oxidized:8888"
echo ""
