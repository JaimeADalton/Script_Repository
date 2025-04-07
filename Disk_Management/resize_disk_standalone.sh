#!/bin/bash
# Script para ampliar discos en Linux (Ubuntu) de forma automática (v5 - Confiar en growpart)
# Soporta particiones estándar y LVM, detecta el disco extendido virtualmente,
# utiliza growpart para intentar redimensionar la partición y expande LVM/sistema de ficheros.
# Ejecución en caliente soportada. Elimina la verificación previa con parted print.
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
#                        cloud-guest-utils (growpart), coreutils (awk, grep, sed, sleep, sync, etc.).
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

if [ "$(id -u)" -ne 0 ]; then error "El script debe ejecutarse como root."; fi

# Nota: Se quita timeout de los requisitos ya que no se usa parted print con él
REQUIRED_CMDS=(parted blockdev lsblk blkid pvresize lvextend resize2fs xfs_growfs partprobe findmnt pvs lvs growpart awk grep sed sleep sync)
MISSING_CMDS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then MISSING_CMDS+=("$cmd"); fi
done
if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    error "Faltan comandos requeridos: ${MISSING_CMDS[*]}. Instala los paquetes necesarios."
fi
info "Validación del entorno completada."

##############################
# Paso 1: Reescanear dispositivos (Mejor esfuerzo)
##############################
log_banner "REESCANEANDO DISPOSITIVOS SCSI (Mejor Esfuerzo)"
RESCAN_ATTEMPTED=false
if ls /sys/class/scsi_host/host* &>/dev/null; then
    for host in /sys/class/scsi_host/host*; do
        if [ -f "$host/scan" ]; then
            RESCAN_ATTEMPTED=true
            info "Reescaneando $host..."
            # Usamos timeout aquí por si el escaneo se cuelga
            if ! timeout 10 bash -c "echo '- - -' > \"$host/scan\""; then
                 warn "Timeout/error reescaneando $host."
            fi
        fi
    done
fi
# Forzar partprobe temprano
info "Ejecutando sync y partprobe inicial para intentar actualizar la vista del kernel..."
sync
# Desactivar -e temporalmente para partprobe, ya que puede fallar si no hay cambios
set +e
partprobe
PARTPROBE_EXIT_CODE=$?
set -e
if [ $PARTPROBE_EXIT_CODE -ne 0 ]; then warn "Partprobe inicial falló (código $PARTPROBE_EXIT_CODE)."; fi
sleep 2
if [ "$RESCAN_ATTEMPTED" = true ]; then info "Reescaneo SCSI intentado."; else info "No se encontraron hosts SCSI estándar."; fi


##############################
# Paso 2: Determinar la configuración del sistema
##############################
log_banner "DETERMINANDO CONFIGURACIÓN DEL SISTEMA"

ROOT_DEV=$(findmnt -n -o SOURCE /) || error "No se pudo determinar el dispositivo raíz."
info "Dispositivo raíz detectado: $ROOT_DEV"

IS_LVM=false
VG_NAME=""
PV_DEVICE=""
LV_DEVICE="$ROOT_DEV"

