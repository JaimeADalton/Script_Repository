# Sample Init Service

Plantilla de script `init.d` para servicios clásicos en Debian/Ubuntu.

- **Archivo:** `Sample init.d file service`
  - **Funcionalidad:** usa `start-stop-daemon` para lanzar un demonio PHP en segundo plano, gestionar el PID y registrar la salida en `/var/log/<nombre>.log`.
  - **Precisión:** respeta la cabecera `INIT INFO` para integrarse con `update-rc.d`. Las rutas (`/usr/bin/php`, `/var/www/myproject/myscript.php`) son ejemplos y deben ajustarse.
  - **Complejidad:** baja; proporciona las funciones básicas `start`, `stop`, `restart` con manejo de PID y limpieza.
  - **Manual de uso:**
    1. Copiar el fichero a `/etc/init.d/<nombre>` y ajustar `NAME`, `DESC`, `DAEMON` y `DAEMON_OPTS`.
    2. Dar permisos de ejecución (`chmod +x`).
    3. Registrar el servicio (`update-rc.d <nombre> defaults`).
    4. Gestionar con `service <nombre> start|stop|restart`.
