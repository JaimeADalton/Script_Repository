#!/bin/bash

# Script de instalación de Prometheus para Ubuntu 24.04
# Requisitos: Grafana y Telegraf ya instalados
# Autor: Modificado por Claude
# Fecha: 6 de marzo de 2025

# Colores para mejor legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes de estado
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Función para comprobar y manejar errores
check_error() {
    if [ $? -ne 0 ]; then
        print_error "$1"
    fi
}

# Verificar que se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root o con sudo"
fi

print_status "Iniciando instalación de Prometheus en Ubuntu 24.04..."

# Variables de configuración (versiones actualizadas)
PROMETHEUS_VERSION="3.2.1"
BLACKBOX_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.9.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
PROMETHEUS_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_CONFIG="${PROMETHEUS_DIR}/prometheus.yml"
TEMP_DIR=$(mktemp -d)

# Función para limpiar archivos temporales
cleanup() {
    print_status "Limpiando archivos temporales..."
    rm -rf "${TEMP_DIR}"
    print_status "Limpieza completada."
}

# Configurar limpieza en caso de interrupción
trap cleanup EXIT

# 1. Crear usuario y directorios para Prometheus
print_status "Creando usuario y directorios para Prometheus..."
id -u ${PROMETHEUS_USER} &>/dev/null || useradd --no-create-home --shell /bin/false ${PROMETHEUS_USER}
id -u blackbox_exporter &>/dev/null || useradd --no-create-home --shell /bin/false blackbox_exporter
id -u node_exporter &>/dev/null || useradd --no-create-home --shell /bin/false node_exporter

mkdir -p ${PROMETHEUS_DIR}/{rules,file_sd}
mkdir -p ${PROMETHEUS_DATA_DIR}
check_error "No se pudieron crear los directorios necesarios"

# 2. Descargar y extraer Prometheus
print_status "Descargando Prometheus v${PROMETHEUS_VERSION}..."
cd "${TEMP_DIR}"
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -O prometheus.tar.gz
check_error "No se pudo descargar Prometheus"

print_status "Extrayendo Prometheus..."
tar xzf prometheus.tar.gz
check_error "No se pudo extraer el archivo de Prometheus"

# 3. Copiar binarios y archivos de configuración
print_status "Instalando binarios y archivos de configuración..."
cp "${TEMP_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" "/usr/local/bin/"
cp "${TEMP_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" "/usr/local/bin/"
check_error "No se pudieron copiar los binarios de Prometheus"

cp -r "${TEMP_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" ${PROMETHEUS_DIR}
cp -r "${TEMP_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" ${PROMETHEUS_DIR}
check_error "No se pudieron copiar los archivos web de Prometheus"

# 4. Crear archivo de configuración de Prometheus si no existe
if [ ! -f ${PROMETHEUS_CONFIG} ]; then
    print_status "Creando configuración de Prometheus..."
    cat > ${PROMETHEUS_CONFIG} << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - "rules/*.yml"

scrape_configs:
  # Monitoreo del propio Prometheus
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Integración con Telegraf
  - job_name: 'telegraf'
    static_configs:
      - targets: ['localhost:9273']

  # Monitoreo del sistema (node_exporter)
  - job_name: 'node'
    scrape_interval: 10s
    static_configs:
      - targets: ['localhost:9100']

  # Monitoreo de sitios web (blackbox_exporter)
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://ei.hmhospitales.com
        - https://xero.hmhospitales.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115  # Dirección del blackbox_exporter
EOF
    check_error "No se pudo crear el archivo de configuración de Prometheus"
else
    print_status "Configuración de Prometheus ya existe, no se sobreescribe"
fi

# 5. Configurar permisos
print_status "Configurando permisos..."
chown -R ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} ${PROMETHEUS_DIR}
chown -R ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} ${PROMETHEUS_DATA_DIR}
chmod -R 775 ${PROMETHEUS_DIR}
chmod -R 775 ${PROMETHEUS_DATA_DIR}
chown ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} /usr/local/bin/prometheus
chown ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} /usr/local/bin/promtool
chmod 755 /usr/local/bin/prometheus
chmod 755 /usr/local/bin/promtool
check_error "No se pudieron configurar los permisos correctamente"

