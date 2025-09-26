# Grafana Telegraf InfluxDB 2.7 - Docker

Stack Docker Compose para monitorización de red con InfluxDB 2.7, Telegraf y Grafana.

## Archivos
- `docker-compose.yml`
  - **Funcionalidad:** define tres servicios (`influxdb`, `telegraf`, `grafana`) conectados en la red `network_monitoring`. Expone los puertos 8086 y 3000, incluye `healthcheck` para InfluxDB y monta volúmenes persistentes.
  - **Precisión:** requiere variables de entorno (`INFLUXDB_USERNAME`, `INFLUXDB_PASSWORD`, etc.) definidas en un `.env`. Asume Docker 20.10+.
  - **Complejidad:** media; orquesta dependencias y volúmenes.
  - **Manual de uso:**
    1. Crear un archivo `.env` con credenciales y tokens.
    2. Revisar las carpetas `influxdb/`, `telegraf/` y `grafana/` para personalizar configuraciones.
    3. Ejecutar `docker compose up -d` desde el directorio.
    4. Verificar la salud de los contenedores (`docker compose ps`).

## Subdirectorios
- `influxdb/`: configuración y almacenamiento de InfluxDB.
- `telegraf/`: configuración del agente de métricas.
- `grafana/`: datos y configuración del dashboard.
