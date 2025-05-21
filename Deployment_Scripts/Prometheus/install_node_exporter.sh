#!/usr/bin/env bash
# install_node_exporter.sh
# Instalación automatizada de Node Exporter 1.9.1 en Debian/Ubuntu
set -euo pipefail

### Parámetros que (aún) puedes ajustar #######################################
PORT="${PORT:-9200}"          # Cambia el puerto sólo si lo necesitas
################################################################################

# CONSTANTES (no las toques si no es imprescindible)
# Servidor web levantado con python3 -m http.server
URL="http://10.7.220.15:8000/node_exporter-1.9.1.linux-amd64/node_exporter"
BIN_DIR="/usr/bin"
SERVICE_FILE="/usr/lib/systemd/system/node_exporter.service"
USER="node_exporter"
GROUP="node_exporter"

## Funciones utilitarias -------------------------------------------------------
info () { printf '\e[34m[INFO]\e[0m %s\n' "$*"; }
error() { printf '\e[31m[ERR ]\e[0m %s\n' "$*" >&2; exit 1; }

require_root () {
  [[ $EUID -eq 0 ]] || error "Ejecuta este script como root o con sudo."
}

install_deps () {
  command -v curl >/dev/null 2>&1 && return
  info "Instalando curl..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl
}

create_user () {
  getent group "$GROUP" >/dev/null || groupadd -r "$GROUP"
  id -u "$USER"  >/dev/null 2>&1 || useradd -r -g "$GROUP" -s /usr/sbin/nologin "$USER"
}

download_binary () {
  info "Descargando node_exporter desde URL fija..."
  curl -fsSL "$URL" -o "${BIN_DIR}/node_exporter"
  chmod 0755 "${BIN_DIR}/node_exporter"
  chown "${USER}:${GROUP}" "${BIN_DIR}/node_exporter"
}

create_service () {
  info "Creando servicio systemd..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
Wants=network-online.target
After=network-online.target

[Service]
User=${USER}
Group=${GROUP}
Type=simple
Restart=on-failure
ExecStart=${BIN_DIR}/node_exporter --web.listen-address=:${PORT}

[Install]
WantedBy=multi-user.target
EOF
  chmod 664 "$SERVICE_FILE"
}

start_service () {
  info "Habilitando y arrancando node_exporter..."
  systemctl daemon-reload
  systemctl enable --now node_exporter
}

open_ufw_port () {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    info "Abriendo el puerto ${PORT}/tcp en ufw..."
    ufw allow "${PORT}/tcp"
  fi
}

verify () {
  info "Comprobando servicio..."
  systemctl --no-pager --full status node_exporter
  echo
  info "Prueba las métricas en:"
  echo "  http://$(hostname -I | awk '{print $1}'):${PORT}/metrics"
}

### Ejecución ##################################################################
require_root
install_deps
create_user
download_binary
create_service
start_service
open_ufw_port
verify

info "Instalación completada."
