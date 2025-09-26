# Telegraf

Herramientas de automatización para generar configuraciones de Telegraf en entornos de monitorización.

## Scripts

### `telegraf_http_icmp_manager.py`
- **Funcionalidad:** administra ficheros `http_monitoring.conf` e `icmp_monitoring.conf` para un despliegue Docker. Normaliza URLs, resuelve dominios a IPs, crea bloques de entrada y ajusta permisos dentro del contenedor.
- **Precisión:** valida sintaxis de URLs/IP, detecta configuraciones existentes y evita duplicados. Requiere acceso al socket Docker para ejecutar `docker exec` cuando es necesario recargar Telegraf.
- **Complejidad:** alta; maneja logging estructurado, prompts interactivos, gestión de permisos y sincronización con contenedores.
- **Manual de uso:**
  1. Instalar dependencias (`python3 -m pip install -r requirements.txt` si aplica).
  2. Ejecutar `python3 telegraf_http_icmp_manager.py --help` para ver las opciones (añadir, eliminar, listar).
  3. Introducir las URLs a monitorizar; el script genera tanto la comprobación HTTP como el ping a la IP resuelta.
  4. Recargar el servicio Telegraf al finalizar.

### `telegraf_snmp_agent_basic_manager.py`
- **Funcionalidad:** asistente sencillo para crear archivos de entrada SNMP basados en una plantilla TOML. Detecta sedes en `/etc/telegraf/telegraf.d`, valida IPs y obtiene el hostname mediante SNMP `get`.
- **Precisión:** utiliza comunidad `public` para descubrir nombres; se recomienda editarla según el entorno. No gestiona permisos especiales.
- **Complejidad:** media.
- **Manual de uso:**
  1. Ejecutar `python3 telegraf_snmp_agent_basic_manager.py` y seguir el menú interactivo.
  2. Seleccionar la sede, introducir la IP y confirmar la creación del archivo.
  3. Revisar el fichero generado y recargar Telegraf.

### `telegraf_snmp_full_manager.py`
- **Funcionalidad:** versión avanzada con logging configurable, soporte de archivos INI, sanitización de nombres, gestión de permisos (`chown` al usuario `telegraf`) y utilidades para consultar MIBs vía `pysnmp`.
- **Precisión:** requiere dependencias `psutil` y `pysnmp`, además de que el usuario `telegraf` exista. Permite personalizar comunidad, tiempo de sondeo y si se incluye la IP en el alias.
- **Complejidad:** alta; incorpora detección de procesos, validaciones múltiples y manejo de señales.
- **Manual de uso:**
  1. Crear un archivo de configuración opcional (`/etc/telegraf/manager.ini`) para ajustar parámetros.
  2. Ejecutar `python3 telegraf_snmp_full_manager.py add --ip <IP>` (consultar `--help` para subcomandos disponibles).
  3. Confirmar los datos detectados y permitir que el script cree los ficheros bajo `telegraf.d/` con permisos correctos.

### `telegraf_snmp_config_generator.py`
- **Funcionalidad:** genera configuraciones SNMP masivas a partir de CSV o datos estructurados, soporta plantillas múltiples y utiliza `pysnmp` para validar conectividad.
- **Precisión:** valida direcciones IP, nombres y tipos de dispositivo; escribe archivos por sede/cliente.
- **Complejidad:** media-alta, pensada para operaciones batch.
- **Manual de uso:**
  1. Preparar la fuente de datos (CSV o parámetros CLI según las opciones disponibles con `--help`).
  2. Ejecutar el script y revisar los archivos producidos en el directorio destino.
  3. Recargar o reiniciar Telegraf para aplicar los cambios.
