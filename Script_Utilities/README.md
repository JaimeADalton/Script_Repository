# Script_Utilities

Colección de utilidades para tareas administrativas diversas.

## Scripts principales

### `Get-VMInfo.ps1` / `Get-VMInfo.py`
- **Funcionalidad:** conectan a un servidor vCenter, consultan información detallada de máquinas virtuales (CPU, RAM, datastore, VLAN, snapshots) y permiten ampliar la salida con la opción `-AllData`.
- **Precisión:** requieren VMware PowerCLI y credenciales válidas. El script `.py` es en realidad PowerShell y debe ejecutarse en un entorno con PowerShell Core.
- **Complejidad:** media-alta; combinan consultas a múltiples cmdlets y gestión de excepciones.
- **Manual de uso:** editar usuario/servidor, ejecutar `./Get-VMInfo.ps1 [-AllData] <VM>` o adaptar para listar todas las VMs según las funciones incluidas.

### `aviso_reinicio.sh`
- **Funcionalidad:** envía un aviso de reinicio a todos los usuarios conectados usando `wall`.
- **Precisión:** mensaje predefinido; modificar el texto según la operación planificada.
- **Complejidad:** baja.
- **Manual:** `sudo ./aviso_reinicio.sh`.

### `compare_directories_details.sh`
- **Funcionalidad:** compara dos directorios generando hashes SHA1, muestra diferencias y, opcionalmente, archivos idénticos con detalles de tamaño/fecha.
- **Precisión:** requiere acceso de lectura a ambos directorios; usa `find`, `sha1sum` y `stat`.
- **Complejidad:** media.
- **Manual:** `./compare_directories_details.sh /ruta/origen /ruta/destino` y responder si se desean listar coincidencias.

### `directory_content_viewer.sh`
- **Funcionalidad:** imprime el contenido de cada archivo en los directorios pasados como argumento con formato resaltado.
- **Precisión:** no filtra archivos binarios; revisar antes de usar en directorios grandes.
- **Complejidad:** baja.
- **Manual:** `./directory_content_viewer.sh /ruta1 /ruta2`.

### `dns_smart_autotune.py`
- **Funcionalidad:** benchmark de servidores DNS con almacenamiento histórico en SQLite, aprendizaje automático (`RandomForestRegressor`, `IsolationForest`) y generación de métricas (latencia, estabilidad, anomalías).
- **Precisión:** necesita privilegios de red, dependencias `dnspython`, `numpy`, `scikit-learn`. Los resultados mejoran con ejecuciones sucesivas gracias al modelo persistente.
- **Complejidad:** alta.
- **Manual:** `sudo python3 dns_smart_autotune.py [--quick|--duration N|--learning|--reset-learning]`.

### `get_os_by_ttl.sh`
- **Funcionalidad:** escanea rangos definidos en `networks`, ejecuta pings y clasifica hosts según el TTL para inferir su sistema operativo.
- **Precisión:** heurística basada en valores comunes de TTL; pueden producirse falsos positivos tras saltos de red.
- **Complejidad:** media.
- **Manual:** definir redes dentro del script y ejecutar con flags (`-w`, `-l`, `-o`, `-x`).

### `identify_os_advanced.sh`
- **Funcionalidad:** identifica distribución Linux, gestor de paquetes, versión de kernel y deduce antigüedad aproximada del sistema. Muestra `uname`, `lsb_release`, `hostnamectl` cuando están disponibles.
- **Precisión:** depende de archivos `/etc/*release`.
- **Complejidad:** baja.
- **Manual:** `./identify_os_advanced.sh`.

### `remove_info_login.sh`
- **Funcionalidad:** deshabilita el log de último acceso en SSH y silencia MOTD dinámico en Ubuntu.
- **Precisión:** modifica `/etc/ssh/sshd_config` y permisos en `/etc/update-motd.d`.
- **Complejidad:** baja.
- **Manual:** ejecutar como root y reiniciar el servicio SSH.

### `scan_space.sh`
- **Funcionalidad:** calcula uso de disco de un directorio o de cada subdirectorio inmediato.
- **Precisión:** requiere ejecutar como root para evitar errores de permisos; ignora enlaces simbólicos.
- **Complejidad:** baja.
- **Manual:** `sudo ./scan_space.sh /ruta`.

### `splitxt.py`
- **Funcionalidad:** divide archivos de texto en bloques de tamaño fijo y crea archivos numerados.
- **Precisión:** opera en modo texto UTF-8; ideal para dividir grandes ficheros de log.
- **Complejidad:** baja.
- **Manual:** `python splitxt.py archivo.txt 40000`.

## Scripts adicionales
- `directory_content_viewer.sh`, `compare_directories_details.sh`, `dns_smart_autotune.py`, etc., pueden combinarse con las subcarpetas descritas en los READMEs correspondientes.
- Consulte cada subdirectorio (`Bash_Header`, `Restricted_Shell`, `Hardening`, `YouTube`, `Let's Encrypt`) para utilidades especializadas.
