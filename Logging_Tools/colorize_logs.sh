#!/bin/bash

# Función para colorear las columnas del archivo log
colorize_log_columns() {
    awk '
    {
        # Colorear cada columna de un color diferente (puedes cambiar los códigos ANSI aquí)
        for (i = 1; i <= NF; i++) {
            printf("\033[1;%dm%s\033[0m%s", 31 + (i % 6), $i, (i == NF) ? "\n" : " ");
        }
    }'
}

# Verifica que se haya pasado un archivo como argumento
if [ $# -eq 0 ]; then
    echo "Uso: $0 archivo.log"
    exit 1
fi

# Verifica que el archivo exista y sea legible
if [ ! -f "$1" ]; then
    echo "Error: El archivo $1 no existe o no es legible."
    exit 1
fi

# Colorea las columnas del archivo log
cat "$1" | colorize_log_columns
