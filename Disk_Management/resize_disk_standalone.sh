#!/bin/bash
# Navaja suiza definitiva para ampliar discos en Linux de forma 100% automática
# Soporta particiones estándar y LVM, detecta el disco extendido virtualmente,
# redimensiona la partición y expande el sistema de ficheros.
#
# ¡IMPORTANTE!: Este script modifica la tabla de particiones y el sistema de ficheros.
# Realiza copias de seguridad y pruebas en entornos controlados antes de usar en producción.
#
# Requisitos:
#   - Ejecutar como root.
#   - Tener instalados: parted, blockdev, lsblk, blkid, pvresize, lvextend,
#                        resize2fs, xfs_growfs, partprobe, findmnt, pvs, lvs, awk, grep, sed.

set -euo pipefail

##############################
# Funciones de logging
##############################
log_banner() {
    echo "============================================================"
    echo "== $1"
    echo "============================================================"
}

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

##############################
# Validación del entorno
##############################
log_banner "VALIDANDO ENTORNO"

# Se debe ejecutar como root
if [ "$(id -u)" -ne 0 ]; then
    error "El script debe ejecutarse como root."
fi

# Verificar comandos requeridos
REQUIRED_CMDS=(parted blockdev lsblk blkid pvresize lvextend resize2fs xfs_growfs partprobe findmnt pvs lvs awk grep sed)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        error "El comando '$cmd' es requerido y no está instalado."
    fi
done

