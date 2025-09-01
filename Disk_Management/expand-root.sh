#!/usr/bin/env bash
# expand-root.sh — Autoexpansión de disco/partición/volumen raíz en Ubuntu
# Soporta:
#  - LVM sobre LUKS (típico en Ubuntu): growpart -> cryptsetup resize -> pvresize -> lvextend -r
#  - LVM sin LUKS: growpart/pvresize -> lvextend -r
#  - Partición simple ext4/xfs: growpart -> resize2fs/xfs_growfs
#  - PV en disco completo (sin particiones): sgdisk -e (si GPT) -> pvresize
#
# PELIGRO: Modifica particiones y FS. Úsalo con backups y bajo tu responsabilidad.

set -euo pipefail

# ---------- Config ----------
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
export LC_ALL=C LANG=C
umask 022
LV_USE_FREE_PCT="${LV_USE_FREE_PCT:-100}"   # Por defecto consume todo el FREE del VG al LV raíz
SLEEP_SETTLE="${SLEEP_SETTLE:-2}"

# ---------- Log ----------
banner(){ echo "============================================================"; echo "== $*"; echo "============================================================"; }
info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

trap 'rc=$?; [[ $rc -ne 0 ]] && echo "[ERROR] Fallo en línea $LINENO" >&2; exit $rc' EXIT

# ---------- Requisitos ----------
REQUIRED=(lsblk findmnt blkid growpart partprobe partx blockdev udevadm awk grep sed)
# LVM y FS
REQUIRED+=(pvresize vgs pvs lvs lvextend resize2fs xfs_growfs)
# Utilidades útiles
REQUIRED+=(timeout)
# Opcionales
OPTIONAL=(cryptsetup sgdisk btrfs)

[[ "$(id -u)" -eq 0 ]] || die "Ejecuta como root."

missing=()
for c in "${REQUIRED[@]}"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
[[ ${#missing[@]} -eq 0 ]] || die "Faltan comandos: ${missing[*]}"

# ---------- Helpers ----------
settle_disk(){
  local disk="$1"
  sync || true
  udevadm settle || true
  blockdev --rereadpt "$disk" || true
  partx -u "$disk" || true
  udevadm settle || true
  sleep "$SLEEP_SETTLE"
}

grow_partition_if_any(){
  # Entrada: dispositivo-partición, p.ej. /dev/sda3 o /dev/nvme0n1p3
  local part="$1"
  local disk="/dev/$(lsblk -no PKNAME "$part")"
  local pnum; pnum="$(lsblk -no PARTN "$part")"

  if [[ -z "$pnum" ]]; then
    info "El dispositivo $part no es una partición (PV en disco completo u otra topología). No se ejecuta growpart."
    [[ -x "$(command -v sgdisk || true)" ]] && { info "Intentando 'sgdisk -e' en $disk para ajustar la copia de respaldo GPT"; sgdisk -e "$disk" || true; }
    settle_disk "$disk"
    return 0
  fi

  local before after
  before="$(lsblk -bno SIZE "$part")"
  info "Creciendo partición $part en disco $disk num $pnum (tamaño previo: $before bytes)…"
  # growpart puede devolver 1 con NOCHANGE; no tratamos como fatal
  if ! growpart "$disk" "$pnum"; then
    warn "growpart devolvió código $? en $disk $pnum. Continuo si es NOCHANGE."
  fi
  settle_disk "$disk"
  after="$(lsblk -bno SIZE "$part")"
  if [[ "$after" -gt "$before" ]]; then
    info "Partición $part creció de $before a $after bytes."
  else
    info "Partición $part no cambió de tamaño."
  fi
}

# Redimensiona FS montado o por dispositivo según tipo
grow_filesystem(){
  local dev="$1"
  local fstype; fstype="$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)"
  local mnt;    mnt="$(findmnt -n -o TARGET "$dev" 2>/dev/null || true)"
  [[ -z "$fstype" ]] && die "No se pudo detectar el tipo de FS en $dev."

  case "$fstype" in
    ext2|ext3|ext4)
      info "resize2fs en $dev…"
      if ! resize2fs -f "$dev"; then
        warn "resize2fs devolvió $?; puede significar sin cambio."
      fi
      ;;
    xfs)
      [[ -n "$mnt" && "$mnt" != "none" ]] || die "XFS requiere punto de montaje válido para crecer."
      info "xfs_growfs en $mnt…"
      xfs_growfs "$mnt"
      ;;
    btrfs)
      if command -v btrfs >/dev/null 2>&1; then
        [[ -n "$mnt" && "$mnt" != "none" ]] || die "Btrfs requiere punto de montaje."
        info "btrfs filesystem resize max $mnt…"
        btrfs filesystem resize max "$mnt"
      else
        die "Btrfs detectado pero 'btrfs-progs' no está disponible."
      fi
      ;;
    *)
      die "FS '$fstype' no soportado."
      ;;
  esac
}

