# Nagios Deployment Scripts

Automatizaciones para instalar Nagios Core y utilidades relacionadas.

## Scripts

### `install_nagios.sh`
- **Funcionalidad:** descarga Nagios Core 4.4.14 y plugins 2.4.6, crea usuario/grupos y compila una instancia en un directorio personalizado.
- **Precisión:** requiere Ubuntu/Debian, Apache2 y PHP 7.4. Pide una contraseña para `nagiosadmin` durante la instalación.
- **Complejidad:** media.
- **Manual:** ejecutar como sudo, introducir nombre de instancia y seguir prompts.

### `install_nagios_v2.sh`
- **Funcionalidad:** versión mejorada que detecta automáticamente la IP de acceso, obtiene la versión más reciente desde GitHub y guía al operador con mensajes coloreados.
- **Precisión:** idem anterior pero con más validaciones. Usa `curl` para descubrir versiones.
- **Complejidad:** media-alta.
- **Manual:** `sudo ./install_nagios_v2.sh`, responder preguntas y anotar la URL sugerida.

### `install_nagios_v3.sh`
- **Funcionalidad:** agrega logging exhaustivo en `/tmp/nagios_install_*.log`, manejo de errores robusto y reutiliza funciones (`run_command`, `log_message`). Descarga versiones recientes dinámicamente.
- **Precisión:** mismo entorno base que v2, actualiza dependencias a PHP 8.3.
- **Complejidad:** alta.
- **Manual:** ejecutar como sudo, revisar el log en caso de fallo y seguir las instrucciones finales para acceder a la interfaz.

## Subdirectorios

### `PHP Web Monitor SNMP`
- **Archivo:** `index.php`.
  - **Funcionalidad:** panel PHP que lee configuraciones de Nagios, ejecuta `ping` concurrentemente y muestra estado/latencia de hosts.
  - **Manual:** copiar a un servidor web con permisos para leer `/usr/local/nagios/etc/objects`, ajustar rutas según la instalación y acceder vía navegador.
