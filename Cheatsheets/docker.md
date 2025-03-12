# Docker y Docker Compose: De Novato a Experto

## NIVEL PRINCIPIANTE

### Instalación en Linux
```bash
# Instalar Docker
sudo apt update
sudo apt install docker.io

# Instalar Docker Compose
sudo apt install docker-compose

# Iniciar Docker y configurarlo para que inicie con el sistema
sudo systemctl start docker
sudo systemctl enable docker

# Agregar usuario al grupo docker (para usar sin sudo)
sudo usermod -aG docker $USER
# Necesitarás cerrar sesión y volver a entrar para que tome efecto
```

### Comandos Básicos de Docker
```bash
# Verificar versión de Docker
docker --version
docker-compose --version

# Ejecutar una imagen (descarga si no está disponible)
docker run hello-world

# Listar contenedores en ejecución
docker ps

# Listar todos los contenedores (incluyendo detenidos)
docker ps -a

# Listar imágenes descargadas
docker images

# Detener un contenedor
docker stop <container_id/name>

# Iniciar un contenedor detenido
docker start <container_id/name>

# Eliminar un contenedor
docker rm <container_id/name>

# Eliminar una imagen
docker rmi <image_id/name>
```

## NIVEL INTERMEDIO

### Operaciones con Contenedores
```bash
# Ejecutar contenedor en modo interactivo
docker run -it ubuntu bash

# Ejecutar contenedor con nombre específico
docker run --name mi-nginx nginx

# Ejecutar contenedor en segundo plano (modo detached)
docker run -d nginx

# Mapear puertos (host:contenedor)
docker run -p 8080:80 nginx

# Montar volumen (directorio_host:directorio_contenedor)
docker run -v /ruta/local:/ruta/contenedor nginx

# Ver logs de un contenedor
docker logs <container_id/name>

# Ver logs en tiempo real
docker logs -f <container_id/name>

# Ejecutar comando en contenedor en ejecución
docker exec -it <container_id/name> bash

# Copiar archivos hacia o desde el contenedor
docker cp archivo.txt <container_id>:/ruta/
docker cp <container_id>:/ruta/archivo.txt ./

# Inspeccionar detalles de un contenedor
docker inspect <container_id/name>

# Ver uso de recursos
docker stats
```

### Docker Compose Básico
```bash
# Estructura típica de docker-compose.yml
version: '3'
services:
  web:
    image: nginx
    ports:
      - "8080:80"
  db:
    image: postgres
    environment:
      POSTGRES_PASSWORD: example
```

```bash
# Iniciar servicios definidos en docker-compose.yml
docker-compose up

# Iniciar en segundo plano
docker-compose up -d

# Detener servicios
docker-compose down

# Ver logs de todos los servicios
docker-compose logs

# Ver logs de un servicio específico
docker-compose logs web
```

## NIVEL AVANZADO

### Creación de Imágenes Personalizadas

#### Ejemplo de Dockerfile
```dockerfile
FROM ubuntu:20.04
LABEL maintainer="tu@email.com"

# Variables de entorno
ENV DEBIAN_FRONTEND=noninteractive

# Actualizar e instalar paquetes
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Directorio de trabajo
WORKDIR /app

# Copiar archivos de la aplicación
COPY . /app/

# Instalar dependencias de Python
RUN pip3 install -r requirements.txt

# Puerto a exponer
EXPOSE 5000

# Comando a ejecutar cuando inicie el contenedor
CMD ["python3", "app.py"]
```

```bash
# Construir imagen desde Dockerfile
docker build -t mi-app:1.0 .

# Construir sin usar caché
docker build --no-cache -t mi-app:1.0 .

# Etiquetar imagen
docker tag mi-app:1.0 usuario/mi-app:1.0

# Publicar imagen en Docker Hub
docker login
docker push usuario/mi-app:1.0
```

### Docker Compose Avanzado
```yaml
version: '3.8'

services:
  web:
    build: 
      context: ./web
      dockerfile: Dockerfile
    ports:
      - "8080:80"
    volumes:
      - ./web:/var/www/html
    depends_on:
      - db
    restart: always
    environment:
      - DB_HOST=db
      - DB_PASSWORD=secreto
    networks:
      - frontend
      - backend

  db:
    image: mariadb:10.5
    volumes:
      - db_data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=secreto
      - MYSQL_DATABASE=appdb
    networks:
      - backend
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  redis:
    image: redis:alpine
    networks:
      - backend

networks:
  frontend:
  backend:

volumes:
  db_data:
```

```bash
# Iniciar con escala (múltiples instancias)
docker-compose up -d --scale web=3

# Ejecutar comandos en un servicio
docker-compose exec web bash

# Ver configuración de redes
docker-compose config

# Verificar configuración
docker-compose config

# Reconstruir servicios
docker-compose build

# Reconstruir y reiniciar
docker-compose up -d --build
```

