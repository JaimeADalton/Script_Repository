# WordPress

### `Wordpress_install.sh`
- **Funcionalidad:** automatiza la instalación de WordPress en Ubuntu 22.04 configurando Apache, MySQL, PHP y creando un `VirtualHost`. Genera claves de seguridad y ajusta permisos.
- **Precisión:** credenciales (`root_password`, `db_password`) deben cambiarse. Utiliza `curl` para obtener salts y no activa HTTPS por defecto.
- **Complejidad:** media.
- **Manual de uso:**
  1. Editar las variables al inicio del script.
  2. Ejecutar como usuario con sudo (`sudo ./Wordpress_install.sh`).
  3. Completar el asistente web en `http://<host>/`.
