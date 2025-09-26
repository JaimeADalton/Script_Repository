# scripts

Utilidades incluidas en la imagen CyberLab para mantenimiento y actualización del entorno.

## Scripts

### `backup-data.sh`
- **Funcionalidad:** genera archivos `tar.gz` diarios con el contenido de `/home/security/{workspace,reports,scripts}`.
- **Precisión:** limpia temporalmente los datos en un directorio seguro y protege los respaldos con permisos `600`. Solo copia scripts personalizados (no `.sh`).
- **Complejidad:** baja.
- **Manual de uso:** ejecutar como usuario `security`, revisar/ajustar rutas y programar con cron si se desea automatizar. Los respaldos se guardan en `/home/security/data/backups`.

### `setup-tools.sh`
- **Funcionalidad:** clona y actualiza una colección de herramientas de seguridad (SecLists, PEASS, AutoRecon, etc.), instala dependencias Python y descarga wordlists.
- **Precisión:** requiere acceso a Internet y `git`. No maneja fallos específicos de cada repositorio.
- **Complejidad:** media por la cantidad de repositorios gestionados.
- **Manual de uso:** ejecutar tras construir la imagen o periódicamente. Ajustar la lista `tools`/`forensic_tools` según necesidades.

### `update-system.sh`
- **Funcionalidad:** actualiza paquetes APT, actualiza módulos Python y vuelve a ejecutar `setup-tools.sh`.
- **Precisión:** usa `sudo` y asume credenciales configuradas. Puede tardar dependiendo del número de herramientas instaladas.
- **Manual de uso:** programar tras despliegues o como tarea de mantenimiento. Revisar la salida para detectar paquetes que requieran intervención manual.