# 6. Crear servicio systemd para Prometheus
print_status "Creando servicio systemd para Prometheus..."
cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_GROUP}
Type=simple
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${PROMETHEUS_CONFIG} \\
  --storage.tsdb.path=${PROMETHEUS_DATA_DIR} \\
  --web.console.templates=${PROMETHEUS_DIR}/consoles \\
  --web.console.libraries=${PROMETHEUS_DIR}/console_libraries \\
  --web.listen-address=0.0.0.0:9090 \\
  --web.enable-lifecycle

SyslogIdentifier=prometheus
Restart=always
RestartSec=5
LimitNOFILE=65535
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
check_error "No se pudo crear el servicio de Prometheus"

# 7. Instalar Blackbox Exporter para monitorización web
print_status "Instalando Blackbox Exporter v${BLACKBOX_VERSION}..."
cd "${TEMP_DIR}"
wget -q "https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64.tar.gz" -O blackbox.tar.gz
check_error "No se pudo descargar Blackbox Exporter"

print_status "Extrayendo Blackbox Exporter..."
tar xzf blackbox.tar.gz
check_error "No se pudo extraer Blackbox Exporter"

# Crear directorio para blackbox si no existe
mkdir -p /etc/blackbox_exporter
check_error "No se pudo crear el directorio para Blackbox Exporter"

# Copiar binario y configuración
cp "${TEMP_DIR}/blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64/blackbox_exporter" /usr/local/bin/
check_error "No se pudo copiar el binario de Blackbox Exporter"
chown blackbox_exporter:blackbox_exporter /usr/local/bin/blackbox_exporter
chmod 755 /usr/local/bin/blackbox_exporter

# Configuración avanzada para blackbox
print_status "Configurando Blackbox Exporter..."
cat > /etc/blackbox_exporter/blackbox.yml << EOF
modules:
  http_2xx:
    prober: http
    timeout: 15s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 301, 302, 303, 307, 308]
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"
      tls_config:
        insecure_skip_verify: true

  http_advanced:
    prober: http
    timeout: 30s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      method: GET
      headers:
        User-Agent: "BlackboxExporter/v${BLACKBOX_VERSION}"
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
      fail_if_not_ssl: false
      fail_if_ssl: false
      follow_redirects: true
      preferred_ip_protocol: "ip4"
      tls_config:
        insecure_skip_verify: true
EOF
check_error "No se pudo crear la configuración de Blackbox Exporter"

# Configurar permisos para Blackbox
chown -R blackbox_exporter:blackbox_exporter /etc/blackbox_exporter
chmod -R 775 /etc/blackbox_exporter

# Crear servicio para blackbox
print_status "Creando servicio para Blackbox Exporter..."
cat > /etc/systemd/system/blackbox_exporter.service << EOF
[Unit]
Description=Blackbox Exporter
Documentation=https://github.com/prometheus/blackbox_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=blackbox_exporter
Group=blackbox_exporter
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter \\
  --config.file=/etc/blackbox_exporter/blackbox.yml \\
  --web.listen-address=:9115

Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
check_error "No se pudo crear el servicio de Blackbox Exporter"

# 8. Instalar Node Exporter
print_status "Instalando Node Exporter v${NODE_EXPORTER_VERSION}..."
cd "${TEMP_DIR}"
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -O node_exporter.tar.gz
check_error "No se pudo descargar Node Exporter"

print_status "Extrayendo Node Exporter..."
tar xzf node_exporter.tar.gz
check_error "No se pudo extraer Node Exporter"

# Copiar el binario
cp "${TEMP_DIR}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
check_error "No se pudo copiar el binario de Node Exporter"
chown node_exporter:node_exporter /usr/local/bin/node_exporter
chmod 755 /usr/local/bin/node_exporter

