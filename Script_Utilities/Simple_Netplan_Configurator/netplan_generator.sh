#!/bin/bash

# Este script de Bash crea un archivo de configuración de red en formato YAML para el sistema Netplan en sistemas Linux.
# La configuración resultante incluye información sobre las interfaces de red físicas, sus direcciones IP y rutas,
# así como las VLAN (Virtual LAN) configuradas en el sistema, incluyendo sus identificadores, enlaces, direcciones IP y rutas.

# Función para procesar una interfaz de red
procesar_interfaz() {
    local intf=$1
    local ips=( $(ip addr show $intf | grep -o 'inet [0-9./]*' | awk '{print $2}') )
    local routes=$(ip route | grep "$intf" | awk '{ if ($2 != "dev") { print "        - to: " $1 "\n          via: " $3 } }')

    echo "    $intf:"
    echo "      dhcp4: no"
    if [[ ${#ips[@]} -gt 0 ]]; then
        echo "      addresses:"
        for ip in "${ips[@]}"; do
            echo "        - $ip"
        done
    fi

    if [[ $routes ]]; then
        echo "      routes:"
        echo "$routes"
    fi
}

# Función para procesar una VLAN
procesar_vlan() {
    local vlan=$1
    local id=$(echo $vlan | grep -o '[0-9]*')
    local link=$(ip a s | grep $vlan@ | cut -d : -f2 | cut -d @ -f 2)
    local ip=$(ip addr show $vlan | grep -o 'inet [0-9./]*' | awk '{print $2}')
    local routes=$(ip route | grep "$vlan" | awk '{ if ($2 != "dev") { print "          - to: " $1 "\n            via: " $3 } }')

    echo "    $vlan:"
    echo "        id: $id"
    echo "        link: $link"
    if [[ ${#ip[@]} -gt 0 ]]; then
        echo "        addresses:"
        for ip in "${ip[@]}"; do
            echo "          - $ip"
        done
    fi

    if [[ $routes ]]; then
        echo "        routes:"
        echo "$routes"
    fi
}

# Crear archivo netplan
{
    echo "network:"
    echo "  version: 2"
    echo "  renderer: networkd"

    # Procesar interfaces físicas
    echo "  ethernets:"
    for intf in $(ls /sys/class/net/ | grep -vE 'vlan|lo'); do
        procesar_interfaz $intf
    done

    # Verificar si existen VLANs
    vlan_list=$(ls /sys/class/net/ | grep 'vlan' | sort -V)
    if [[ $vlan_list ]]; then
        echo "  vlans:"

        # Procesar VLANs
        for vlan in $vlan_list; do
            procesar_vlan $vlan
        done
    fi
} > 00-installer-config.yaml


chmod 600 00-installer-config.yaml
