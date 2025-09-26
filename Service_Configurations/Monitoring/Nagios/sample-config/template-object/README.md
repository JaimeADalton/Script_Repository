# template-object

Colección de objetos de ejemplo que acompañan al paquete Nagios original.

## Contenido destacado
- `localhost.cfg.in`: servicios estándar para el servidor local (carga, uso de disco, procesos críticos).
- `switch.cfg.in`, `printer.cfg.in`: ejemplos de dispositivos de red/impresoras con plantillas de chequeo SNMP.
- `windows.cfg.in`: definiciones base para hosts Windows usando `check_nt`.
- `commands.cfg.in`, `templates.cfg.in`, `timeperiods.cfg.in`: comandos y plantillas reutilizables.
- `contacts.cfg.in`: contactos y grupos predefinidos.

## Uso sugerido
1. Eliminar la extensión `.in` y ajustar los valores (hostnames, comunidades SNMP, contraseñas) antes de copiarlos a `objects/`.
2. Integrar solo los bloques necesarios para evitar duplicidades con plantillas personalizadas.
3. Validar con `nagios -v` tras importar los objetos.
