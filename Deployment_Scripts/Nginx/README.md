# Nginx

Scripts para preparar un contenedor Nginx con persistencia local.

## Archivos

### `docker_nginx.sh`
- **Funcionalidad:** crea estructuras de directorios (`nginx/share`, `nginx/etc`, `nginx/www`, `nginx/ssl`), copia la configuración por defecto desde un contenedor temporal y genera un `docker-compose.yml` listo para usar.
- **Precisión:** requiere Docker y Docker Compose plugin. El script detiene y elimina el contenedor temporal `tmp-nginx` tras extraer los archivos.
- **Manual:** ejecutar `./docker_nginx.sh`, editar los archivos en los directorios montados y reiniciar con `docker compose up -d`.

### `docker-compose.yml`
- **Funcionalidad:** versión mínima que monta configuraciones y certificados desde el host.
- **Manual:** colocar certificados en `./ssl`, configuración en `./nginx/etc`, luego `docker compose up -d`.
