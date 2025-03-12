#!/bin/bash
# Script de instalación de MTR Topology Visualizer

# Colores para mensajes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directorio de instalación
INSTALL_DIR="/opt/mtr-topology"
SERVICE_NAME="mtr-topology"
SOURCE_DIR="$(dirname "$(readlink -f "$0")")"

# Función para mostrar mensajes
print_message() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

# Verificar permisos de root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

print_message "Instalando MTR Topology Visualizer..."

# Verificar dependencias
print_warning "Verificando dependencias..."

# Paquetes necesarios
PACKAGES=(
    "python3"
    "python3-pip"
    "python3-venv"
    "wget"
    "mtr"   # Aseguramos que MTR esté instalado
)

# Verificar e instalar paquetes necesarios
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q $pkg; then
        print_warning "Instalando $pkg..."
        apt-get update
        apt-get install -y $pkg
    else
        print_message "$pkg ya está instalado"
    fi
done

# Verificar si ya existe una instalación previa
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Se ha detectado una instalación previa en $INSTALL_DIR"
    read -p "¿Desea sobrescribirla? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_message "Instalación cancelada."
        exit 0
    fi
    # Detener el servicio existente si está activo
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_warning "Deteniendo servicio existente..."
        systemctl stop $SERVICE_NAME
    fi
fi

# Crear directorio de instalación
print_warning "Creando directorios..."
mkdir -p $INSTALL_DIR
mkdir -p $INSTALL_DIR/core
mkdir -p $INSTALL_DIR/web
mkdir -p $INSTALL_DIR/web/static/js
mkdir -p $INSTALL_DIR/web/static/css
mkdir -p $INSTALL_DIR/web/templates

# Crear entorno virtual
print_warning "Creando entorno virtual Python..."
python3 -m venv $INSTALL_DIR/venv

# Instalar dependencias Python
print_warning "Instalando dependencias Python..."
$INSTALL_DIR/venv/bin/pip install flask requests influxdb uwsgi

# Descargar D3.js
print_warning "Descargando D3.js..."
wget -q https://d3js.org/d3.v7.min.js -O $INSTALL_DIR/web/static/js/d3.v7.min.js

# Copiar archivos de código fuente
print_warning "Copiando archivos de código fuente..."

# Copiar archivos principales
cp "$SOURCE_DIR/main.py" $INSTALL_DIR/
chmod +x $INSTALL_DIR/main.py

# Copiar módulos core
cp "$SOURCE_DIR/core/icmp.py" $INSTALL_DIR/core/
cp "$SOURCE_DIR/core/mtr.py" $INSTALL_DIR/core/
cp "$SOURCE_DIR/core/storage.py" $INSTALL_DIR/core/
touch $INSTALL_DIR/core/__init__.py

# Copiar módulos web
cp "$SOURCE_DIR/web/app.py" $INSTALL_DIR/web/
cp -r "$SOURCE_DIR/web/static/css/"* $INSTALL_DIR/web/static/css/
cp -r "$SOURCE_DIR/web/static/js/"* $INSTALL_DIR/web/static/js/
cp -r "$SOURCE_DIR/web/templates/"* $INSTALL_DIR/web/templates/
touch $INSTALL_DIR/web/__init__.py

# Crear servicio systemd
print_warning "Configurando servicio..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=MTR Topology Visualizer
After=network.target

[Service]
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/main.py
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configurar archivo uwsgi para producción
print_warning "Configurando uwsgi para producción..."
cat > "$INSTALL_DIR/uwsgi.ini" << EOF
[uwsgi]
module = web.app:app
master = true
processes = 5

socket = mtr-topology.sock
chmod-socket = 660
vacuum = true

die-on-term = true
EOF

# Recargar systemd
systemctl daemon-reload

# Habilitar e iniciar el servicio
print_warning "Iniciando servicio..."
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Verificar que el servicio se haya iniciado correctamente
if systemctl is-active --quiet $SERVICE_NAME; then
    print_message "El servicio se ha iniciado correctamente."
else
    print_error "Error al iniciar el servicio. Consulte los logs para más detalles:"
    print_error "journalctl -u $SERVICE_NAME -n 20"
fi

print_message "Instalación completada."
print_message "El visualizador está disponible en: http://[IP-SERVER]:8088"
echo ""
print_message "Para ver el estado del servicio: systemctl status $SERVICE_NAME"
print_message "Para ver logs: journalctl -u $SERVICE_NAME -f"
print_message "Para iniciar/detener manualmente: systemctl start/stop $SERVICE_NAME"
