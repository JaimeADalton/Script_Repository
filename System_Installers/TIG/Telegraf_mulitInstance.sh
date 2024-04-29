#!/bin/bash

# Solicitar al usuario el número de instancias a crear
echo -n "Ingrese el número de instancias de Telegraf a instalar: "
read num_instances

# Verificar si Telegraf está instalado y, si no, instalarlo
if ! command -v telegraf &> /dev/null
then
    echo "Telegraf no está instalado. Instalando Telegraf..."
    sudo apt update && sudo apt install telegraf -y
else
    echo "Telegraf ya está instalado."
fi

# Función para crear y configurar una nueva instancia de Telegraf
configure_instance() {
    local instance_number=$1

    echo "Configurando la instancia $instance_number de Telegraf..."

    # Copiar el archivo de configuración base
    sudo cp -r /etc/telegraf/ "/etc/telegraf${instance_number}"
    
    # Crear un nuevo servicio systemd
    sudo cp /lib/systemd/system/telegraf.service "/etc/systemd/system/telegraf${instance_number}.service"
    sudo sed -i "s|ExecStart=/usr/bin/telegraf -config /etc/telegraf/telegraf.conf|ExecStart=/usr/bin/telegraf -config /etc/telegraf${instance_number}/telegraf.conf|" "/etc/systemd/system/telegraf${instance_number}.service"

    # Habilitar y arrancar el servicio
    sudo systemctl daemon-reload
    sudo systemctl enable "telegraf${instance_number}.service"
    sudo systemctl start "telegraf${instance_number}.service"
    echo "Instancia $instance_number configurada y en ejecución."
}

# Crear las instancias especificadas por el usuario
for ((i = 1; i <= num_instances; i++))
do
    configure_instance $i
done

echo "Todas las instancias de Telegraf han sido configuradas."
