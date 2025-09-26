# Nagios

Este árbol reúne asistentes para automatizar la incorporación de hosts y los conjuntos de configuración base empleados por Nagios Core.

## Scripts

### `add_host_csv.sh`
- **Funcionalidad:** importa hosts desde un `hosts.csv`, genera definiciones `define host` y `define service` y mantiene actualizadas las pertenencias a `hostgroups` dentro del fichero principal de objetos.
- **Precisión y alcance:** confía en la existencia del CSV y en nombres de grupos válidos. Usa `awk` y copias temporales para evitar corrupción, pero no valida que los comandos o plantillas existan en el runtime de Nagios.
- **Complejidad:** media; automatiza la edición de archivos de configuración, detecta el separador del CSV y actualiza hostgroups de forma incremental.
- **Manual de uso:**
  1. Ajustar la variable `NAGIOS_CONFIG` con la ruta al archivo `.cfg` destino.
  2. Preparar `hosts.csv` con columnas `host_name,alias,address,hostgroup` y ejecutar `bash add_host_csv.sh`.
  3. Verificar el archivo actualizado y reiniciar Nagios (`nagios -v ...` y `systemctl restart nagios`).

### `add_host_wizard.sh`
- **Funcionalidad:** asistente interactivo que permite crear un fichero de cliente nuevo o reutilizar uno existente, añadir múltiples hosts y anexa servicios base (PING). Gestiona la membresía de hostgroups.
- **Precisión y alcance:** usa `select` y confirmaciones para evitar errores de entrada. No valida direcciones IP ni elimina duplicados; se recomienda revisión manual antes de recargar Nagios.
- **Complejidad:** media-baja; combina bucles y `awk` para actualizar hostgroups.
- **Manual de uso:**
  1. Ejecutar como usuario con permisos sobre `/usr/local/nagios/etc`.
  2. Elegir si se creará un cliente nuevo o se editará uno existente.
  3. Indicar cuántos hosts se añadirán y proporcionar sus campos.
  4. Seleccionar o crear el hostgroup objetivo.
  5. Validar con `nagios -v` y reiniciar el servicio.

### `install_ndoutils.sh`
- **Funcionalidad:** instala MySQL y NDOUtils 2.1.3, crea la base de datos `nagios`, genera el usuario `ndoutils` y activa el broker `ndomod.o`.
- **Precisión y alcance:** pensado para Ubuntu/Debian. Usa credenciales codificadas en el script y no endurece MySQL; se recomienda cambiarlas tras la ejecución.
- **Complejidad:** media; automatiza descarga, compilación y ajustes mínimos.
- **Manual de uso:**
  1. Ejecutar como root en el servidor Nagios.
  2. Esperar a que instale dependencias y compile.
  3. Revisar `/usr/local/nagios/etc/ndo2db.cfg` para ajustar credenciales.
  4. Reiniciar Nagios y comprobar que `ndo2db` está activo.

### `nagios configuration file`
- **Funcionalidad:** plantilla del archivo `nagios.cfg` con opciones de logging, rutas y parámetros de ejecución predeterminados.
- **Uso recomendado:** copiar a `/usr/local/nagios/etc/nagios.cfg` y ajustar rutas (`cfg_file`, `cfg_dir`, etc.) para el entorno específico.

## Configuraciones

### `Templates/`
- Contiene definiciones base (`generic-host`, `generic-service`, `contactgroups`, `timeperiods`, etc.) listas para importarse. Útiles como punto de partida para nuevos despliegues o para mantener convenciones homogéneas.

### `sample-config/`
- Incluye los archivos `*.cfg.in` originales del paquete Nagios (HTTPD, MRTG, `nagios.cfg`, plantillas de objetos). Sirven como referencia para regenerar configuraciones o estudiar los parámetros por defecto.
  - `template-object/` aporta ejemplos para `localhost`, impresoras, switches, hosts Windows y los comandos asociados.
  - Revisar los archivos README adjuntos para instrucciones de `augenrules` y compilación de plantillas.
