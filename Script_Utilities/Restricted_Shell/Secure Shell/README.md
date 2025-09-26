# Secure Shell

Implementación en C++ de una shell restringida acompañada de un instalador en Bash.

## Archivos

### `secure_shell.cpp`
- **Funcionalidad:** shell robusta con control de argumentos, límites de uso para comandos (`ping`, `tracepath`, `ssh`), registro rotativo mediante `spdlog` y aplicación de capacidades POSIX (`cap_net_raw`, `cap_net_admin`). Sanitiza entradas, limita número de argumentos y evita opciones peligrosas en SSH.
- **Precisión:** depende de bibliotecas Boost, `libcap`, `fmt`, `spdlog` y de MIBs del sistema. Gestiona conexiones simultáneas (`MAX_SSH_CONNECTIONS`) y bloquea intentos fallidos repetidos.
- **Complejidad:** alta.
- **Manual de uso:**
  1. Compilar con el script `setup_secure_shell.sh` o manualmente (`g++ secure_shell.cpp -o /usr/bin/secure_shell ...`).
  2. Editar el archivo de configuración `/etc/secure_shell.conf` para ajustar límites.
  3. Asignar la shell a usuarios restringidos.

### `setup_secure_shell.sh`
- **Funcionalidad:** instala dependencias (compiladores, Boost, libcap, etc.), compila `secure_shell`, crea usuario `secureshell`, prepara un chroot y configura logging.
- **Precisión:** pensado para Debian/Ubuntu. Ajusta capacidades con `setcap` y crea el archivo de configuración por defecto.
- **Manual de uso:** ejecutar como root (`sudo ./setup_secure_shell.sh`), revisar el chroot generado y añadir los binarios necesarios dentro de `/home/secureshell/chroot` antes de conceder acceso.
