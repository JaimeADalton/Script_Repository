# Nextcloud

### `install_nextcloud.sh`
- **Funcionalidad:** despliega Nextcloud en Ubuntu/Debian instalando Apache, MariaDB y PHP con las extensiones necesarias, crea base de datos/usuario y configura un `VirtualHost` básico.
- **Precisión:** usa credenciales codificadas (`nextclouduser`/`T3mp0r4l`) que deben cambiarse. `mysql_secure_installation` solicita entrada manual.
- **Complejidad:** media.
- **Manual de uso:**
  1. Ejecutar como usuario con sudo (`sudo ./install_nextcloud.sh`).
  2. Configurar SSL y dominio en `/etc/apache2/sites-available/nextcloud.conf` según el entorno.
  3. Acceder vía navegador para completar el asistente web de Nextcloud.
