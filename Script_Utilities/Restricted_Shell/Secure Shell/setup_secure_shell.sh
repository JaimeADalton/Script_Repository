#!/bin/bash

# Verificar si se está ejecutando como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script debe ser ejecutado como root" 1>&2
   exit 1
fi

# Configurar variables
CHROOT_DIR="/home/secureshell/chroot"
SECURE_USER="secureshell"
SECURE_SHELL="/usr/bin/secure_shell"
CONFIG_FILE="/etc/secure_shell.conf"
LOG_FILE="/var/log/secure_shell.log"

# Instalar dependencias
echo "Instalando dependencias..."
apt-get update
apt-get install -y build-essential libboost-all-dev libcap-dev debootstrap libfmt-dev libspdlog-dev

# Crear usuario si no existe
if ! id "$SECURE_USER" &>/dev/null; then
    useradd -m -s "$SECURE_SHELL" "$SECURE_USER"
    echo "Usuario $SECURE_USER creado."
else
    usermod -s "$SECURE_SHELL" "$SECURE_USER"
    echo "Shell de $SECURE_USER actualizada."
fi

# Crear directorio chroot
mkdir -p "$CHROOT_DIR"

# Configurar entorno chroot
#echo "Configurando entorno chroot..."
#debootstrap --variant=minbase stable "$CHROOT_DIR"

# Compilar la shell segura
echo "Compilando la shell segura..."
g++ -std=c++11 secure_shell.cpp -o "$SECURE_SHELL" -lboost_system -lboost_filesystem -lboost_program_options -lcap -lfmt -lspdlog

# Configurar permisos y capacidades
chown root:root "$SECURE_SHELL"
chmod 755 "$SECURE_SHELL"
setcap cap_net_raw,cap_net_admin+ep "$SECURE_SHELL"

# Crear archivo de configuración
cat > "$CONFIG_FILE" <<EOL
[Settings]
MaxArgs = 10
MaxArgLength = 100
CommandTimeout = 30
ChrootDir = $CHROOT_DIR
LogFile = $LOG_FILE
LogRotateSize = 1048576
EOL

# Configurar logging
touch "$LOG_FILE"
chown "$SECURE_USER:$SECURE_USER" "$LOG_FILE"

# Copiar binarios necesarios al chroot
mkdir -p "$CHROOT_DIR/bin" "$CHROOT_DIR/lib" "$CHROOT_DIR/lib64"
cp /bin/ping /bin/tracepath /usr/bin/ssh "$CHROOT_DIR/bin/"

# Copiar bibliotecas necesarias
ldd "$CHROOT_DIR/bin/"* | grep -v dynamic | awk '{print $3}' | sort | uniq | xargs -I '{}' cp -v '{}' "$CHROOT_DIR/lib/"

# Configurar resolución DNS en chroot
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

echo "Configuración completada."
echo "La shell segura está instalada en $SECURE_SHELL"
echo "El usuario $SECURE_USER puede iniciar sesión usando esta shell."
echo "Asegúrese de reiniciar el sistema o cerrar sesión y volver a iniciar para que los cambios surtan efecto."
