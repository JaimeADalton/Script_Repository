# Audit

Recursos para configurar `auditd`.

## Archivos

### `audit.rules`
- **Funcionalidad:** conjunto extensivo de reglas recomendadas (basadas en guías Gov.uk, PCI, NISPOM). Limpia reglas previas, establece buffers, filtros y audita actividades críticas (kernel, módulos, cron, cuentas, cambios de permisos, etc.).
- **Precisión:** compatible con auditd 2.8+/Linux kernel 4+. Algunas reglas hacen referencia a arquitecturas `b64`; conviene revisar syscalls disponibles si se usa ARM o plataformas sin `open`. Incluye exclusiones para reducir ruido.
- **Complejidad:** alta; cubre decenas de categorías y requiere comprender el impacto en el rendimiento.
- **Manual de uso:**
  1. Respaldar `/etc/audit/rules.d` y `/etc/audit/audit.rules` actuales.
  2. Copiar el archivo como `/etc/audit/audit.rules` o dividirlo en `rules.d/`.
  3. Ejecutar `augenrules --load` o reiniciar `auditd`.
  4. Monitorizar `/var/log/audit/audit.log` para ajustar filtros según el entorno.

## Directorios

### `rules/`
- **Contenido:** colecciones modulares agrupadas por prefijo (10-, 20-, 30-, etc.) para usarse con `augenrules`. Incluyen perfiles PCI DSS, STIG, OSPP y reglas locales.
- **Uso:** copiar sólo los archivos relevantes a `/etc/audit/rules.d/` según el perfil deseado, regenerar con `augenrules --load` y reiniciar `auditd`.
- **Documentación:** revisar `README-rules` para entender el orden de carga y cómo regenerar `31-privileged.rules`.
