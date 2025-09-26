# Audit Logging Tools

Herramientas de análisis para los logs de `auditd`.

## Scripts

### `audit_log_analizer.py`
- **Funcionalidad:** parser interactivo que utiliza expresiones regulares para extraer campos clave (`type`, `timestamp`, `pid`, `uid`, `exe`, etc.) de archivos `audit.log*`. Permite filtrar por tipo de evento, usuario, IP, resultado y múltiples parámetros adicionales.
- **Precisión:** requiere ejecutarse como root para leer `/var/log/audit/*`. Maneja errores de permisos y valida los argumentos; usa `glob` para combinar archivos rotados.
- **Complejidad:** media; combina parsing manual, filtro condicional y una clase de `ArgumentParser` personalizada.
- **Manual de uso:**
  1. Ejecutar `sudo python3 audit_log_analizer.py --help` para consultar las opciones.
  2. Aplicar filtros como `--type USER_LOGIN --result success` o `--user root`.
  3. Revisar la salida estructurada en consola o redirigirla a un archivo para posteriores análisis.