if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
    IS_LVM=true
    info "Sistema configurado con LVM."
    LV_NAME=$(basename "$ROOT_DEV")
    VG_NAME=$(lvs --noheadings -o vg_name "$ROOT_DEV" | awk '{print $1}') || error "No se pudo obtener el VG de $ROOT_DEV."
    info "Grupo de Volúmenes (VG): $VG_NAME"
    info "Volumen Lógico (LV) raíz: $LV_NAME"
    PV_LIST=($(pvs --noheadings -o pv_name --select vgname="$VG_NAME"))
    [ ${#PV_LIST[@]} -eq 0 ] && error "No se encontró ningún PV para el VG $VG_NAME."
    info "PVs en el VG $VG_NAME: ${PV_LIST[*]}"
    CANDIDATE_PART=""
    for pv in "${PV_LIST[@]}"; do
        # Busca PVs que sean particiones (terminan en número, opcionalmente precedido por 'p')
        if [[ "$pv" =~ ^/dev/([a-zA-Z0-9]+)p?[0-9]+$ ]]; then
             if [ -z "$CANDIDATE_PART" ]; then
                CANDIDATE_PART="$pv"
             else
                warn "Múltiples PVs en particiones encontrados en VG $VG_NAME (${PV_LIST[*]}). Usando el primero: $CANDIDATE_PART."
             fi
        fi
    done
    [ -z "$CANDIDATE_PART" ] && error "No se pudo identificar una partición PV adecuada en VG $VG_NAME para ampliar."
    PV_DEVICE="$CANDIDATE_PART"
    info "PV seleccionado (en partición a ampliar): $PV_DEVICE"
else
    info "Sistema sin LVM detectado."
    CANDIDATE_PART="$ROOT_DEV"
fi

DISK=""
PART_NUM=""
# Extraer disco y número de partición (más robusto)
if [[ "$CANDIDATE_PART" =~ ^/dev/(nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then DISK="/dev/${BASH_REMATCH[1]}"; PART_NUM="${BASH_REMATCH[2]}";
elif [[ "$CANDIDATE_PART" =~ ^/dev/([a-zA-Z]+)([0-9]+)$ ]]; then DISK="/dev/${BASH_REMATCH[1]}"; PART_NUM="${BASH_REMATCH[2]}";
else error "No se pudo determinar el disco padre/número de partición desde: $CANDIDATE_PART"; fi
[ -z "$DISK" ] || [ -z "$PART_NUM" ] && error "Disco o número de partición vacío tras extraer de $CANDIDATE_PART."
if ! [ -b "$DISK" ]; then error "Disco '$DISK' no encontrado o no es dispositivo de bloque."; fi
if ! [ -b "$CANDIDATE_PART" ]; then error "Partición '$CANDIDATE_PART' no encontrada o no es dispositivo de bloque."; fi

info "Disco a ampliar: $DISK"
info "Partición a intentar redimensionar: $CANDIDATE_PART (Número: $PART_NUM)"

###############################################################
# Paso 3: Intentar redimensionar la partición física con growpart
###############################################################
log_banner "INTENTANDO REDIMENSIONAR PARTICIÓN CON GROWPART"

info "Ejecutando sync antes de growpart..."
sync
sleep 1
info "Intentando redimensionar la partición $PART_NUM en el disco $DISK usando growpart..."
GROWPART_FAILED=false
if growpart_output=$(growpart "$DISK" "$PART_NUM" 2>&1); then
    info "growpart ejecutado exitosamente para $DISK $PART_NUM."
    info "Salida de growpart: $growpart_output"
    # Podría ser útil verificar si realmente cambió algo, pero NOCHANGE también es aceptable
    if [[ "$growpart_output" == *"CHANGED"* ]]; then
        info "growpart reportó que la partición fue modificada."
    elif [[ "$growpart_output" == *"NOCHANGE"* ]]; then
         info "growpart reportó NOCHANGE. La partición ya estaba al tamaño máximo o no se pudo modificar."
    fi
else
    growpart_exit_code=$?
    if [[ "$growpart_output" == *"NOCHANGE"* ]]; then
        # A veces NOCHANGE viene con código de salida 1, lo tratamos como no fatal
        info "growpart indica NOCHANGE (partición ya al tamaño máximo o no modificable)."
        info "Salida: $growpart_output"
    else
        # Otro tipo de error es fatal
        error "growpart falló para $DISK $PART_NUM. Código de salida: $growpart_exit_code. Salida: $growpart_output"
        GROWPART_FAILED=true # Marcar el fallo para posible lógica futura (actualmente error sale)
    fi
fi

# Si growpart falló catastróficamente, el script ya habría salido por el 'error'
info "Solicitando al kernel que relea la tabla de particiones de $DISK (post-growpart)..."
sync
set +e # Permitir fallo de partprobe
partprobe "$DISK"
PARTPROBE_EXIT_CODE=$?
set -e
if [ $PARTPROBE_EXIT_CODE -ne 0 ]; then warn "partprobe falló después de growpart (código $PARTPROBE_EXIT_CODE). Puede requerir reinicio."; fi
sleep 3

info "Intento de redimensionamiento de partición física completado."

##############################
# Paso 4: Expandir LVM (si aplica) y Sistema de Ficheros
##############################
log_banner "EXPANDIENDO LVM Y/O SISTEMA DE FICHEROS"

FS_RESIZE_TARGET=""
MOUNT_POINT="/"

if [ "$IS_LVM" = true ]; then
    info "Actualizando PV $PV_DEVICE..."
    sync
    if ! pvresize "$PV_DEVICE"; then
        # No considerar esto un error fatal inmediatamente
        warn "pvresize falló o no reportó cambios para $PV_DEVICE. Se continuará intentando extender el LV."
        pvs "$PV_DEVICE" # Mostrar estado del PV para diagnóstico
    else
        info "pvresize completado para $PV_DEVICE."
    fi

    info "Extendiendo LV $LV_DEVICE al 100% del espacio libre disponible en VG $VG_NAME..."
    sync
    # Verificar si hay espacio libre ANTES de intentar extender (más informativo)
    FREE_PE=$(vgs --noheadings -o vg_free_count "$VG_NAME" | awk '{print $1}')
    info "Extensiones físicas libres en VG $VG_NAME: $FREE_PE"
    if [[ "$FREE_PE" -gt 0 ]]; then
        if ! lvextend -l +100%FREE "$LV_DEVICE"; then
            lv_extend_exit_code=$?
            # Si lvextend falla AUNQUE había PEs libres, es un problema
            error "lvextend falló (código $lv_extend_exit_code) a pesar de detectar $FREE_PE PEs libres en $VG_NAME."
        else
            info "lvextend completado para $LV_DEVICE."
        fi
    else
        info "No hay extensiones físicas libres detectadas en VG $VG_NAME. No se ejecutará lvextend."
        # No es un error si no había espacio que añadir
    fi
    FS_RESIZE_TARGET="$LV_DEVICE"
    MOUNT_POINT=$(findmnt -n -o TARGET "$FS_RESIZE_TARGET") || MOUNT_POINT="/"

else
    info "Sistema sin LVM. FS reside en $CANDIDATE_PART."
    FS_RESIZE_TARGET="$CANDIDATE_PART"
    MOUNT_POINT=$(findmnt -n -o TARGET "$FS_RESIZE_TARGET") || MOUNT_POINT="/"
fi

info "FS a redimensionar: $FS_RESIZE_TARGET (Montado en: $MOUNT_POINT)"

# Redimensionar el FS *independientemente* de si lvextend reportó éxito,
# ya que a veces el FS necesita actualizarse incluso si el LV no cambió mucho.
FS_TYPE=$(blkid -s TYPE -o value "$FS_RESIZE_TARGET" 2>/dev/null) || warn "No se pudo detectar FS type en $FS_RESIZE_TARGET."

if [ -z "$FS_TYPE" ]; then
     error "Imposible continuar sin tipo de sistema de ficheros."
fi
info "Tipo de FS detectado: $FS_TYPE"

sync

case "$FS_TYPE" in
    ext2|ext3|ext4)
        info "Redimensionando FS $FS_TYPE en $FS_RESIZE_TARGET..."
        # Añadir -f por si acaso, y capturar salida/error
        set +e
        resize2fs_output=$(resize2fs -f "$FS_RESIZE_TARGET" 2>&1)
        resize2fs_exit_code=$?
        set -e
        if [ $resize2fs_exit_code -eq 0 ]; then
            info "resize2fs completado exitosamente."
            echo "$resize2fs_output" # Mostrar salida por si hay infos útiles
        else
            # No fallar necesariamente, solo advertir si el error no es fatal
            # (resize2fs a veces sale con 1 si no hay nada que hacer)
            warn "resize2fs finalizó con código $resize2fs_exit_code. Salida: $resize2fs_output"
            warn "Esto puede ser normal si el sistema de ficheros ya estaba al tamaño máximo."
            # Podríamos decidir fallar aquí si $resize2fs_exit_code es > 1
            # if [ $resize2fs_exit_code -gt 1 ]; then error "resize2fs falló gravemente."; fi
        fi
        ;;
    xfs)
        info "Redimensionando FS XFS en punto de montaje $MOUNT_POINT..."
        if [ -z "$MOUNT_POINT" ] || [ "$MOUNT_POINT" == "none" ]; then error "Punto de montaje inválido para XFS."; fi
        # xfs_growfs suele salir con 0 incluso si no hay cambio
        if ! xfs_growfs "$MOUNT_POINT"; then
            error "xfs_growfs falló (código $?).";
        else
            info "xfs_growfs completado (puede no haber habido cambios si ya estaba al máximo).";
        fi
        ;;
    *)
        error "FS Type '$FS_TYPE' no soportado." ;;
esac

##############################
# Paso 5: Resultados finales
##############################
log_banner "RESULTADOS FINALES"
info "Distribución del disco $DISK:"
lsblk "$DISK"
info "Uso del FS en $MOUNT_POINT:"
df -hT "$MOUNT_POINT"
if [ "$IS_LVM" = true ]; then
    info "Estado LVM:"
    vgs "$VG_NAME" --units h
    lvs "$LV_DEVICE" --units h
fi

log_banner "OPERACIÓN COMPLETADA"
info "Script finalizado. Verifica la salida y el uso del disco para confirmar la expansión."
exit 0
