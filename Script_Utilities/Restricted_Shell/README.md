# Restricted_Shell

Shells restringidas y herramientas asociadas para limitar comandos de usuarios.

## Scripts

### `restricted_shell`
- **Funcionalidad:** shell en Bash que limita la ejecución a comandos permitidos (`ping`, `ssh`, `plink`, `telnet`, `tracepath`, `mtr`, `help`, `exit`). Mantiene historial propio, registra cada comando en `/var/log/restricted_shell.log`, valida rutas de salida y bloquea CIDR definidos.
- **Precisión:** determina la ruta de salida con `ip route get` y la compara con `allowed_routes`. Los bloqueos de red (`restricted_networks`) deben definirse manualmente.
- **Complejidad:** media-alta; incorpora control de señales, análisis de argumentos, logging y validaciones de IP/CIDR.
- **Manual de uso:**
  1. Ajustar listas `allowed_commands`, `allowed_routes` y `restricted_networks` según políticas internas.
  2. Copiar el script a `/usr/bin/restricted_shell`, otorgar permisos (`chmod 750`) y asignarlo como shell en `/etc/passwd` para los usuarios objetivo.
  3. Revisar `restricted_shell.log` para auditar comandos.

## Subdirectorios

### `Secure Shell`
Véase el README del subdirectorio para la implementación en C++ y el script de despliegue.
