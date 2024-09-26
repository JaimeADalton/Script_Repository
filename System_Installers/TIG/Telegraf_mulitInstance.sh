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

# Verificar si InfluxDB está instalado y, si no, instalarlo
if ! command -v influxd &> /dev/null
then
    echo "InfluxDB no está instalado. Instalando InfluxDB..."
    sudo apt update && sudo apt install influxdb -y
    sudo systemctl enable influxdb
    sudo systemctl start influxdb
else
    echo "InfluxDB ya está instalado."
fi

# Función para crear y configurar una nueva instancia de Telegraf
configure_instance() {
    local instance_number=$1

    echo "Configurando la instancia $instance_number de Telegraf..."

    # Crear un directorio de configuración específico para la instancia
    sudo cp -r /etc/telegraf/ "/etc/telegraf${instance_number}/"

    # Modificar el archivo de configuración
    sudo sed -i "s|/var/log/telegraf/telegraf.log|/var/log/telegraf/telegraf${instance_number}.log|g" "/etc/telegraf${instance_number}/telegraf.conf"
    sudo sed -i "s|hostname = \".*\"|hostname = \"telegraf-instance-${instance_number}\"|g" "/etc/telegraf${instance_number}/telegraf.conf"

    # Configurar Telegraf para enviar datos a una base de datos específica en InfluxDB
    sudo sed -i "s|database = \".*\"|database = \"telegraf_db_${instance_number}\"|g" "/etc/telegraf${instance_number}/telegraf.conf"

    # Crear la base de datos en InfluxDB
    influx -execute "CREATE DATABASE telegraf_db_${instance_number}"

    # Crear un nuevo servicio systemd para la instancia
    sudo cp /lib/systemd/system/telegraf.service "/etc/systemd/system/telegraf${instance_number}.service"
    sudo sed -i "s|ExecStart=/usr/bin/telegraf -config /etc/telegraf/telegraf.conf|ExecStart=/usr/bin/telegraf -config /etc/telegraf${instance_number}/telegraf.conf|" "/etc/systemd/system/telegraf${instance_number}.service"

    # Modificar el PIDFile para evitar conflictos
    sudo sed -i "s|PIDFile=/run/telegraf/telegraf.pid|PIDFile=/run/telegraf/telegraf${instance_number}.pid|g" "/etc/systemd/system/telegraf${instance_number}.service"

    # Crear el directorio de ejecución si no existe
    sudo mkdir -p /run/telegraf

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

# Configurar Grafana para conectarse a las bases de datos de InfluxDB
echo "Configurando Grafana para conectarse a las bases de datos de InfluxDB..."

if ! command -v grafana-server &> /dev/null
then
    echo "Grafana no está instalado. Instalando Grafana..."
    sudo apt update && sudo apt install grafana -y
    sudo systemctl enable grafana-server
    sudo systemctl start grafana-server
else
    echo "Grafana ya está instalado."
fi

echo "Por favor, accede a Grafana y configura manualmente las fuentes de datos para cada base de datos telegraf_db_X."
