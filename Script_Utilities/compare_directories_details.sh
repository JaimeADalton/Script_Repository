#!/bin/bash

# Función para verificar si la respuesta es afirmativa
es_afirmativo() {
    case "$1" in
        [yY]|[yY][eE][sS]|[sS][iI]|[sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Pedir al usuario si desea ver los archivos iguales
echo -n "¿Quieres que muestre los archivos iguales? [n]: "
read mostrar_iguales
mostrar_iguales=${mostrar_iguales:-n}

# Verificar si se proporcionaron dos directorios
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 directorio1 directorio2"
    exit 1
fi

dir1=$1
dir2=$2

# Verificar si ambos argumentos son directorios
if [ ! -d "$dir1" ] || [ ! -d "$dir2" ]; then
    echo "Ambos argumentos deben ser directorios válidos."
    exit 1
fi

# Función para obtener tamaño y fecha de modificación de un archivo
file_details() {
    local file=$1
    local size=$(stat -c%s "$file")
    local date=$(stat -c%y "$file")
    printf "Tamaño: %s bytes, Fecha de Modificación: %s\n" "$size" "$date"
}

# Función para generar hashes y nombres de archivos
generate_hashes() {
    find "$1" -type f -exec sha1sum {} \; | awk '{print $1 " " $2}' | sort
}

# Generar hashes para ambos directorios
hashes_dir1=$(generate_hashes "$dir1")
hashes_dir2=$(generate_hashes "$dir2")

# Comparar archivos
echo "Comparando archivos..."

while read -r line; do
    hash=$(echo "$line" | cut -d ' ' -f 1)
    file=$(echo "$line" | cut -d ' ' -f 2-)

    if grep -q "$hash" <<< "$hashes_dir2"; then
        if es_afirmativo "$mostrar_iguales"; then
            echo "Igual: $file"
        fi
    else
        echo -e "\nDiferente: $file"
        echo "Detalles de $file:"
        echo "$(file_details "$file")"

        # Buscar y mostrar detalles del archivo correspondiente en el otro directorio
        counterpart=$(grep -m 1 "/$(basename "$file")$" <<< "$hashes_dir2" | cut -d ' ' -f 2-)
        if [ ! -z "$counterpart" ]; then
            echo -e "\nArchivo correspondiente en $dir2: $counterpart"
            echo "Detalles de $counterpart:"
            echo "$(file_details "$counterpart")"
        else
            echo -e "\nNo se encontró un archivo correspondiente en $dir2"
        fi
    fi
done <<< "$hashes_dir1"
