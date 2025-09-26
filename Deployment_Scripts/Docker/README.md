# Docker

### `DockerInstall.sh`
- **Funcionalidad:** instala Docker Engine y complementos (`docker-ce`, `docker-compose-plugin`, `buildx`), elimina versiones previas, configura el repositorio oficial y agrega al usuario al grupo `docker`. Mantiene un log en `/tmp/docker_install_*.log`.
- **Precisión:** diseñado para Ubuntu/Debian. Verifica arquitectura soportada y requiere conexión a Internet.
- **Complejidad:** media.
- **Manual de uso:**
  1. Ejecutar como root (`sudo ./DockerInstall.sh`).
  2. Revisar el log si ocurre algún error.
  3. Cerrar sesión para aplicar la pertenencia al grupo `docker`.
