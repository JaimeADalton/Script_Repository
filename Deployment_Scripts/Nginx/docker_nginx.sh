#!/bin/bash

# Definir la ruta del directorio de trabajo
WORKDIR=$(dirname "$(realpath "$0")")

# Crear directorios para la configuración y el contenido de NGINX
NGINX_ETC_DIR="$WORKDIR/nginx/etc"
NGINX_WWW_DIR="$WORKDIR/nginx/www"
NGINX_SSL_DIR="$WORKDIR/nginx/ssl"
mkdir -p "$NGINX_ETC_DIR"
mkdir -p "$NGINX_WWW_DIR"
mkdir -p "$NGINX_SSL_DIR"

# Ejecutar un contenedor temporal de NGINX
docker run --name tmp-nginx -d nginx

# Copiar la configuración y el contenido predeterminado de NGINX
docker cp tmp-nginx:/etc/nginx/ "$NGINX_ETC_DIR"
docker cp tmp-nginx:/var/www/ "$NGINX_WWW_DIR"
docker cp tmp-nginx:/etc/ssl/ "$NGINX_SSL_DIR"

# Detener y eliminar el contenedor temporal de NGINX
docker stop tmp-nginx
docker rm tmp-nginx

# Generar el archivo docker-compose.yml
cat > "$WORKDIR/docker-compose.yml" <<EOF
version: '3'

services:
  nginx:
    container_name: nginx
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/etc:/etc/nginx
      - ./nginx/www:/var/www
      - ./nginx/ssl:/etc/ssl
    networks:
      - nginx-network

networks:
  nginx-network:
    driver: bridge
EOF

# Iniciar el servicio NGINX con Docker Compose
docker-compose -f "$WORKDIR/docker-compose.yml" up -d

echo "Configuración de NGINX completada. Edita los archivos en '$NGINX_ETC_DIR', '$NGINX_WWW_DIR' y '$NGINX_SSL_DIR' según sea necesario."
