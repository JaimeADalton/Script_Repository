# Templates

Plantillas de objetos para Nagios Core.

## Archivos
- `commands.cfg`: define comandos comunes (`check_ping`, `check_ssh`, etc.) que sirven de base a los servicios añadidos por los asistentes.
- `contacts.cfg`, `contactgroups.cfg`: estructura de contactos, pensada para usarse como ejemplo y adaptarse con los usuarios reales.
- `generic-host.cfg`, `generic-service.cfg`, `generic-switch.cfg`: plantillas con parámetros por defecto que minimizan la repetición en las definiciones.
- `timeperiods.cfg`: ventanas de notificación/monitorización predefinidas.

## Uso sugerido
1. Copiar los ficheros a `objects/` dentro del árbol de Nagios.
2. Ajustar nombres de contactos, emails, escalados y comandos según la organización.
3. Ejecutar `nagios -v /ruta/nagios.cfg` para validar la sintaxis antes de recargar el servicio.
