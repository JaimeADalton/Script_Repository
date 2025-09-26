# Ubuntu-Server

Definición de contenedor Ubuntu 24.04 preconfigurado para labores administrativas.

## Archivos

### `Dockerfile`
- **Funcionalidad:** construye una imagen con localización `es_ES.UTF-8`, zona horaria Madrid y un amplio catálogo de utilidades (diagnóstico de red, seguridad, edición, monitoreo). Evita paquetes problemáticos (`pcp`), configura `policy-rc.d` y prepara un entorno listo para tareas de bastionado o laboratorio.
- **Complejidad:** alta; instala decenas de paquetes y aplica varias capas de configuración.
- **Manual de uso:**
  1. Ajustar paquetes según las necesidades (por ejemplo, eliminar `masscan` si no se requiere).
  2. Construir con `docker build -t ubuntu-admin .`.
  3. Lanzar con `docker run -it --rm ubuntu-admin` y montar volúmenes si se necesitan scripts persistentes.

### `docker-compose.yml`
- **Funcionalidad:** crea un servicio único basado en la imagen construida, expone el puerto SSH (`2222:22`) y monta volúmenes para persistir `/home` y archivos de configuración.
- **Manual de uso:** ejecutar `docker compose up -d` tras compilar la imagen, actualizar las rutas de volúmenes y definir contraseñas/llaves en la configuración de `openssh-server` dentro del contenedor.