# ---------- Reescaneo bus ----------
banner "REESCANEO DEL BUS"
if compgen -G "/sys/class/scsi_host/host*" >/dev/null; then
  for h in /sys/class/scsi_host/host*; do
    [[ -w "$h/scan" ]] || continue
    info "Rescan $h"
    timeout 10 bash -c "echo '- - -' >'$h/scan'" || warn "Timeout/error reescaneando $h"
  done
else
  info "Sin hosts SCSI detectados."
fi
sync; partprobe || true; udevadm settle || true; sleep "$SLEEP_SETTLE"

# ---------- Detección de topología ----------
banner "DETECCIÓN"
ROOT_SRC="$(findmnt -n -o SOURCE /)" || die "No se pudo obtener el dispositivo de /"
ROOT_FS="$(findmnt -n -o FSTYPE /)"  || die "No se pudo obtener el FS de /"
ROOT_TYP="$(lsblk -no TYPE "$ROOT_SRC")"

info "Raíz: SRC=$ROOT_SRC FS=$ROOT_FS TYPE=$ROOT_TYP"

# Bloqueos por topologías no soportadas
case "$(lsblk -no TYPE "$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null || echo "$ROOT_SRC")" 2>/dev/null || echo "")" in
  raid*|rom|loop) die "Topología RAID/loop/rom no soportada por este script." ;;
esac
if [[ "$ROOT_FS" == "zfs" ]]; then die "ZFS no soportado."; fi

