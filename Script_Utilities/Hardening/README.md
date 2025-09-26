# Hardening

Scripts para fortificar servidores expuestos a laboratorios de seguridad.

## Scripts

### `fortify-web-system.sh`
- **Funcionalidad:** despliega medidas de endurecimiento en un host que aloja aplicaciones web vulnerables. Crea un usuario aislado, aplica límites de recursos, configura `sysctl`, habilita AppArmor/Fail2ban/Auditd, instala IDS básicos y ajusta servicios.
- **Precisión:** asume Debian/Ubuntu y debe ejecutarse como root. Modifica archivos de sistema (`/etc/security/limits.conf`, `/etc/sysctl.d`, `ufw`, etc.), por lo que conviene revisar cada bloque antes de usarlo en producción.
- **Complejidad:** alta; consta de múltiples pasos con comprobaciones y logs.
- **Manual de uso:**
  1. Revisar todas las secciones para adecuarlas al entorno (nombre de usuario, límites, políticas).
  2. Ejecutar `sudo ./fortify-web-system.sh` y seguir la salida para detectar posibles errores.
  3. Reiniciar los servicios indicados y verificar con `auditctl -s`, `ufw status`, etc.

### `configure-firewall.sh`
- **Funcionalidad:** configura `iptables` para un entorno de pruebas WAF, respaldando reglas anteriores, definiendo políticas estrictas y permitiendo únicamente redes autorizadas.
- **Precisión:** requiere conocer interfaces (`ens3`, `ens7`), gateways y redes permitidas. Usa `iptables-save/restore`, `netfilter-persistent` y Fail2ban.
- **Complejidad:** alta.
- **Manual de uso:**
  1. Ajustar variables `SSH_ALLOWED_NET`, `WAF_TESTING_NET`, `MANAGEMENT_NET`, etc.
  2. Ejecutar como root y revisar el backup generado en `/etc/iptables/backups/`.
  3. Validar conectividad tras aplicar las reglas (`iptables -L -n`).

### `ip-rep-fw.sh`
- **Funcionalidad:** consume feeds de reputación IP (HTTP/HTTPS), genera reglas para bloquear direcciones maliciosas y mantiene métricas/estadísticas en `/var/log/ip-rep-fw/`.
- **Precisión:** configurable vía variables de entorno o archivo `.conf`; registra en syslog si se habilita. Requiere `curl`, `jq` y privilegios para manipular `iptables`/`nftables` según la integración deseada.
- **Complejidad:** alta; implementa logging estructurado, métricas y cachés.
- **Manual de uso:**
  1. Configurar `CONF_FILE` o variables (`FEEDS`, `OUTPUT_DIR`, etc.).
  2. Ejecutar manualmente o programar con cron/systemd timer.
  3. Revisar los logs y estadísticas generadas para asegurarse de que los feeds se procesan correctamente.
