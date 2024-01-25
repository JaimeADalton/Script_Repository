#!/bin/bash

# Colores para resaltar la salida
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

# Función para mostrar la ayuda
show_help() {
    echo "Uso: $0 [DIRECTORIO]..."
    echo "  Explora todos los archivos en cada directorio especificado y muestra su contenido. Cada directorio debe ser un directorio válido."
}

# Comprueba si no se proporcionaron argumentos
if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

# Itera sobre cada argumento proporcionado
for dir in "$@"; do
    # Comprueba si el argumento es un directorio
    if [ -d "$dir" ]; then
        echo -e "${CYAN}Directorio: $dir${RESET}"
        echo "-------------------------"

        # Itera sobre cada archivo en el directorio
        for file in "$dir"/*; do
            # Comprueba si es un archivo regular
            if [ -f "$file" ]; then
                echo -e "${YELLOW}Contenido de $file:${RESET}"
                cat "$file" 2>/dev/null
                echo "-------------------------"
            fi
        done
    else
        echo "Advertencia: '$dir' no es un directorio válido o no existe."
    fi
done
