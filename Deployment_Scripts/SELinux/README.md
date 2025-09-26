# SELinux

### `fix_selinux_logs.sh`
- **Funcionalidad:** corrige contextos SELinux de directorios de logs en sistemas RHEL/CentOS: elimina reglas erróneas con `semanage`, ejecuta `restorecon` sobre rutas críticas y crea un log de ejecución.
- **Precisión:** requiere utilidades `semanage`, `restorecon`, `ausearch`. El script valida su presencia e informa cómo instalarlas si faltan.
- **Complejidad:** media.
- **Manual de uso:** ejecutar como root (`sudo ./fix_selinux_logs.sh`), revisar el log generado en `/tmp/selinux_log_fix_*.log` y verificar que los servicios puedan escribir en `/var/log` sin alertas de AVC.
