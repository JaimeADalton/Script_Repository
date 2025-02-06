#!/bin/bash
set -euo pipefail

# Configuración ajustable
readonly DEFAULT_USER_FILE="usernames.txt"
readonly SSH_KEY_TYPE="ed25519"
readonly SSH_KEY_ROUNDS=200
readonly SSH_KEY_PREFIX="_srvbastionssh.key"
readonly EXCEPTIONS="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody _apt systemd-network systemd-resolve messagebus systemd-timesync pollinate sshd syslog uuidd tcpdump tss landscape usbmux lxd fwupd-refresh restricted"

# Variables globales
VERBOSE=0
USER_FILE="$DEFAULT_USER_FILE"
HAS_PUTTYGEN=0

# Nuevas variables para forzar regeneración
FORCE_ALL=0      # Si se activa, se fuerzan las claves de TODOS los usuarios
FORCE_USER=""    # Si se especifica, solo se actualiza el usuario indicado

# Funciones de utilidad
usage() {
    cat <<EOF
Uso: $0 [OPCIONES]

Administrador de usuarios con configuración SSH y generación de claves .ppk

Opciones:
  -f ARCHIVO       Especifica archivo de usuarios (por defecto: $DEFAULT_USER_FILE)
  -v               Habilita modo verboso
  -h               Muestra este mensaje de ayuda
  --force USUARIO  Forzar regeneración de las claves SSH solo para el usuario indicado (debe existir)
  --force-all      Forzar regeneración de las claves SSH para TODOS los usuarios

EOF
}

