#!/bin/bash
# Script para ampliar discos en Linux (Ubuntu) de forma automática
# Soporta particiones estándar y LVM, detecta el disco extendido virtualmente,
# utiliza growpart para redimensionar la partición (manejando GPT) y expande LVM/sistema de ficheros.
#
# ¡IMPORTANTE!: Este script modifica la tabla de particiones y el sistema de ficheros.
# REALIZA COPIAS DE SEGURIDAD COMPLETAS y PRUEBAS EXHAUSTIVAS en entornos
# controlados IDÉNTICOS a producción antes de usar. Úsalo bajo tu propio riesgo.
#
# Requisitos:
#   - Ejecutar como root.
#   - Sistema Operativo: Ubuntu (probado en versiones LTS recientes).
#   - Paquetes instalados: parted, blockdev, lsblk, blkid, lvm2 (pvs, lvs, pvresize, lvextend),
#                        e2fsprogs (resize2fs), xfsprogs (xfs_growfs), util-linux (findmnt, partprobe),
#                        cloud-guest-utils (growpart), coreutils (awk, grep, sed, etc.).
#   - Instalar growpart: sudo apt update && sudo apt install cloud-guest-utils

set -euo pipefail # Salir en error, variable no definida, error en pipe

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

warn() {
    echo "[WARN] $1"
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
# Se añade growpart, se asumen pvs/lvs/pvresize/lvextend vienen con lvm2
REQUIRED_CMDS=(parted blockdev lsblk blkid pvresize lvextend resize2fs xfs_growfs partprobe findmnt pvs lvs growpart awk grep sed)
MISSING_CMDS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    error "Faltan comandos requeridos: ${MISSING_CMDS[*]}. Asegúrate de que los paquetes lvm2, e2fsprogs, xfsprogs, util-linux, cloud-guest-utils están instalados."
fi

info "Validación del entorno completada."

##############################
# Paso 1: Reescanear dispositivos SCSI (Buena práctica)
##############################
log_banner "REESCANEANDO DISPOSITIVOS SCSI"
RESCAN_PERFORMED=false
if ls /sys/class/scsi_host/host* &>/dev/null; then
    for host in /sys/class/scsi_host/host*; do
        if [ -f "$host/scan" ]; then
            info "Reescaneando $host..."
            echo "- - -" > "$host/scan"
            RESCAN_PERFORMED=true
        fi
    done
fi
# Para discos virtuales (virtio), a veces el rescan anterior no es suficiente
# o no aplica. Forzar relectura del tamaño puede ser útil.
# No se añade un comando específico aquí, confiando en que el SO/hypervisor
# ya ha notificado el cambio de tamaño, o que los pasos posteriores lo detectarán.
if [ "$RESCAN_PERFORMED" = true ]; then
    info "Reescaneo de hosts SCSI completado. Esperando sincronización..."
    sleep 3 # Dar tiempo a udev/kernel
else
    info "No se encontraron hosts SCSI estándar para reescanear (puede ser normal para NVMe/VirtIO)."
fi


##############################
# Paso 2: Determinar la configuración del sistema
##############################
log_banner "DETERMINANDO CONFIGURACIÓN DEL SISTEMA"

# Detectar el dispositivo que contiene la raíz
ROOT_DEV=$(findmnt -n -o SOURCE /) || error "No se pudo determinar el dispositivo raíz."
info "Dispositivo raíz detectado: $ROOT_DEV"

# Detectar si se usa LVM
IS_LVM=false
VG_NAME=""
PV_DEVICE="" # El PV que realmente reside en la partición física a ampliar
LV_DEVICE="$ROOT_DEV" # El LV raíz

if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
    IS_LVM=true
    info "Sistema configurado con LVM."
    # Extraer el nombre del LV del path /dev/mapper/VG-LV
    LV_NAME=$(basename "$ROOT_DEV")
    # Obtener el nombre del grupo de volúmenes (VG) a partir del LV raíz
    VG_NAME=$(lvs --noheadings -o vg_name "$ROOT_DEV" | awk '{print $1}') || error "No se pudo obtener el VG de $ROOT_DEV."
    info "Grupo de Volúmenes (VG): $VG_NAME"
    info "Volumen Lógico (LV) raíz: $LV_NAME"

    # Obtener TODOS los volúmenes físicos (PV) asociados al VG
    PV_LIST=($(pvs --noheadings -o pv_name --select vgname="$VG_NAME"))
    if [ ${#PV_LIST[@]} -eq 0 ]; then
        error "No se encontró ningún PV para el VG $VG_NAME."
    fi
    info "PVs en el VG $VG_NAME: ${PV_LIST[*]}"

    # Estrategia: Asumimos que la partición a ampliar es la que contiene *uno* de los PVs del VG raíz.
    # Normalmente es la última partición del disco principal. Intentamos identificarla.
    # Buscamos un PV que NO sea un disco completo (sino una partición).
    CANDIDATE_PART=""
    for pv in "${PV_LIST[@]}"; do
        # Comprobar si el PV es una partición (contiene número al final)
        if [[ "$pv" =~ ^/dev/([a-zA-Z]+|nvme[0-9]+n[0-9]+)p?[0-9]+$ ]]; then
            # Es una partición, usarla como candidata
            # Si hay múltiples PVs en particiones, esta lógica podría necesitar ajuste
            # pero para el caso común de un solo PV en una partición para el SO, esto funciona.
             if [ -z "$CANDIDATE_PART" ]; then # Tomar la primera partición encontrada
                CANDIDATE_PART="$pv"
            else
                warn "Múltiples PVs en particiones encontrados en VG $VG_NAME (${PV_LIST[*]}). Usando el primero: $CANDIDATE_PART. Si el espacio se añadió a otro disco/partición, este script podría fallar."
                # Podríamos intentar una heurística más avanzada aquí si fuera necesario
                # como buscar la partición con el número más alto en el disco sda/nvme0n1.
             fi
        fi
    done

    if [ -z "$CANDIDATE_PART" ]; then
         # Quizás el PV es el disco entero? (Menos común para SO, pero posible)
         # O quizás todos los PVs están en otros discos no relacionados con el boot?
         error "No se pudo identificar una partición PV adecuada en el VG $VG_NAME para ampliar."
    fi
    PV_DEVICE="$CANDIDATE_PART" # El PV que reside en la partición física
    info "PV seleccionado para ampliación (reside en la partición a redimensionar): $PV_DEVICE"
else
    info "Sistema sin LVM detectado (partición estándar para raíz)."
    CANDIDATE_PART="$ROOT_DEV"
fi

# Determinar el disco padre de la partición candidata.
# Ejemplos: /dev/sda3 -> /dev/sda; /dev/nvme0n1p2 -> /dev/nvme0n1
DISK=""
PART_NUM=""
if [[ "$CANDIDATE_PART" =~ ^(/dev/(nvme[0-9]+n[0-9]+))p([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[3]}"
elif [[ "$CANDIDATE_PART" =~ ^(/dev/([a-zA-Z]+))([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
    PART_NUM="${BASH_REMATCH[3]}"
else
    error "No se pudo determinar el disco padre y número de partición desde: $CANDIDATE_PART"
fi

if [ -z "$DISK" ] || [ -z "$PART_NUM" ]; then
     error "No se pudo extraer el disco o número de partición desde $CANDIDATE_PART."
fi

# Validar que el disco y la partición existen
if ! [ -b "$DISK" ]; then error "El disco '$DISK' no existe o no es un dispositivo de bloque."; fi
if ! [ -b "$CANDIDATE_PART" ]; then error "La partición '$CANDIDATE_PART' no existe o no es un dispositivo de bloque."; fi


info "Disco a verificar/ampliar: $DISK"
info "Partición a redimensionar: $CANDIDATE_PART (Número: $PART_NUM)"

##############################
# Paso 3: Verificar espacio libre en el disco físico
##############################
log_banner "VERIFICANDO ESPACIO LIBRE EN DISCO FÍSICO"

# Forzar relectura del tamaño del disco físico
info "Forzando relectura del tamaño de $DISK..."
blockdev --rereadpt "$DISK" || warn "blockdev --rereadpt falló para $DISK (puede no ser crítico)."
sleep 1

# Obtener el tamaño total del disco en bytes (después de relectura)
DISK_SIZE=$(blockdev --getsize64 "$DISK") || error "No se pudo obtener el tamaño de $DISK."
info "Tamaño actual detectado de $DISK: $DISK_SIZE bytes"

# Obtener el final de la partición usando parted en modo máquina y unidades de bytes
# Usamos 'print' en lugar de 'print free' para obtener detalles de la partición existente
PARTED_OUT=$(parted -ms "$DISK" unit B print 2>/dev/null) || error "Error al obtener información de particiones de $DISK con parted."

# Buscar la línea correspondiente a nuestra partición
# Formato: Número:InicioB:FinB:TamañoB:TipoFS:NombrePart:Flags;
PART_LINE=$(echo "$PARTED_OUT" | grep -E "^${PART_NUM}:")
if [ -z "$PART_LINE" ]; then
    # A veces, la partición puede no tener un número simple si hay Gaps o si es LVM sobre disco entero (no aplica aquí)
    # Reintentar buscando por el path del dispositivo si el número falla
    PART_LINE=$(echo "$PARTED_OUT" | grep -E ":${CANDIDATE_PART//\//\\/}:") # Buscar por el path escapado
    if [ -z "$PART_LINE" ]; then
       error "No se encontró información para la partición $PART_NUM ($CANDIDATE_PART) en $DISK usando parted."
    fi
fi
info "Línea de partición encontrada: $PART_LINE"

# Extraer el final de la partición (tercer campo, quitar la 'B' al final)
PART_END_STR=$(echo "$PART_LINE" | cut -d':' -f3)
PART_END=${PART_END_STR%B}

if ! [[ "$PART_END" =~ ^[0-9]+$ ]]; then
    error "El valor de fin de partición ('$PART_END_STR' -> '$PART_END') no es numérico."
fi
info "La partición ${CANDIDATE_PART} finaliza actualmente en: $PART_END bytes"

# Calcular el espacio libre *después* de la partición
# Nota: GPT usa un pequeño espacio al final para la tabla de respaldo.
# growpart usualmente maneja esto, pero calculamos el espacio bruto.
FREE_SPACE=$(( DISK_SIZE - PART_END ))
# Ajuste menor: Considerar el espacio para la GPT backup (~17KB o 34 sectores)
# No es estrictamente necesario para la lógica de growpart, pero para info
GPT_RESERVED=$(( 34 * 512 )) # Asumiendo sectores de 512B
EFFECTIVE_FREE_SPACE=$(( FREE_SPACE > GPT_RESERVED ? FREE_SPACE - GPT_RESERVED : 0 ))

info "Espacio bruto detectado después de la partición: $FREE_SPACE bytes"
info "Espacio efectivo estimado disponible para expansión: $EFFECTIVE_FREE_SPACE bytes"

MIN_FREE=10485760 # Requerir al menos 10 MB de espacio libre para intentar la expansión
if [ "$EFFECTIVE_FREE_SPACE" -lt "$MIN_FREE" ]; then
    info "No hay suficiente espacio libre significativo detectado en $DISK después de la partición $PART_NUM para justificar una expansión."
    info "Operación finalizada. No se realizaron cambios."
    exit 0
fi

info "Espacio libre suficiente detectado. Procediendo con la expansión."

##############################
# Paso 4: Redimensionar la partición física con growpart
##############################
log_banner "REDIMENSIONANDO PARTICIÓN FÍSICA CON GROWPART"

info "Intentando redimensionar la partición $PART_NUM en el disco $DISK usando growpart..."
# growpart <disk_device> <partition_number>
if growpart_output=$(growpart "$DISK" "$PART_NUM" 2>&1); then
    info "growpart ejecutado exitosamente para $DISK $PART_NUM."
    info "Salida de growpart: $growpart_output"
else
    # Verificar si falló porque no había cambio (código de salida 1 con "NOCHANGE")
    if [[ "$growpart_output" == *"NOCHANGE"* ]]; then
        info "growpart indica que la partición $PART_NUM en $DISK ya está en su tamaño máximo o no se pudo cambiar."
        info "Salida de growpart: $growpart_output"
        # Consideramos esto no fatal, puede que LVM o FS necesiten ajuste aún.
    else
        # Otro tipo de error
        error "growpart falló para $DISK $PART_NUM. Código de salida: $?. Salida: $growpart_output"
    fi
fi

# Informar al kernel sobre el cambio en la tabla de particiones
info "Solicitando al kernel que relea la tabla de particiones de $DISK..."
partprobe "$DISK" || warn "partprobe falló después de growpart (puede requerir reinicio para que algunos sistemas vean el cambio)."
sleep 3 # Dar tiempo extra para que el sistema se actualice

info "Redimensionamiento de la partición física completado (o no fue necesario)."

##############################
# Paso 5: Expandir LVM (si aplica) y Sistema de Ficheros
##############################
log_banner "EXPANDIENDO LVM Y/O SISTEMA DE FICHEROS"

FS_RESIZE_TARGET="" # El dispositivo/path que necesita el resize del FS
MOUNT_POINT="/"     # Default a root, se refinará

if [ "$IS_LVM" = true ]; then
    info "Actualizando el Volumen Físico (PV) $PV_DEVICE para reconocer el nuevo tamaño..."
    if pvresize "$PV_DEVICE"; then
        info "pvresize completado para $PV_DEVICE."
    else
        # pvresize puede fallar si la partición subyacente no creció realmente
        # o si hay algún otro problema. Lo registramos como advertencia y continuamos
        # hacia lvextend, que fallará si no hay espacio libre en el VG.
        warn "pvresize falló o no encontró cambios para $PV_DEVICE. Verificando VG/LV de todos modos."
    fi

    # Mostrar espacio libre en VG antes de extender LV
    info "Espacio disponible en VG $VG_NAME antes de lvextend:"
    vgs "$VG_NAME" --units b

    info "Extendiendo el Volumen Lógico (LV) $LV_DEVICE para usar todo el espacio libre disponible en $VG_NAME..."
    # Usar -l +100%FREE es la forma estándar de usar todo el espacio nuevo en el VG
    if lvextend -l +100%FREE "$LV_DEVICE"; then
        info "lvextend completado para $LV_DEVICE."
    else
        # Si falla, puede ser porque no había espacio libre (pvresize no encontró más espacio)
        # o por otro motivo.
        warn "lvextend falló o no encontró espacio libre para $LV_DEVICE. El sistema de ficheros no será expandido."
        # No continuamos a la expansión del FS si lvextend falla.
        # Podemos mostrar el df final y salir.
        log_banner "RESULTADOS PARCIALES (LV no extendido)"
        lsblk "$DISK"
        df -hT "$MOUNT_POINT" || df -hT / # Fallback si findmnt falla
        error "No se pudo extender el Volumen Lógico. La operación no se completó." # Salir con error para indicar fallo
    fi
    FS_RESIZE_TARGET="$LV_DEVICE" # El FS está en el LV
    MOUNT_POINT=$(findmnt -n -o TARGET "$FS_RESIZE_TARGET") || MOUNT_POINT="/"

else
    # Caso de partición estándar
    info "Sistema sin LVM. El sistema de ficheros reside directamente en $CANDIDATE_PART."
    FS_RESIZE_TARGET="$CANDIDATE_PART" # El FS está en la partición
    MOUNT_POINT=$(findmnt -n -o TARGET "$FS_RESIZE_TARGET") || MOUNT_POINT="/"
fi

info "El sistema de ficheros a redimensionar está en: $FS_RESIZE_TARGET"
info "Punto de montaje asociado: $MOUNT_POINT"

# Ahora, redimensionar el sistema de ficheros
FS_TYPE=$(blkid -s TYPE -o value "$FS_RESIZE_TARGET" 2>/dev/null) || error "No se pudo detectar el tipo de sistema de ficheros en $FS_RESIZE_TARGET."
info "Tipo de sistema de ficheros detectado: $FS_TYPE"

case "$FS_TYPE" in
    ext2|ext3|ext4)
        info "Redimensionando sistema de ficheros $FS_TYPE en $FS_RESIZE_TARGET..."
        if resize2fs "$FS_RESIZE_TARGET"; then
            info "resize2fs completado exitosamente."
        else
            error "resize2fs falló para $FS_RESIZE_TARGET."
        fi
        ;;
    xfs)
        info "Redimensionando sistema de ficheros XFS montado en $MOUNT_POINT..."
        # xfs_growfs opera sobre el punto de montaje
        if [ -z "$MOUNT_POINT" ] || [ "$MOUNT_POINT" == "none" ]; then
             error "No se pudo determinar el punto de montaje para XFS en $FS_RESIZE_TARGET."
        fi
        if xfs_growfs "$MOUNT_POINT"; then
            info "xfs_growfs completado exitosamente para $MOUNT_POINT."
        else
            error "xfs_growfs falló para $MOUNT_POINT."
        fi
        ;;
    *)
        error "Sistema de ficheros '$FS_TYPE' no soportado para redimensionamiento automático por este script."
        ;;
esac

##############################
# Paso 6: Resultados finales
##############################
log_banner "RESULTADOS FINALES"

info "Mostrando nueva distribución del disco $DISK:"
lsblk "$DISK"

info "Mostrando uso del sistema de ficheros en $MOUNT_POINT:"
df -hT "$MOUNT_POINT"

if [ "$IS_LVM" = true ]; then
    info "Mostrando estado del Grupo de Volúmenes $VG_NAME:"
    vgs "$VG_NAME"
    info "Mostrando estado del Volumen Lógico $LV_DEVICE:"
    lvs "$LV_DEVICE"
fi

log_banner "OPERACIÓN COMPLETADA"
info "La expansión del disco y sistema de ficheros parece haberse completado exitosamente."
info "Aunque no siempre es estrictamente necesario, un reinicio puede ser recomendable en algunos casos."

exit 0