##############################
# Paso 1: Reescanear dispositivos SCSI
##############################
log_banner "REESCANEANDO DISPOSITIVOS SCSI"
if ls /sys/class/scsi_disk/* &>/dev/null; then
    for dev in /sys/class/scsi_disk/*; do
        [ -e "$dev/device/rescan" ] && echo 1 > "$dev/device/rescan"
    done
    info "Reescaneo de dispositivos SCSI completado."
else
    info "No se encontraron dispositivos SCSI para reescaneo."
fi
sleep 1

##############################
# Paso 2: Determinar la configuración del sistema
##############################
log_banner "DETERMINANDO CONFIGURACIÓN DEL SISTEMA"

# Detectar el dispositivo que contiene la raíz
ROOT_DEV=$(findmnt -n -o SOURCE /) || error "No se pudo determinar el dispositivo raíz."
info "Dispositivo raíz: $ROOT_DEV"

# Detectar si se usa LVM
IS_LVM=false
if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
    IS_LVM=true
    info "Sistema configurado con LVM."
    # Obtener el nombre del grupo de volúmenes (VG) a partir del LV raíz
    VG_NAME=$(lvs --noheadings -o vg_name "$ROOT_DEV" | awk '{print $1}') || error "No se pudo obtener el VG de $ROOT_DEV."
    info "Grupo de volúmenes: $VG_NAME"
    # Seleccionar el primer volumen físico (PV) asociado al VG
    CANDIDATE_PART=$(pvs --noheadings -o pv_name --select vgname="$VG_NAME" | awk '{print $1}' | head -n1)
    [ -z "$CANDIDATE_PART" ] && error "No se encontró un PV para el VG $VG_NAME."
    info "PV detectado: $CANDIDATE_PART"
else
    info "Sistema sin LVM; se usará el dispositivo raíz como partición candidata."
    CANDIDATE_PART="$ROOT_DEV"
fi

# Determinar el disco padre de la partición candidata.
# Para NVMe: /dev/nvme0n1p3 → /dev/nvme0n1; para otros: /dev/sda3 → /dev/sda.
if [[ "$CANDIDATE_PART" =~ ^/dev/(nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
    DISK="/dev/${BASH_REMATCH[1]}"
elif [[ "$CANDIDATE_PART" =~ ^/dev/([a-zA-Z]+)[0-9]+$ ]]; then
    DISK="/dev/${BASH_REMATCH[1]}"
else
    error "No se pudo determinar el disco padre de $CANDIDATE_PART."
fi
info "Disco a ampliar: $DISK"

# Extraer el número de partición de la candidata
if [[ "$CANDIDATE_PART" =~ ([0-9]+)$ ]]; then
    PART_NUM="${BASH_REMATCH[1]}"
    info "Número de partición a ampliar: $PART_NUM"
else
    error "No se pudo extraer el número de partición de $CANDIDATE_PART."
fi

##############################
# Paso 3: Verificar espacio libre en el disco
##############################
log_banner "VERIFICANDO ESPACIO LIBRE"

# Obtener el tamaño total del disco en bytes
DISK_SIZE=$(blockdev --getsize64 "$DISK") || error "No se pudo obtener el tamaño de $DISK."
info "Tamaño total de $DISK: $DISK_SIZE bytes"

# Forzar a parted a emitir la salida en bytes.
# Se usa la opción 'unit B' en modo máquina (-ms) para obtener valores en bytes.
PARTED_OUT=$(parted -ms "$DISK" unit B print 2>/dev/null) || error "Error al obtener información de $DISK con parted."

# La salida tiene líneas separadas por ':'
# Buscamos la línea que comience con el número de partición
PART_LINE=$(echo "$PARTED_OUT" | grep -E "^${PART_NUM}:" || true)
if [ -z "$PART_LINE" ]; then
    error "No se encontró información para la partición $PART_NUM en $DISK."
fi
info "Línea de partición encontrada: $PART_LINE"

# La línea tiene el formato:
#   Número:Inicio:Fin:Tamaño:Tipo:FS:Flags
IFS=":" read -r pnum pstart pend psize ptype pfs pflags <<< "$PART_LINE"

# 'pend' debe terminar con una "B". Quitamos la "B" para obtener el número.
PART_END=${pend%B}
if ! [[ "$PART_END" =~ ^[0-9]+$ ]]; then
    error "El valor de fin de partición ('$pend') no es numérico."
fi
info "La partición ${CANDIDATE_PART} finaliza en: $PART_END bytes"

# Calcular el espacio libre
FREE_SPACE=$(( DISK_SIZE - PART_END ))
info "Espacio libre detectado: $FREE_SPACE bytes"

MIN_FREE=1048576  # 1 MB mínimo
if [ "$FREE_SPACE" -lt "$MIN_FREE" ]; then
    info "No hay espacio libre suficiente en $DISK para ampliar la partición."
    exit 0
fi

##############################
# Paso 4: Redimensionar la partición
##############################
log_banner "REDIMENSIONANDO LA PARTICIÓN"

info "Redimensionando la partición $PART_NUM en $DISK para ocupar el 100% del disco..."
# Se envía "Yes" para confirmar si es requerido
echo "Yes" | parted -s "$DISK" resizepart "$PART_NUM" 100% \
    || error "Error al redimensionar la partición."
info "Partición redimensionada correctamente."
partprobe "$DISK"
sleep 2

##############################
# Paso 5: Expandir el sistema de ficheros
##############################
log_banner "EXPANDIENDO SISTEMA DE FICHEROS"

if [ "$IS_LVM" = true ]; then
    info "Actualizando el volumen físico (PV) en $CANDIDATE_PART..."
    pvresize "$CANDIDATE_PART" || error "pvresize falló en $CANDIDATE_PART."
    
    info "Extendiendo el volumen lógico (LV) $ROOT_DEV al 100% del espacio libre..."
    lvextend -l +100%FREE "$ROOT_DEV" || error "lvextend falló en $ROOT_DEV."
    
    FS_TYPE=$(blkid -s TYPE -o value "$ROOT_DEV" 2>/dev/null) || error "No se pudo detectar el sistema de ficheros en $ROOT_DEV."
    info "Tipo de sistema de ficheros en LV: $FS_TYPE"
    
    if [[ "$FS_TYPE" == "xfs" ]]; then
        MOUNT_POINT=$(findmnt -n -o TARGET "$ROOT_DEV" || echo "/")
        info "Redimensionando XFS en $MOUNT_POINT..."
        xfs_growfs "$MOUNT_POINT" || error "xfs_growfs falló en $MOUNT_POINT."
    elif [[ "$FS_TYPE" =~ ^ext[2-4]$ ]]; then
        info "Redimensionando sistema de ficheros ext en $ROOT_DEV..."
        resize2fs "$ROOT_DEV" || error "resize2fs falló en $ROOT_DEV."
    else
        error "Sistema de ficheros no soportado: $FS_TYPE"
    fi

else
    # Caso de partición estándar
    FS_TYPE=$(blkid -s TYPE -o value "$CANDIDATE_PART" 2>/dev/null) || error "No se pudo detectar el sistema de ficheros en $CANDIDATE_PART."
    info "Tipo de sistema de ficheros en partición: $FS_TYPE"
    
    MOUNT_POINT=$(findmnt -n -o TARGET "$CANDIDATE_PART") || error "No se pudo determinar el punto de montaje de $CANDIDATE_PART."
    if [[ "$FS_TYPE" == "xfs" ]]; then
        info "Redimensionando XFS en $MOUNT_POINT..."
        xfs_growfs "$MOUNT_POINT" || error "xfs_growfs falló en $MOUNT_POINT."
    elif [[ "$FS_TYPE" =~ ^ext[2-4]$ ]]; then
        info "Redimensionando sistema de ficheros ext en $CANDIDATE_PART..."
        resize2fs "$CANDIDATE_PART" || error "resize2fs falló en $CANDIDATE_PART."
    else
        error "Sistema de ficheros no soportado: $FS_TYPE"
    fi
fi

##############################
# Paso 6: Resultados finales
##############################
log_banner "RESULTADOS FINALES"

info "Nueva distribución de $DISK:"
lsblk "$DISK"

if [ "$IS_LVM" = true ]; then
    MOUNT_POINT=$(findmnt -n -o TARGET "$ROOT_DEV" || echo "/")
else
    MOUNT_POINT=$(findmnt -n -o TARGET "$CANDIDATE_PART")
fi
info "Uso del sistema de ficheros en $MOUNT_POINT:"
df -h "$MOUNT_POINT"

log_banner "OPERACIÓN COMPLETADA"
info "La expansión del disco se completó exitosamente. Se recomienda reiniciar el sistema."

exit 0
