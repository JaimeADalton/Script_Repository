# Update_RHEL8.0

### `Actualizar_RHEL8.0`
- **Funcionalidad:** registra una suscripción de Red Hat Enterprise Linux 8.6, ejecuta `yum clean all`, aplica todas las actualizaciones disponibles y reinicia el sistema.
- **Precisión:** guarda la salida en `/var/log/script.log` y detiene la ejecución si `subscription-manager` falla. Las credenciales están codificadas y deben modificarse.
- **Complejidad:** baja.
- **Manual de uso:** editar usuario/contraseña al inicio del script, ejecutarlo como root (`bash Actualizar_RHEL8.0`) y revisar el log generado para confirmar que la actualización concluyó correctamente.
