# MySQL

Este directorio contiene utilidades interactivas para gestionar copias de seguridad de instancias MySQL/MariaDB.

## Scripts

### `dumpmysql.sh`
- **Funcionalidad:** asistente interactivo en Bash que valida credenciales con `mysql_config_editor`, comprueba el estado del servicio y permite generar copias de seguridad puntuales o masivas. Puede crear un respaldo único, un volcado consolidado de todas las bases de datos o dumps individuales por base, y registra toda la actividad en `~/DumpMySQL.log`.
- **Precisión y alcance:** utiliza directamente `mysqldump`, por lo que la fiabilidad del respaldo depende del estado del servidor y de los permisos del usuario. Valida la existencia del usuario, confirma rutas de salida y ofrece compresión opcional (`tar`). Supone entornos tipo Debian/Ubuntu con `service mysql` disponible.
- **Complejidad:** media. El script orquesta múltiples flujos, maneja errores comunes y automatiza tareas tediosas, pero no implementa programación concurrente ni comprobaciones avanzadas de integridad.
- **Manual de uso:**
  1. Ejecutar como un usuario con acceso administrativo sobre MySQL (`bash dumpmysql.sh`).
  2. Iniciar el servicio cuando se solicite si está detenido.
  3. Introducir el usuario MySQL; la contraseña se registra mediante `mysql_config_editor` sin exponerla en texto plano.
  4. Elegir una opción del menú (dump individual, completo en un único archivo, dumps separados o listado de bases de datos).
  5. Especificar la carpeta de salida (el script la crea si no existe) y si se desea comprimir el resultado.
  6. Supervisar el progreso en pantalla y, si es necesario, revisar el fichero de log del home para diagnosticar fallos.
