# Moodle

### `install_moodle.sh`
- **Funcionalidad:** instala Moodle sobre Ubuntu/Debian: actualiza paquetes, despliega LAMP stack con PHP 8.1 y extensiones necesarias, clona Moodle desde Git y prepara permisos.
- **Precisión:** usa credenciales MySQL estáticas que deben cambiarse en producción. Depende de `git` y `mysql_secure_installation` interactivo.
- **Complejidad:** media.
- **Manual de uso:**
  1. Ejecutar como usuario con sudo (`sudo ./install_moodle.sh`).
  2. Durante `mysql_secure_installation` establecer contraseña root y políticas.
  3. Completar la instalación desde el navegador apuntando a `http://<host>/moodle`.