## NIVEL EXPERTO

### Optimización y Seguridad

#### Optimización de Dockerfile
```dockerfile
# Multi-stage build
FROM node:14 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Docker Swarm (Orquestación nativa)
```bash
# Inicializar Swarm
docker swarm init --advertise-addr <IP_MANAGER>

# Obtener token para unir nodos worker
docker swarm join-token worker

# Unirse como worker
docker swarm join --token <TOKEN> <IP_MANAGER>:2377

# Listar nodos
docker node ls

# Desplegar stack desde compose
docker stack deploy -c docker-compose.yml mi-app

# Listar servicios en el stack
docker stack services mi-app

# Escalar servicio
docker service scale mi-app_web=5

# Actualizar servicio (rolling update)
docker service update --image nuevaimagen:version mi-app_web
```

### Redes Avanzadas
```bash
# Crear red personalizada
docker network create --driver overlay --attachable mi-red

# Inspeccionar red
docker network inspect mi-red

# Conectar contenedor a red
docker network connect mi-red mi-contenedor

# Desconectar contenedor de red
docker network disconnect mi-red mi-contenedor
```

### Volúmenes y Almacenamiento
```bash
# Crear volumen
docker volume create mi-volumen

# Listar volúmenes
docker volume ls

# Inspeccionar volumen
docker volume inspect mi-volumen

# Eliminar volúmenes no utilizados
docker volume prune
```

### Monitoreo y Administración
```bash
# Monitoreo básico
docker stats $(docker ps --format={{.Names}})

# Limpieza completa del sistema
docker system prune -a --volumes

# Ver detalles del sistema
docker system info

# Verificar espacio usado
docker system df
```

### Docker Compose con Override
```bash
# Estructura de archivos:
# - docker-compose.yml (base)
# - docker-compose.override.yml (desarrollo)
# - docker-compose.prod.yml (producción)

# Desarrollo (usa override automáticamente)
docker-compose up -d

# Producción (especificar ambos archivos)
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## COMANDOS ÚTILES AVANZADOS

### Gestión de Contenedores
```bash
# Eliminar todos los contenedores detenidos
docker container prune

# Eliminar todos los contenedores (incluso en ejecución)
docker rm -f $(docker ps -aq)

# Reiniciar todos los contenedores
docker restart $(docker ps -q)

# Ver procesos en un contenedor
docker top <container_id/name>

# Limitar recursos (CPU, memoria)
docker run --cpus=0.5 --memory=512m nginx
```

### Gestión de Imágenes
```bash
# Eliminar imágenes sin etiqueta (<none>)
docker rmi $(docker images -f "dangling=true" -q)

# Guardar imagen como tarball
docker save -o imagen.tar mi-imagen:tag

# Cargar imagen desde tarball
docker load -i imagen.tar

# Ver historial de capas de una imagen
docker history mi-imagen:tag

# Exportar contenedor como imagen
docker commit <container_id> nueva-imagen:tag
```

### Seguridad
```bash
# Escanear vulnerabilidades en imágenes
docker scan mi-imagen:tag

# Ejecutar contenedor con menos privilegios
docker run --user 1000:1000 --cap-drop=ALL mi-imagen

# Verificar contenido de secretos
docker secret ls
docker secret inspect mi-secreto

# Crear e implementar secretos (en swarm)
echo "valor-secreto" | docker secret create mi-secreto -
```

### Depuración
```bash
# Seguir eventos de Docker
docker events

# Ver uso detallado de recursos
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Explorar el sistema de archivos de un contenedor sin entrar
docker export <container_id> | tar -tv | grep filename

# Depurar problemas de red
docker run --net container:<container_id> nicolaka/netshoot tcpdump -i eth0
```

## TIPS Y TRUCOS DE EXPERTO

1. **Usar .dockerignore**: Excluir archivos innecesarios al construir imágenes
2. **Minimizar capas**: Combinar comandos RUN para reducir tamaño
3. **Hardening**: Usar imágenes distroless o Alpine para menor superficie de ataque
4. **Secretos**: Nunca hardcodear credenciales en Dockerfiles
5. **Healthchecks**: Implementar HEALTHCHECK para monitoreo interno
6. **Limitar privilegios**: Usar --security-opt=no-new-privileges
7. **Labels**: Etiquetar imágenes para organización y automatización
8. **CI/CD**: Integrar construcción y pruebas en pipelines
9. **Caché inteligente**: Ordenar comandos en Dockerfile del menos al más cambiante
10. **Actualizaciones**: Mantener imágenes base actualizadas por seguridad
