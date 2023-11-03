#!/bin/bash


EXCEPTIONS="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody _apt systemd-network systemd-resolve messagebus systemd-timesync pollinate sshd syslog uuidd tcpdump tss landscape usbmux lxd fwupd-refresh restricted"

# Leer la lista de nombres de usuario del archivo "usernames.txt".
while read username; do
  # Comprobar si el usuario ya existe
  if ! id "$username" >/dev/null 2>&1; then
    # Cree una nueva cuenta de usuario con "/bin/bash" como shell
    echo "Creando usuario $username"
    useradd $username -m -s /bin/bash

    mkdir /home/$username/.ssh
    # Generar un nuevo par de claves SSH para el usuario
    ssh-keygen -t rsa -b 4096 -f /home/$username/.ssh/id_rsa -q -N ""

    # Añadir la clave pública al archivo authorized_keys del usuario
    mv /home/$username/.ssh/id_rsa.pub /home/$username/.ssh/authorized_keys
    mv /home/$username/.ssh/id_rsa /home/$username/.ssh/${username}_srvbastionssh.key

    # Establecer los permisos del directorio personal del usuario y del archivo authorized_keys.
    chmod 700 /home/$username/.ssh
    chmod 600 /home/$username/.ssh/authorized_keys
    chown -R $username:$username /home/$username -R
  fi
done < usernames.txt

# Leer la lista de nombres de usuario existentes en el equipo
while read username; do
  # Comprobar si el usuario está en la lista de excepciones
  if [[ $EXCEPTIONS == *"$username"* ]]; then
    continue
  fi

  # Comprobar si el usuario no existe en el archivo usernames.txt
  if ! grep -Fxq "$username" usernames.txt; then
    # Eliminar el usuario
    echo "Eliminando usuario $username"
    userdel -r $username
  fi
done < <(cut -d: -f1 /etc/passwd)
