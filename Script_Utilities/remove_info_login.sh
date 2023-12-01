#!/bin/bash
# solo para Ubuntu.
# Cambiar la línea en /etc/ssh/sshd_config
sed -i 's/#PrintLastLog yes/PrintLastLog no/' /etc/ssh/sshd_config

# Quitar los permisos de ejecución de todos los archivos en /etc/update-motd.d
chmod -x /etc/update-motd.d/*

# Reiniciar el servicio SSH
service ssh restart
