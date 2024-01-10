#!/bin/bash

# Verifica si el script se ejecuta como superusuario
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ser ejecutado como superusuario"
   exit 1
fi

# Verifica si se proporciona un segundo parámetro
if [ -z "$1" ]; then
   echo "Uso: $0 <ruta_del_directorio>"
   exit 1
fi

# Ruta del directorio proporcionada como segundo parámetro
directory="$1"

# Verifica si la ruta del directorio es válida y no es un enlace simbólico
if [ -d "$directory" ] && [ ! -L "$directory" ]; then
    # Obtiene la cantidad de subdirectorios en el directorio
    num_subdirectories=$(find "$directory" -type d | wc -l)
    
    if [ "$num_subdirectories" -eq 1 ]; then
        # Si solo hay un subdirectorio (el propio directorio), calcula el espacio de los archivos
        total_size=$(du -sh "$directory" | cut -f1)
        echo "Espacio usado por archivos en $directory: $total_size"
    else
        # Si hay más de un subdirectorio, muestra el espacio de cada uno
        for userdir in "$directory"/*; do
            # Si el directorio existe y no es un enlace simbólico
            if [ -d "$userdir" ] && [ ! -L "$userdir" ]; then
                # Obtiene el nombre del usuario a partir del nombre del directorio
                username=$(basename "$userdir")
                # Usa du para calcular el tamaño del directorio del usuario
                size=$(du -sh "$userdir" | cut -f1)
                echo "$username: $size"
            fi
        done
    fi
else
    echo "La ruta proporcionada no es un directorio válido o es un enlace simbólico."
fi
