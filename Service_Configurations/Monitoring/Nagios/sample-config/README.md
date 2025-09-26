# sample-config

Archivos de configuración de referencia distribuidos con Nagios.

## Archivos principales
- `cgi.cfg.in`, `nagios.cfg.in`, `resource.cfg.in`, `mrtg.cfg.in`, `httpd.conf.in`: plantillas oficiales con comentarios que explican cada parámetro del demonio, la interfaz CGI y servicios auxiliares.
- `README`: instrucciones de uso y relación con el sistema de construcción original.

## Subdirectorios
- `template-object/`: definiciones `*.cfg.in` para hosts y comandos de ejemplo (localhost, impresoras, Windows, switches). Resultan útiles como punto de partida para generar archivos propios con `make` o para copiar bloques concretos.

## Uso sugerido
1. Copiar los archivos necesarios a `/usr/local/nagios/etc` y eliminar la extensión `.in` tras personalizarlos.
2. Revisar rutas y credenciales antes de habilitar las CGIs o integraciones.
3. Validar la configuración ejecutando `nagios -v` antes de iniciar o reiniciar el servicio.
