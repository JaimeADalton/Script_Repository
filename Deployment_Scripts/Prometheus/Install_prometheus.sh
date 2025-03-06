#!/bin/bash

# Script de instalación de Prometheus para Ubuntu 24.04
# Para ser ejecutado en un sistema con Grafana y Telegraf ya instalados

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

# Verificar que se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root o con sudo"
fi

print_status "Iniciando instalación de Prometheus en Ubuntu 24.04..."

# Variables de configuración (puedes ajustarlas según tus necesidades)
PROMETHEUS_VERSION="3.2.1"
BLACKBOX_VERSION="0.26.0"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
PROMETHEUS_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_CONFIG="${PROMETHEUS_DIR}/prometheus.yml"

# 1. Crear usuario y directorios para Prometheus
print_status "Creando usuario y directorios para Prometheus..."
useradd --no-create-home --shell /bin/false ${PROMETHEUS_USER} 2>/dev/null || true

mkdir -p ${PROMETHEUS_DIR}
mkdir -p ${PROMETHEUS_DATA_DIR}
mkdir -p ${PROMETHEUS_DIR}/rules
mkdir -p ${PROMETHEUS_DIR}/file_sd

# 2. Descargar y extraer Prometheus
print_status "Descargando Prometheus v${PROMETHEUS_VERSION}..."
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz -O prometheus.tar.gz || print_error "No se pudo descargar Prometheus"
tar xzf prometheus.tar.gz
cd prometheus-${PROMETHEUS_VERSION}.linux-amd64

# 3. Copiar binarios y archivos de configuración
print_status "Instalando binarios y archivos de configuración..."
cp prometheus promtool /usr/local/bin/
cp -r consoles console_libraries ${PROMETHEUS_DIR}
if [ ! -f ${PROMETHEUS_CONFIG} ]; then
    cp prometheus.yml ${PROMETHEUS_CONFIG}
fi

# 4. Configurar permisos
print_status "Configurando permisos..."
chown -R ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} ${PROMETHEUS_DIR}
chown -R ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} ${PROMETHEUS_DATA_DIR}
chown ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} /usr/local/bin/prometheus
chown ${PROMETHEUS_USER}:${PROMETHEUS_GROUP} /usr/local/bin/promtool

# 5. Crear archivo de configuración de Prometheus para monitorización web
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

  # Monitoreo del sistema (si se instala node_exporter)
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # Monitoreo de sitios web (requiere blackbox_exporter)
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

[Install]
WantedBy=multi-user.target
EOF

# 7. Instalar Blackbox Exporter para monitorización web
print_status "Instalando Blackbox Exporter para monitorización web..."
cd /tmp
wget -q https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64.tar.gz -O blackbox.tar.gz || print_error "No se pudo descargar Blackbox Exporter"
tar xzf blackbox.tar.gz
cd blackbox_exporter-${BLACKBOX_VERSION}.linux-amd64

# Crear usuario y directorio para blackbox
useradd --no-create-home --shell /bin/false blackbox_exporter 2>/dev/null || true
mkdir -p /etc/blackbox_exporter

# Copiar binario y configuración
cp blackbox_exporter /usr/local/bin/
chown blackbox_exporter:blackbox_exporter /usr/local/bin/blackbox_exporter

# Configuración avanzada para blackbox
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

chown -R blackbox_exporter:blackbox_exporter /etc/blackbox_exporter

# Crear servicio para blackbox
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

[Install]
WantedBy=multi-user.target
EOF

# 8. Iniciar y habilitar servicios
print_status "Iniciando servicios..."
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
systemctl enable blackbox_exporter
systemctl start blackbox_exporter

# 9. Limpiar archivos temporales
print_status "Limpiando archivos temporales..."
cd /tmp
rm -rf prometheus* blackbox*

# 10. Instrucciones para configurar Grafana
print_success "Instalación completada con éxito!"
print_status "Prometheus está ejecutándose en: http://localhost:9090"
print_status "Blackbox Exporter está ejecutándose en: http://localhost:9115"
print_status ""
print_status "Para configurar Prometheus en Grafana:"
print_status "1. Accede a Grafana en http://localhost:3000"
print_status "2. Ve a Configuración > Data sources > Add data source"
print_status "3. Selecciona Prometheus"
print_status "4. Configura URL como http://localhost:9090"
print_status "5. Haz clic en Save & Test"
print_status ""
print_status "Para importar dashboards útiles en Grafana:"
print_status "- ID 7587: Blackbox Exporter"
print_status "- ID 1860: Node Exporter (si lo instalas)"
print_status ""
print_warning "Recuerda ajustar la configuración de firewalls si es necesario"

exit 0
