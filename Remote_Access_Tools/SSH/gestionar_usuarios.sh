#!/bin/bash

set -euo pipefail

# Este script automatiza la creación de cuentas de usuario y la eliminación de cuentas no deseadas

EXCEPTIONS="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody _apt systemd-network systemd-resolve messagebus systemd-timesync pollinate sshd syslog uuidd tcpdump tss landscape usbmux lxd fwupd-refresh restricted"
USERNAMES_FILE="usernames.txt"
LOG_FILE="/var/log/user_management.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

create_user() {
    local username="$1"
    log "Creando usuario $username"
    useradd "$username" -m -s /bin/bash || { log "Error al crear usuario $username"; return 1; }

    local ssh_dir="/home/$username/.ssh"
    mkdir -p "$ssh_dir"
    ssh-keygen -t ed25519 -a 200 -f "$ssh_dir/ed25519" -q -N "" || { log "Error al generar claves SSH para $username"; return 1; }

    mv "$ssh_dir/ed25519.pub" "$ssh_dir/authorized_keys"
    mv "$ssh_dir/ed25519" "$ssh_dir/${username}_srvbastionssh.key"

    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/authorized_keys" "$ssh_dir/${username}_srvbastionssh.key"
    chown -R "$username:$username" "/home/$username"
    log "Usuario $username creado exitosamente"
}

delete_user() {
    local username="$1"
    log "Eliminando usuario $username"
    userdel -r "$username" || log "Error al eliminar usuario $username"
}

# Verificar si el script se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   log "Este script debe ser ejecutado como root"
   exit 1
fi

# Verificar si el archivo de usuarios existe
if [[ ! -f "$USERNAMES_FILE" ]]; then
    log "El archivo $USERNAMES_FILE no existe"
    exit 1
fi

# Crear usuarios
while IFS= read -r username || [[ -n "$username" ]]; do
    username=$(echo "$username" | tr -d '[:space:]')
    if [[ -z "$username" ]]; then continue; fi
    if ! id "$username" &>/dev/null; then
        create_user "$username"
    else
        log "El usuario $username ya existe"
    fi
done < "$USERNAMES_FILE"

# Eliminar usuarios no deseados
while IFS=: read -r username _; do
    if [[ $EXCEPTIONS != *"$username"* ]] && ! grep -qFx "$username" "$USERNAMES_FILE"; then
        delete_user "$username"
    fi
done < /etc/passwd

log "Proceso completado"
