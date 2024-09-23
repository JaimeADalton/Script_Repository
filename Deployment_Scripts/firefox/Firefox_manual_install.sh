#!/bin/bash

# Comprobar si se está ejecutando como root
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ser ejecutado como root"
   exit 1
fi

# Definir variables
DOWNLOAD_URL="https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=es-ES"
DOWNLOAD_DIR="/tmp"
INSTALL_DIR="/opt/firefox"
DESKTOP_FILE="/usr/share/applications/firefox.desktop"
ICON_PATH="$INSTALL_DIR/browser/chrome/icons/default/default128.png"

# Cambiar al directorio de descargas temporal
cd "$DOWNLOAD_DIR" || exit 1

# Descargar Firefox
echo "Descargando Firefox..."
wget -O firefox.tar.bz2 "$DOWNLOAD_URL"

# Extraer el archivo descargado
echo "Extrayendo el contenido..."
tar xjf firefox.tar.bz2

# Mover la carpeta extraída al directorio de instalación en /opt
if [ -d "$INSTALL_DIR" ]; then
  echo "Eliminando la versión anterior de Firefox..."
  rm -rf "$INSTALL_DIR"
fi
mv firefox "$INSTALL_DIR"

# Eliminar el archivo descargado
echo "Eliminando el archivo de descarga..."
rm firefox.tar.bz2

# Crear un archivo .desktop para el acceso directo en /usr/share/applications
echo "Creando acceso directo en /usr/share/applications..."
cat > "$DESKTOP_FILE" <<EOL
[Desktop Entry]
Name=Firefox
Comment=Navegador web Mozilla Firefox
Exec=$INSTALL_DIR/firefox
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOL

# Dar permisos de ejecución al acceso directo
chmod +x "$DESKTOP_FILE"

echo "Instalación completada. Puedes ejecutar Firefox desde el menú de aplicaciones."
