# rules

Colección oficial de reglas de `auditd` organizadas para `augenrules`.

## Organización por prefijo
- **10-** Configuración base del demonio (buffers, política de fallo, loginuid).
- **20-** Exclusiones o filtros que evitan duplicidades con reglas específicas.
- **30-** Perfiles completos (OSPP, PCI DSS, STIG) divididos por tipo de evento (creación, modificación, permisos, etc.).
- **31-** Reglas generadas dinámicamente para binarios con privilegios (ver comentarios en `31-privileged.rules`).
- **40/41/42/43/44-** Reglas opcionales: personalización local, contenedores, detección de inyección, carga de módulos, instalación de software.
- **70-** Manejo de errores `EINVAL`.
- **71-** Eventos de red.
- **99-** Clausura (`-e 2`) para inmovilizar la política.

## Manual de uso
1. Seleccionar los archivos que representen el perfil de cumplimiento deseado.
2. Copiarlos a `/etc/audit/rules.d/` manteniendo el prefijo numérico.
3. Regenerar la política (`augenrules --load`).
4. Verificar con `auditctl -l` que las reglas estén activas y ajustar según el volumen de eventos.