# Crear servicio systemd para Node Exporter
print_status "Creando servicio para Node Exporter..."
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
  --collector.systemd \\
  --collector.processes \\
  --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+)($|/)"

Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
check_error "No se pudo crear el servicio de Node Exporter"

# 9. Configurar Telegraf para exportar métricas a Prometheus
print_status "Configurando Telegraf para Prometheus..."
if ! grep -q "prometheus_client" /etc/telegraf/telegraf.conf; then
    cat >> /etc/telegraf/telegraf.conf << EOF

# Configuración para exponer métricas en formato Prometheus
[[outputs.prometheus_client]]
  ## Dirección en la que Telegraf expondrá las métricas
  listen = ":9273"

  ## Ruta en la que se expondrán las métricas
  path = "/metrics"

  ## Exponer los campos de Telegraf como etiquetas de Prometheus
  string_as_label = true

  ## Si es true, expone todos los etiquetas de Telegraf como etiquetas de Prometheus
  export_timestamp = true
EOF
    check_error "No se pudo actualizar la configuración de Telegraf"
    print_status "Reiniciando Telegraf..."
    systemctl restart telegraf
    check_error "No se pudo reiniciar Telegraf"
else
    print_status "Telegraf ya configurado para Prometheus, no se modifica"
fi

# 10. Iniciar y habilitar servicios
print_status "Iniciando servicios..."
systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus
check_error "No se pudo iniciar el servicio de Prometheus"

systemctl enable blackbox_exporter
systemctl restart blackbox_exporter
check_error "No se pudo iniciar el servicio de Blackbox Exporter"

systemctl enable node_exporter
systemctl restart node_exporter
check_error "No se pudo iniciar el servicio de Node Exporter"

# 11. Verificar que los servicios estén funcionando
print_status "Verificando servicios..."
sleep 2

if systemctl is-active --quiet prometheus; then
    print_success "Prometheus está activo y funcionando"
else
    print_warning "Prometheus no se inició correctamente. Verifica los logs con: journalctl -u prometheus"
fi

if systemctl is-active --quiet blackbox_exporter; then
    print_success "Blackbox Exporter está activo y funcionando"
else
    print_warning "Blackbox Exporter no se inició correctamente. Verifica los logs con: journalctl -u blackbox_exporter"
fi

if systemctl is-active --quiet node_exporter; then
    print_success "Node Exporter está activo y funcionando"
else
    print_warning "Node Exporter no se inició correctamente. Verifica los logs con: journalctl -u node_exporter"
fi

# 12. Instrucciones finales
print_success "Instalación completada con éxito!"
print_status "Prometheus está ejecutándose en: http://localhost:9090"
print_status "Blackbox Exporter está ejecutándose en: http://localhost:9115"
print_status "Node Exporter está ejecutándose en: http://localhost:9100"
print_status ""
print_status "Para configurar Prometheus en Grafana:"
print_status "1. Accede a Grafana en http://localhost:3000"
print_status "2. Ve a Configuración > Data sources > Add data source"
print_status "3. Selecciona Prometheus"
print_status "4. Configura URL como http://localhost:9090"
print_status "5. Haz clic en Save & Test"
print_status ""
print_status "Dashboards recomendados para importar en Grafana:"
print_status "- ID 7587: Blackbox Exporter (monitorización web)"
print_status "- ID 1860: Node Exporter Full (métricas del sistema)"
print_status "- ID 17784: Telegraf System Dashboard"
print_status ""
print_warning "Recuerda ajustar la configuración de firewalls si es necesario:"
print_status "sudo ufw allow 9090/tcp # Prometheus"
print_status "sudo ufw allow 9115/tcp # Blackbox Exporter"
print_status "sudo ufw allow 9100/tcp # Node Exporter"
print_status "sudo ufw allow 9273/tcp # Telegraf Prometheus Output"

exit 0
