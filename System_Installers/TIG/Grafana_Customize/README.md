# Manual de Personalización de la Página de Inicio de Sesión de Grafana

Este manual proporciona una guía paso a paso para personalizar la página de inicio de sesión de Grafana. A través de instrucciones claras y comandos específicos, podrás modificar elementos clave como el footer, el logo, el favicon, el texto de bienvenida y el fondo. Al final del manual, encontrarás un script automatizado que realiza todas estas personalizaciones de manera eficiente.

---

## **Índice**

1. [Requisitos Previos](#1-requisitos-previos)
2. [Pasos de Personalización Manual](#2-pasos-de-personalización-manual)
   - [2.1. Crear Copias de Seguridad](#21-crear-copias-de-seguridad)
   - [2.2. Reemplazar Logos](#22-reemplazar-logos)
   - [2.3. Reemplazar el Favicon](#23-reemplazar-el-favicon)
   - [2.4. Copiar Imagen de Fondo](#24-copiar-imagen-de-fondo)
   - [2.5. Modificar el Archivo JavaScript de Login](#25-modificar-el-archivo-javascript-de-login)
   - [2.6. Modificar el Archivo CSS](#26-modificar-el-archivo-css)
   - [2.7. Reiniciar el Servicio de Grafana](#27-reiniciar-el-servicio-de-grafana)
3. [Script Automatizado de Personalización](#3-script-automatizado-de-personalización)
4. [Verificación de Cambios](#4-verificación-de-cambios)
5. [Notas Finales](#5-notas-finales)

---

## **1. Requisitos Previos**

Antes de comenzar con la personalización, asegúrate de cumplir con los siguientes requisitos:

- **Acceso al Servidor**: Debes tener acceso al servidor donde está instalado Grafana.
- **Permisos de Administrador**: Necesitas permisos de superusuario (root) para modificar archivos en el directorio de instalación de Grafana.
- **Herramientas Necesarias**:
  - Editor de texto (como `nano` o `vim`).
  - Terminal de comandos con acceso SSH al servidor.
- **Archivos Personalizados**: Asegúrate de tener preparados los archivos personalizados que reemplazarán los predeterminados:
  - `trc_files/logo_trc.svg` – Logo personalizado en formato SVG.
  - `trc_files/favicon.ico` – Favicon personalizado en formato ICO.
  - `trc_files/fondo.png` – Imagen de fondo personalizada en formato PNG.

---

## **2. Pasos de Personalización Manual**

A continuación, se detallan los pasos para personalizar manualmente la página de inicio de sesión de Grafana. Cada sección incluye los comandos necesarios que puedes copiar y ejecutar en tu terminal.

### **2.1. Crear Copias de Seguridad**

Es fundamental crear copias de seguridad de los archivos que serán modificados para poder restaurarlos en caso de ser necesario.

```bash
# Directorio de instalación de Grafana
GRAFANA_DIR="/usr/share/grafana"

# Directorio temporal para copias de seguridad con fecha y hora
BACKUP_DIR="$GRAFANA_DIR/backup_$(date +%F_%T)"
sudo mkdir -p "$BACKUP_DIR"

# Crear copias de seguridad de los logos y favicon
sudo cp "$GRAFANA_DIR/public/img/grafana_icon.svg" "$BACKUP_DIR/"
sudo cp "$GRAFANA_DIR/public/img/grafana_com_auth_icon.svg" "$BACKUP_DIR/"
sudo cp "$GRAFANA_DIR/public/img/fav32.png" "$BACKUP_DIR/"
sudo cp "$GRAFANA_DIR/public/img/g8_login_dark.svg" "$BACKUP_DIR/"

# Identificar los archivos JavaScript y CSS a modificar
LOGIN_JS_FILE=$(sudo find "$GRAFANA_DIR/public/build/" -type f -name '322.*.js' -print -quit)
CSS_FILE=$(sudo find "$GRAFANA_DIR/public/build/" -type f -name 'grafana.dark.*.css' -print -quit)

# Verificar la existencia de los archivos
if [[ ! -f "$LOGIN_JS_FILE" ]]; then
    echo "Error: Archivo JavaScript de login no encontrado."
    exit 1
fi

if [[ ! -f "$CSS_FILE" ]]; then
    echo "Error: Archivo CSS no encontrado."
    exit 1
fi

# Crear copias de seguridad de los archivos JavaScript y CSS
sudo cp "$LOGIN_JS_FILE" "$BACKUP_DIR/$(basename "$LOGIN_JS_FILE").bak"
sudo cp "$CSS_FILE" "$BACKUP_DIR/$(basename "$CSS_FILE").bak"

echo "Copias de seguridad creadas en $BACKUP_DIR."
```

### **2.2. Reemplazar Logos**

Sustituye los logos predeterminados de Grafana por tus logos personalizados.

```bash
# Directorios de origen y destino para los logos
LOGO_SRC="trc_files/logo_trc.svg"
LOGO_DST1="$GRAFANA_DIR/public/img/grafana_icon.svg"
LOGO_DST2="$GRAFANA_DIR/public/img/grafana_com_auth_icon.svg"

# Reemplazar los logos
sudo cp "$LOGO_SRC" "$LOGO_DST1"
sudo cp "$LOGO_SRC" "$LOGO_DST2"

echo "Logos reemplazados exitosamente."
```

### **2.3. Reemplazar el Favicon**

Actualiza el favicon de Grafana con tu favicon personalizado.

```bash
# Directorios de origen y destino para el favicon
FAVICON_SRC="trc_files/favicon.ico"
FAVICON_DST="$GRAFANA_DIR/public/img/fav32.png"

# Reemplazar el favicon
sudo cp "$FAVICON_SRC" "$FAVICON_DST"

echo "Favicon reemplazado exitosamente."
```

### **2.4. Copiar Imagen de Fondo**

Copia tu imagen de fondo personalizada al directorio de Grafana.

```bash
# Directorios de origen y destino para la imagen de fondo
BACKGROUND_SRC="trc_files/fondo.png"
BACKGROUND_DST="$GRAFANA_DIR/public/img/fondo.png"

# Copiar la imagen de fondo
sudo cp "$BACKGROUND_SRC" "$BACKGROUND_DST"

echo "Imagen de fondo copiada exitosamente."
```

### **2.5. Modificar el Archivo JavaScript de Login**

Realiza modificaciones en el archivo JavaScript encargado del login para eliminar enlaces del footer, ocultar información de versión, cambiar el título de la página y actualizar el texto de bienvenida.

```bash
# Variables para los archivos JavaScript y CSS
LOGIN_JS_FILE=$(sudo find "$GRAFANA_DIR/public/build/" -type f -name '322.*.js' -print -quit)

# Eliminar enlaces del footer
sudo sed -i 's|let l=()=>\[{target:"_blank",id:"documentation",text:(0,i.t)("nav.help/documentation","Documentation"),icon:"document-info",url:"https://grafana.com/docs/grafana/latest/\?utm_source=grafana_footer"},{target:"_blank",id:"support",text:(0,i.t)("nav.help/support","Support"),icon:"question-circle",url:"https://grafana.com/products/enterprise/\?utm_source=grafana_footer"},{target:"_blank",id:"community",text:(0,i.t)("nav.help/community","Community"),icon:"comments-alt",url:"https://community.grafana.com/\?utm_source=grafana_footer"}\];|let l=()=>[{target:"",id:"",text:"",icon:"",url:""}];|' "$LOGIN_JS_FILE"

# Ocultar información de versión
sudo sed -i 's|function o(m){const{buildInfo:f,licenseInfo:y}=s\.$,P=\[\],v=y\.stateInfo\?` \(${y\.stateInfo}\)`:"";if(m\|\|P\.push\({target:"_blank",id:"license",text:`${f\.edition}${v}`,url:y\.licenseUrl}\),f\.hideVersion)return P;const{hasReleaseNotes:D}=d\(f\.version\);return P\.push\({target:"_blank",id:"version",text:f\.versionString,url:D\?"https://github.com/grafana/grafana/blob/main/CHANGELOG.md":void 0}\),f\.hasUpdate&&P\.push\({target:"_blank",id:"updateVersion",text:"New version available!",icon:"download-alt",url:"https://grafana.com/grafana/download\?utm_source=grafana_footer"}\),P}|function o(m){return [{target:"",id:"",text:"",icon:"",url:""}];}|' "$LOGIN_JS_FILE"

# Modificar el título del HTML
sudo sed -i '1i\new MutationObserver(() => { if (document.title !== "Mnet") document.title = "Mnet"; }).observe(document.querySelector("title"), { childList: true });' "$LOGIN_JS_FILE"

# Reemplazar el texto de bienvenida
sudo sed -i 's|static{this.LoginTitle="Welcome to Grafana"}|static{this.LoginTitle="Bienvenido a TRC"}|' "$LOGIN_JS_FILE"

# Modificar la referencia al fondo
sudo sed -iE 's|g8_login_[^)]*|fondo.png|g' "$LOGIN_JS_FILE"

echo "Archivo JavaScript de login modificado exitosamente."
```

### **2.6. Modificar el Archivo CSS**

Añade reglas CSS para ocultar visualmente el footer.

```bash
# Variable para el archivo CSS
CSS_FILE=$(sudo find "$GRAFANA_DIR/public/build/" -type f -name 'grafana.dark.*.css' -print -quit)

# Añadir la regla CSS para ocultar el footer
echo ".css-uhhimz{display:none!important;visibility:hidden!important;opacity:0!important;width:0!important;height:0!important;overflow:hidden!important;position:absolute!important;top:-9999px!important;left:-9999px!important;}" | sudo tee -a "$CSS_FILE" > /dev/null

echo "Archivo CSS modificado exitosamente para ocultar el footer."
```

### **2.7. Reiniciar el Servicio de Grafana**

Para aplicar los cambios, es necesario reiniciar el servicio de Grafana.

```bash
sudo systemctl restart grafana-server

echo "Servicio de Grafana reiniciado exitosamente."
```

---

## **3. Script Automatizado de Personalización**

Para simplificar el proceso de personalización, puedes utilizar el siguiente script. Este script realiza todas las modificaciones mencionadas anteriormente de manera automatizada.

### **Script Completo: `customizar_grafana.sh`**

```bash
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
```

### **Cómo Utilizar el Script**

1. **Crear el Archivo del Script**

   Abre tu terminal y crea un nuevo archivo para el script:

   ```bash
   sudo nano /usr/local/bin/customizar_grafana.sh
   ```

2. **Pegar el Contenido del Script**

   Copia y pega el contenido del script proporcionado anteriormente en el archivo abierto.

3. **Guardar y Cerrar el Archivo**

   - En `nano`, presiona `CTRL + O` para guardar y `CTRL + X` para salir.

4. **Asignar Permisos de Ejecución**

   Otorga permisos de ejecución al script:

   ```bash
   sudo chmod +x /usr/local/bin/customizar_grafana.sh
   ```

5. **Ejecutar el Script**

   Ejecuta el script para iniciar el proceso de personalización:

   ```bash
   sudo /usr/local/bin/customizar_grafana.sh
   ```

   **Nota**: Es recomendable ejecutar el script durante un periodo de mantenimiento o cuando el impacto en los usuarios sea mínimo, ya que el reinicio de Grafana puede afectar temporalmente el acceso.

---

## **4. Verificación de Cambios**

Después de completar la personalización, es importante verificar que todos los cambios se hayan aplicado correctamente.

1. **Acceder a la Página de Inicio de Sesión**

   Abre tu navegador web y dirígete a la URL de Grafana (por ejemplo, `http://tu-servidor-grafana:3000`).

2. **Verificar los Elementos Personalizados**

   - **Logo**: Asegúrate de que el logo personalizado (`logo_trc.svg`) se muestre correctamente en la página de inicio de sesión.
   - **Favicon**: Verifica que el favicon personalizado aparezca en la pestaña del navegador.
   - **Texto de Bienvenida**: Comprueba que el texto de bienvenida haya cambiado a "Bienvenido a TRC".
   - **Fondo**: Confirma que la imagen de fondo personalizada (`fondo.png`) se muestre correctamente.
   - **Footer**: Verifica que los enlaces del footer hayan sido eliminados y que la información de la versión esté oculta.

3. **Limpiar la Caché del Navegador**

   Si no observas los cambios, limpia la caché de tu navegador o intenta acceder en una ventana de incógnito.

---

## **5. Notas Finales**

- **Copias de Seguridad**: Todas las copias de seguridad de los archivos originales se encuentran en el directorio de respaldo creado dentro del directorio de instalación de Grafana (por ejemplo, `/usr/share/grafana/backup_2024-04-27_15:30:00/`). Puedes restaurar los archivos originales si es necesario.

- **Actualizaciones de Grafana**: Ten en cuenta que futuras actualizaciones de Grafana pueden sobrescribir los archivos modificados. Después de una actualización, es posible que necesites re-ejecutar el script o volver a aplicar las personalizaciones manualmente.

- **Seguridad**: Asegúrate de que los archivos personalizados (logos, favicon, fondo) sean seguros y no contengan contenido malicioso.

- **Compatibilidad**: Verifica que las modificaciones sean compatibles con la versión específica de Grafana que estás utilizando. Las rutas y nombres de archivos pueden variar según la versión.

- **Responsabilidad**: Realiza estas modificaciones bajo tu propia responsabilidad. Asegúrate de cumplir con las licencias y términos de uso de Grafana y de cualquier imagen o recurso que utilices.

---

¡Con estos pasos, habrás personalizado exitosamente la página de inicio de sesión de Grafana según tus necesidades!