# ---------- Casos ----------
if [[ "$ROOT_SRC" == /dev/mapper/* && "$ROOT_TYP" == "lvm" ]]; then
  banner "LVM DETECTADO"
  LV_DEV="$ROOT_SRC"
  VG_NAME="$(lvs --noheadings -o vg_name "$LV_DEV" | awk '{print $1}')"
  [[ -n "$VG_NAME" ]] || die "No se pudo obtener el VG de $LV_DEV"

  # PVs del VG
  mapfile -t PV_LIST < <(pvs --noheadings -o pv_name --select vgname="$VG_NAME" | awk '{print $1}')
  [[ ${#PV_LIST[@]} -gt 0 ]] || die "Sin PVs en VG $VG_NAME"

  info "VG: $VG_NAME"
  info "PVs: ${PV_LIST[*]}"

  # Crece particiones subyacentes de cada PV si existen
  for PV in "${PV_LIST[@]}"; do
    # Si PV es mapper (LUKS), baja un nivel a su partición física
    PART_DEV="/dev/$(lsblk -no PKNAME "$PV" 2>/dev/null || true)"
    if [[ -n "$PART_DEV" && -b "$PART_DEV" ]]; then
      grow_partition_if_any "$PART_DEV"
    else
      # PV puede ser partición directa: usa el propio PV
      if [[ -n "$(lsblk -no PARTN "$PV" 2>/dev/null || true)" ]]; then
        grow_partition_if_any "$PV"
      else
        # PV en disco completo
        DISK="/dev/$(lsblk -no PKNAME "$PV" 2>/dev/null || true)"
        [[ -n "$DISK" ]] && { info "PV en disco completo detectado en $DISK"; [[ -x "$(command -v sgdisk || true)" ]] && sgdisk -e "$DISK" || true; settle_disk "$DISK"; }
      fi
    fi
  done

  # Si hay LUKS, resize de los mapeos antes de pvresize
  for PV in "${PV_LIST[@]}"; do
    if [[ "$PV" == /dev/mapper/* ]] && command -v cryptsetup >/dev/null 2>&1; then
      MAP="$(basename "$PV")"
      info "cryptsetup resize $MAP"
      cryptsetup resize "$MAP"
      udevadm settle || true
    fi
  done

  # pvresize en todos los PVs
  for PV in "${PV_LIST[@]}"; do
    info "pvresize $PV"
    pvresize "$PV" || warn "pvresize falló o sin cambio en $PV"
  done

  # Extiende LV raíz consumiendo %FREE configurable
  FREE_PE="$(vgs --noheadings -o vg_free_count "$VG_NAME" | awk '{print $1+0}')"
  info "PE libres en VG $VG_NAME: $FREE_PE"
  if [[ "$FREE_PE" -gt 0 && "${LV_USE_FREE_PCT}" -gt 0 ]]; then
    info "lvextend -r -l +${LV_USE_FREE_PCT}%FREE $LV_DEV"
    lvextend -r -l +"${LV_USE_FREE_PCT}"%FREE "$LV_DEV"
  else
    info "Sin PE libres o política LV_USE_FREE_PCT=0. No se extiende el LV."
  fi

elif [[ "$ROOT_SRC" == /dev/mapper/* && "$ROOT_TYP" == "crypt" ]]; then
  banner "LUKS + FS DIRECTO"
  # / está sobre un mapa LUKS que contiene ext4/xfs/btrfs
  PART_DEV="/dev/$(lsblk -no PKNAME "$ROOT_SRC")"                # p.ej. /dev/sda3
  [[ -b "$PART_DEV" ]] || die "No se pudo resolver la partición física de $ROOT_SRC"
  grow_partition_if_any "$PART_DEV"
  MAP="$(basename "$ROOT_SRC")"
  info "cryptsetup resize $MAP"
  cryptsetup resize "$MAP"
  udevadm settle || true
  grow_filesystem "$ROOT_SRC"

elif [[ "$ROOT_TYP" == "part" || "$ROOT_TYP" == "disk" ]]; then
  banner "PARTICIÓN SIMPLE"
  # / sobre partición o disco con FS
  PART_NODE="$ROOT_SRC"
  # si es disco completo con FS, PARTN vacío
  if [[ -n "$(lsblk -no PARTN "$PART_NODE" 2>/dev/null || true)" ]]; then
    grow_partition_if_any "$PART_NODE"
  else
    DISK="/dev/$(lsblk -no PKNAME "$PART_NODE" 2>/dev/null || echo "")"
    [[ -n "$DISK" ]] && { info "FS en disco completo detectado ($PART_NODE). Intentando sgdisk -e si GPT."; [[ -x "$(command -v sgdisk || true)" ]] && sgdisk -e "${DISK:-$PART_NODE}" || true; settle_disk "${DISK:-$PART_NODE}"; }
  fi
  grow_filesystem "$PART_NODE"

else
  die "Topología no reconocida: TYPE=$ROOT_TYP SRC=$ROOT_SRC"
fi

# ---------- Informe ----------
banner "RESULTADO"
DISK_ROOT="/dev/$(lsblk -no PKNAME "$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null || echo "$ROOT_SRC")" 2>/dev/null || echo "")"
[[ -b "$DISK_ROOT" ]] && { info "Distribución actual en $DISK_ROOT:"; lsblk -e7 -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT -f "$DISK_ROOT"; } || true
info "Uso de /:"
df -hT /

if [[ "$ROOT_TYP" == "lvm" ]]; then
  info "Estado LVM:"
  vgs "$VG_NAME" --units h
  lvs "$LV_DEV" --units h -o +devices
fi

banner "OK"
exit 0
