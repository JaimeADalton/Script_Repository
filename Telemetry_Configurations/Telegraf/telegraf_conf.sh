#!/bin/bash

# Función para mostrar las interfaces disponibles
function mostrar_interfaces {
    snmpwalk -v2c -c GestionGrp $1 IF-MIB::ifName | awk -F ' ' '{print $NF}'
}

# Función para obtener el OID de la interfaz seleccionada
function obtener_oid {
    snmpwalk -v2c -c GestionGrp $1 IF-MIB::ifName | awk -F ' ' -v interface="$2" '$NF == interface {print $(NF-3)}' | cut -d"." -f2
}

# Función para generar el archivo de configuración de Telegraf
function generar_configuracion {
    echo "# $config_name" >> all_telegraf_snmp.conf
    cat <<EOF >>all_telegraf_snmp.conf
[[inputs.snmp]]
  agents = ["$1:161"]
  version = 2
  community = "GestionGrp"
  name = "snmp"
  interval = "5s"
  flush_interval = "5s"

EOF

    for numero_interfaz in "${interfaz_numeros[@]}"; do
        interfaz=${interfaces[$((numero_interfaz-1))]}
        oid=$(obtener_oid $1 "$interfaz")
        if [[ -n "$oid" ]]; then
            cat <<EOF >>all_telegraf_snmp.conf
  [[inputs.snmp.field]]
    oid = "IF-MIB::ifHCInOctets.$oid"
    name = "${interfaz}_In"

  [[inputs.snmp.field]]
    oid = "IF-MIB::ifHCOutOctets.$oid"
    name = "${interfaz}_Out"

EOF
        fi
    done
}

# Inicio del wizard
read -p "Ingresa cuántas direcciones IP vas a introducir: " num_ips

for ((j=0; j<$num_ips; j++)); do
    read -p "Ingresa la dirección IP: " ip
    read -p "Ingresa un nombre para esta configuración: " config_name
    echo "Interfaces disponibles:"
    interfaces=($(mostrar_interfaces $ip))

    for i in "${!interfaces[@]}"; do
        echo "$((i+1)). ${interfaces[$i]}"
    done

    echo

    read -p "Ingresa el número de interfaz(es) separado por espacios: " -a interfaz_numeros

    # Generar el archivo de configuración
    generar_configuracion $ip
done

read -p "Ingresa el nombre para el archivo de configuración generado: " final_filename
mv all_telegraf_snmp.conf $final_filename

echo "Archivo de configuración generado: $final_filename"
