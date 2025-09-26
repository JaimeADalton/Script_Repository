# telegraf

Configuración del agente Telegraf empleado por el stack Docker.

## Archivos
### `telegraf.conf`
- **Funcionalidad:** configura el agente con intervalo de 30s, jitter para distribución de carga y salida hacia InfluxDB v2 mediante token (`INFLUX_TOKEN`). Establece `hostname` estático para diferenciar métricas.
- **Precisión:** ajustado para enviar datos al servicio `influxdb` del mismo compose. Los valores de `organization` y `bucket` deben coincidir con los definidos en el `.env`.
- **Complejidad:** baja-media; se limita a configuración global y destino InfluxDB.
- **Manual de uso:**
  1. Revisar intervalos y buffers según el volumen de métricas.
  2. Configurar entradas (plugins `[[inputs.*]]`) adicionales según sea necesario.
  3. Asegurarse de que la variable `INFLUX_TOKEN` esté disponible como variable de entorno del contenedor.
