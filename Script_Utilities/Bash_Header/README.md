# Bash_Header

Generador de cabeceras estándar para scripts Bash.

## Script
### `createheader.sh`
- **Funcionalidad:** solicita título, descripción, autor y versión, crea un archivo `.sh` con plantilla (shebang, metadatos, líneas separadoras) y abre el editor seleccionado (Vim, Emacs o Nano) en la línea 12.
- **Precisión:** asegura que el nombre del archivo sea único, normaliza el título (`lowercase`, guiones bajos) y hace ejecutable el script creado.
- **Complejidad:** baja.
- **Manual de uso:** ejecutar `bash createheader.sh`, responder a los prompts y elegir el editor preferido para continuar editando el nuevo script.