log() {
    local level=$1
    shift
    local message="$*"
    if [[ $level == "INFO" ]] || { [[ $level == "DEBUG" ]] && [[ $VERBOSE -eq 1 ]]; } || [[ $level == "ERROR" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    fi
}

check_dependencies() {
    if command -v puttygen >/dev/null 2>&1; then
        HAS_PUTTYGEN=1
    else
        log ERROR "puttygen no está instalado. No se generarán archivos .ppk"
        HAS_PUTTYGEN=0
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "Este script debe ejecutarse como root"
        exit 1
    fi
}

validate_user_file() {
    if [[ ! -f "$USER_FILE" ]]; then
        log ERROR "Archivo de usuarios no encontrado: $USER_FILE"
        exit 1
    fi
}

is_exception() {
    local username=$1
    for ex in "${EXCEPTIONS[@]}"; do
        [[ "$ex" == "$username" ]] && return 0
    done
    return 1
}

convert_to_ppk() {
    local username=$1
    local ssh_dir="/home/$username/.ssh"
    local key_file="$ssh_dir/${username}${SSH_KEY_PREFIX}"
    # Se usa sustitución para cambiar la extensión a .ppk
    local ppk_file="${key_file%.key}.ppk"

    if [[ $HAS_PUTTYGEN -eq 0 ]]; then
        log ERROR "No se puede convertir a .ppk: puttygen no está instalado"
        return 1
    fi

    if [[ $FORCE_ALL -eq 1 || "$FORCE_USER" == "$username" ]]; then
        rm -f "$ppk_file"
    elif [[ -f "$ppk_file" ]]; then
        log INFO "Archivo .ppk existente para $username, omitiendo conversión"
        return
    fi

    log INFO "Convirtiendo clave privada a formato .ppk para $username"
    if ! puttygen "$key_file" -o "$ppk_file" -O private; then
        log ERROR "Fallo en la conversión de la clave para $username"
        return 1
    fi

    chmod 600 "$ppk_file"
    chown "$username:$username" "$ppk_file"
    log INFO "Archivo .ppk generado: $ppk_file"
}

setup_ssh_keys() {
    local username=$1
    local ssh_dir="/home/$username/.ssh"

    if [[ $FORCE_ALL -eq 1 || "$FORCE_USER" == "$username" ]]; then
        rm -f "$ssh_dir/${username}${SSH_KEY_PREFIX}" "$ssh_dir/${username}${SSH_KEY_PREFIX}.pub"
    elif [[ -f "$ssh_dir/${username}${SSH_KEY_PREFIX}" ]]; then
        log INFO "Claves SSH existentes para $username, omitiendo generación"
        return
    fi

    log INFO "Generando nuevas claves SSH para $username"
    ssh-keygen -t "$SSH_KEY_TYPE" -a "$SSH_KEY_ROUNDS" \
        -f "$ssh_dir/${username}${SSH_KEY_PREFIX}" -q -N ""
    mv "$ssh_dir/${username}${SSH_KEY_PREFIX}.pub" "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"
    chown "$username:$username" "$ssh_dir/authorized_keys"

    convert_to_ppk "$username"
}

create_user() {
    local username=$1
    if id "$username" &>/dev/null; then
        log INFO "Usuario $username ya existe, actualizando claves SSH si es necesario"
    else
        log INFO "Creando usuario: $username"
        useradd -m -s /bin/bash "$username"
        local ssh_dir="/home/$username/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown -R "$username:$username" "$ssh_dir"
    fi
    setup_ssh_keys "$username"
}

delete_user() {
    local username=$1
    log INFO "Eliminando usuario: $username"
    if userdel -r "$username" 2>/dev/null; then
        log INFO "Usuario $username eliminado exitosamente"
    else
        log ERROR "Fallo al eliminar usuario $username"
    fi
}

process_users() {
    while read -r username; do
        username="${username%%#*}"  # Elimina comentarios
        username="${username// /}"  # Elimina espacios
        [[ -z "$username" ]] && continue
        create_user "$username"
    done < "$USER_FILE"
}

cleanup_users() {
    local tmpfile
    tmpfile=$(mktemp)
    # Prepara un listado limpio de usuarios a partir del archivo
    sed -e 's/#.*//' -e 's/ //g' "$USER_FILE" | grep -v '^$' > "$tmpfile"

    while IFS=: read -r username _; do
        if ! grep -Fxq "$username" "$tmpfile" && ! is_exception "$username"; then
            delete_user "$username"
        fi
    done < /etc/passwd
    rm "$tmpfile"
}

main() {
    check_root
    check_dependencies
    validate_user_file

    # Si se activa --force-all, se fuerza la regeneración para todos los usuarios
    if [[ $FORCE_ALL -eq 1 ]]; then
         log INFO "Forzando regeneración de claves SSH para TODOS los usuarios"
         process_users
         cleanup_users
    # Si se usa --force USUARIO, se actualiza solo ese usuario (debe existir)
    elif [[ -n "$FORCE_USER" ]]; then
         if id "$FORCE_USER" &>/dev/null; then
             log INFO "Forzando regeneración de claves SSH para el usuario: $FORCE_USER"
             setup_ssh_keys "$FORCE_USER"
         else
             log ERROR "El usuario $FORCE_USER no existe"
             exit 1
         fi
    else
         log INFO "Iniciando sincronización de usuarios"
         process_users
         cleanup_users
         log INFO "Proceso completado exitosamente"
    fi
}

# Procesar argumentos
# Se usan las opciones cortas y la extensión para opciones largas (--force y --force-all)
while getopts ":f:vh-:" opt; do
    case $opt in
        f) USER_FILE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) usage; exit 0 ;;
        -)
            case "${OPTARG}" in
                force-all)
                    FORCE_ALL=1
                    ;;
                force)
                    # Se requiere un argumento: el nombre de usuario a actualizar
                    if [[ -n "${!OPTIND:-}" ]] && [[ "${!OPTIND}" != -* ]]; then
                        FORCE_USER="${!OPTIND}"
                        OPTIND=$((OPTIND + 1))
                    else
                        echo "Opción --force requiere un argumento: el nombre de usuario" >&2
                        exit 1
                    fi
                    ;;
                *) echo "Opción inválida: --$OPTARG" >&2; exit 1 ;;
            esac
            ;;
        \?) echo "Opción inválida: -$OPTARG" >&2; usage; exit 1 ;;
        :) echo "Opción -$OPTARG requiere un argumento." >&2; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Ejecutar programa principal
main
