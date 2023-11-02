#!/bin/bash

# Obtener la lista de volúmenes lógicos, físicos o particiones
IFS=$'\n'
vol_list=($(lvs -o lv_path 2>/dev/null | grep -v "Path" | sed 's/[^/[:alnum:]]//g'))
vol_list+=($(pvs -o pv_name 2>/dev/null | grep -v "PV" | sed 's/[^/[:alnum:]]//g'))
vol_list+=($(lsblk --paths --output NAME,FSTYPE | grep -E 'ext[2-4]|xfs' | awk '{print $1}' | grep -Eo '[a-z\/].+'))
for i in "${!vol_list[@]}"; do
    vol_list[$i]="${vol_list[$i]}"
done
unset IFS

# Verificar que se encontró al menos un volumen o partición
if [ ${#vol_list[@]} -eq 0 ]; then
    echo "No se encontraron volúmenes lógicos, físicos o particiones en el sistema."
    exit 1
fi

# Mostrar la lista de volúmenes y particiones disponibles
echo "Selecciona un volumen o partición para ampliar:"
for i in "${!vol_list[@]}"; do
    echo "$((i+1)). ${vol_list[$i]}"
done

# Leer el índice del volumen o partición a ampliar
read -p "Introduce el número de volumen o partición que deseas ampliar: " vol_idx
vol_idx=$((vol_idx-1))

# Verificar que el índice es válido
if [ $vol_idx -lt 0 ] || [ $vol_idx -ge ${#vol_list[@]} ]; then
    echo "Número de volumen o partición inválido"
    exit 1
fi

# Obtener el nombre del volumen o partición seleccionado
nombre_volumen="${vol_list[$vol_idx]}"

# Verificar si es un volumen lógico, físico o una partición
es_volumen_logico=$(lvdisplay "$nombre_volumen" 2>/dev/null)
es_volumen_fisico=$(pvdisplay "$nombre_volumen" 2>/dev/null)
es_particion=$(lsblk -o NAME,FSTYPE | grep "$(basename "$nombre_volumen")" | awk '{print $2}')

# Mostrar un mensaje de confirmación antes de realizar la operación de ampliación
echo "¿Estás seguro de que deseas ampliar $nombre_volumen al 100% del espacio disponible en el disco?"
read -p "(s/n): " confirmacion
if [ "$confirmacion" != "s" ]; then
    echo "Operación cancelada"
    exit 0
fi

# Ampliar el volumen o partición seleccionado
if [ -n "$es_volumen_logico" ]; then
    echo "Ampliando el volumen lógico $nombre_volumen al 100% del espacio disponible en el disco..."
    lvextend -l +100%FREE "$nombre_volumen"
    if [ $? -eq 0 ]; then
        echo "Volumen lógico $nombre_volumen ampliado con éxito al 100% del espacio disponible en el disco"
    else
        echo "Error al ampliar el volumen lógico $nombre_volumen"
        exit 1
    fi
elif [ -n "$es_volumen_fisico" ]; then
    echo "Ampliando el volumen físico $nombre_volumen al 100% del espacio disponible en el disco..."
    pvresize "$nombre_volumen"
    if [ $? -eq 0 ]; then
        echo "Volumen físico $nombre_volumen ampliado con éxito al 100% del espacio disponible en el disco"
    else
        echo "Error al ampliar el volumen físico $nombre_volumen"
        exit 1
    fi
elif [ -n "$es_particion" ]; then
    echo "Ampliando la partición $nombre_volumen al 100% del espacio disponible en el disco..."
    if [[ $es_particion == ext[2-4] ]]; then
        resize2fs "$nombre_volumen"
    elif [[ $es_particion == "xfs" ]]; then
        xfs_growfs "$nombre_volumen"
    else
        echo "El sistema de archivos $es_particion no es compatible con el script."
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "Partición $nombre_volumen ampliada con éxito al 100% del espacio disponible en el disco"
    else
        echo "Error al ampliar la partición $nombre_volumen"
        exit 1
    fi
else
    echo "El volumen o partición $nombre_volumen no es válido"
    exit 1
fi
