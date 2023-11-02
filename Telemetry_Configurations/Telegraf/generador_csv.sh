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

    for interfaz in "${interfaz_nombres[@]}"; do
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

# Leer archivo CSV
while IFS=',' read -r ip interfaz config_name
do
    echo "Procesando IP: $ip"
    echo "Interfaces a configurar: $interfaz"
    interfaz_nombres=(${interfaz//;/ })  # asumir que los nombres de las interfaces están separados por ';' en la misma celda del CSV

    # Generar el archivo de configuración
    generar_configuracion $ip
done < input.csv
