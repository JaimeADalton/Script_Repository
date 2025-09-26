# config

Configuración CLI de InfluxDB.

### `influx-configs`
- **Funcionalidad:** fichero compatible con `influx config` que define un perfil por defecto (`network-monitoring-token-secure-2024`).
- **Uso:** copiar a `/etc/influxdb2/influx-configs` para que la CLI tenga credenciales y URL preconfiguradas.
- **Precisión:** sustituir token y URL por valores reales antes de arrancar el contenedor en producción.
