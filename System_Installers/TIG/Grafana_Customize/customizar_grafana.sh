#!/bin/bash

# Script para personalizar la página de inicio de sesión de Grafana

# Salir inmediatamente si ocurre un error
set -e

# Directorio de instalación de Grafana
GRAFANA_DIR="/usr/share/grafana"

# Directorio temporal para copias de seguridad
BACKUP_DIR="$GRAFANA_DIR/backup_$(date +%F_%T)"
mkdir -p "$BACKUP_DIR"

# Archivos de origen personalizados
LOGO_SRC="trc_files/logo_trc.svg"
FAVICON_SRC="trc_files/favicon.ico"
BACKGROUND_SRC="trc_files/fondo.png"

# Archivos de destino
LOGO_DST1="$GRAFANA_DIR/public/img/grafana_icon.svg"
LOGO_DST2="$GRAFANA_DIR/public/img/grafana_com_auth_icon.svg"
FAVICON_DST="$GRAFANA_DIR/public/img/fav32.png"
BACKGROUND_DST="$GRAFANA_DIR/public/img/fondo.png"

# Archivo JavaScript de login a modificar (ajusta el patrón según la versión)
LOGIN_JS_FILE=$(find "$GRAFANA_DIR/public/build/" -type f -name '322.*.js' -print -quit)

# Archivo CSS a modificar (ajusta el patrón según la versión)
CSS_FILE=$(find "$GRAFANA_DIR/public/build/" -type f -name 'grafana.dark.*.css' -print -quit)

# Verificar que los archivos existen
if [[ ! -f "$LOGIN_JS_FILE" ]]; then
    echo "Error: Archivo JavaScript de login no encontrado."
    exit 1
fi

if [[ ! -f "$CSS_FILE" ]]; then
    echo "Error: Archivo CSS no encontrado."
    exit 1
fi

# 1. Reemplazar logos
echo "Reemplazando logos..."
cp "$LOGO_DST1" "$BACKUP_DIR/"
cp "$LOGO_DST2" "$BACKUP_DIR/"
cp "$LOGO_SRC" "$LOGO_DST1"
cp "$LOGO_SRC" "$LOGO_DST2"

# 2. Reemplazar favicon
echo "Reemplazando favicon..."
cp "$FAVICON_DST" "$BACKUP_DIR/"
cp "$FAVICON_SRC" "$FAVICON_DST"

# 3. Copiar imagen de fondo
echo "Copiando imagen de fondo..."
cp "$BACKGROUND_SRC" "$BACKGROUND_DST"

# 4. Modificar archivo JavaScript de login
echo "Modificando archivo JavaScript de login..."
cp "$LOGIN_JS_FILE" "$BACKUP_DIR/$(basename "$LOGIN_JS_FILE").bak"

# Reemplazar líneas exactas

# Reemplazar línea para eliminar los enlaces del footer
sed -i 's|let l=()=>\[{target:"_blank",id:"documentation",text:(0,i.t)("nav.help/documentation","Documentation"),icon:"document-info",url:"https://grafana.com/docs/grafana/latest/\?utm_source=grafana_footer"},{target:"_blank",id:"support",text:(0,i.t)("nav.help/support","Support"),icon:"question-circle",url:"https://grafana.com/products/enterprise/\?utm_source=grafana_footer"},{target:"_blank",id:"community",text:(0,i.t)("nav.help/community","Community"),icon:"comments-alt",url:"https://community.grafana.com/\?utm_source=grafana_footer"}\];|let l=()=>[{target:"",id:"",text:"",icon:"",url:""}];|' "$LOGIN_JS_FILE"

# Reemplazar la función para deshabilitar la información de la versión
sed -i 's|function o(m){const{buildInfo:f,licenseInfo:y}=s\.$,P=\[\],v=y\.stateInfo\?` \(${y\.stateInfo}\)`:"";if(m\|\|P\.push\({target:"_blank",id:"license",text:`${f\.edition}${v}`,url:y\.licenseUrl}\),f\.hideVersion)return P;const{hasReleaseNotes:D}=d\(f\.version\);return P\.push\({target:"_blank",id:"version",text:f\.versionString,url:D\?"https://github.com/grafana/grafana/blob/main/CHANGELOG.md":void 0}\),f\.hasUpdate&&P\.push\({target:"_blank",id:"updateVersion",text:"New version available!",icon:"download-alt",url:"https://grafana.com/grafana/download\?utm_source=grafana_footer"}\),P}|function o(m){return [{target:"",id:"",text:"",icon:"",url:""}];}|' "$LOGIN_JS_FILE"

# Añadir la línea para modificar el título del HTML al inicio del archivo
sed -i '1i\new MutationObserver(() => { if (document.title !== "Mnet") document.title = "Mnet"; }).observe(document.querySelector("title"), { childList: true });' "$LOGIN_JS_FILE"

# Reemplazar el texto de bienvenida
sed -i 's|static{this.LoginTitle="Welcome to Grafana"}|static{this.LoginTitle="Bienvenido a TRC"}|' "$LOGIN_JS_FILE"

# Modificar la referencia al fondo
sed -iE 's|g8_login_[^)]*|fondo.png|g' "$LOGIN_JS_FILE"

# 5. Modificar archivo CSS
echo "Modificando archivo CSS para ocultar el footer..."
cp "$CSS_FILE" "$BACKUP_DIR/$(basename "$CSS_FILE").bak"

# Añadir la regla CSS en una sola línea
echo ".css-uhhimz{display:none!important;visibility:hidden!important;opacity:0!important;width:0!important;height:0!important;overflow:hidden!important;position:absolute!important;top:-9999px!important;left:-9999px!important;}" >> "$CSS_FILE"

# 6. Reiniciar Grafana
echo "Reiniciando el servicio de Grafana..."
sudo systemctl restart grafana-server

echo "Personalización completada. Se han creado copias de seguridad en $BACKUP_DIR."
