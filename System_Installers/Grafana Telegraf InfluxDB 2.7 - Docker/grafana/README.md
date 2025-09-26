# grafana

Configuración y almacenamiento de Grafana dentro del stack Docker.

## Archivos
### `grafana.ini`
- **Funcionalidad:** versión mínima que delega credenciales al entorno (`GF_SECURITY_ADMIN_USER` y `GF_SECURITY_ADMIN_PASSWORD`). Adecuada para pruebas o entornos pequeños.
- **Uso:** se monta en `/etc/grafana/grafana.ini` del contenedor. Ajustar el dominio y las opciones de registro según el despliegue.

### `config/grafana.ini`
- **Funcionalidad:** configuración avanzada orientada a un entorno profesional (rotación de logs, seguridad endurecida, opciones de snapshot y dashboards).
- **Precisión:** valores de ejemplo (usuario `netadmin`, contraseñas y claves secretas) deben sustituirse antes de producción.
- **Manual de uso:** copiar al directorio `config/` del contenedor y actualizar rutas, políticas de seguridad y credenciales.
