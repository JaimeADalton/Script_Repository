# Prometheus

Scripts para desplegar Prometheus y Node Exporter en servidores Debian/Ubuntu.

## `Install_prometheus.sh`
- **Funcionalidad:** instala Prometheus 3.2.1, Blackbox Exporter y Node Exporter, crea usuarios de servicio, configura directorios, genera `prometheus.yml` básico y crea unidades systemd.
- **Precisión:** requiere conexión a Internet y privilegios root. Las URLs de descarga apuntan a GitHub; actualice versiones si es necesario.
- **Complejidad:** alta.
- **Manual:** `sudo ./Install_prometheus.sh` y revisar `/etc/prometheus/prometheus.yml` para añadir jobs adicionales.

## `install_node_exporter.sh`
- **Funcionalidad:** descarga un binario hospedado internamente (`http://10.7.220.15:8000/...`), crea usuario/grupo `node_exporter`, instala el servicio systemd y opcionalmente abre el puerto en UFW.
- **Precisión:** actualice la URL antes de usarlo en otros entornos. Escucha por defecto en el puerto 9200 (se puede sobrescribir con `PORT=9100 ./install_node_exporter.sh`).
- **Complejidad:** media.
- **Manual:** ejecutar como root y comprobar acceso en `http://<host>:9200/metrics`.
