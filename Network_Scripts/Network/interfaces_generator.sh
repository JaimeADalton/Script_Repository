#!/bin/bash

# Este script crea un archivo de configuración de red para sistemas Debian en /etc/network/interfaces.
# La configuración incluye información sobre las interfaces de red físicas, sus direcciones IP, rutas y VLAN configuradas.

# Función para calcular la máscara de red a partir de una dirección CIDR
calcular_netmask() {
    local cidr=$1
    local full_bin_mask=$(head -c $cidr < /dev/zero | tr '\0' '1'; head -c $(( 32 - cidr )) < /dev/zero | tr '\0' '0')
    local octet1=$((2#${full_bin_mask:0:8}))
    local octet2=$((2#${full_bin_mask:8:8}))
    local octet3=$((2#${full_bin_mask:16:8}))
    local octet4=$((2#${full_bin_mask:24:8}))

    echo "$octet1.$octet2.$octet3.$octet4"
}

# Función para procesar una interfaz de red
procesar_interfaz() {
    local intf=$1
    local ips=( $(ip addr show $intf | grep -o 'inet [0-9./]*' | awk '{print $2}') )
    local routes=$(ip route | grep "$intf" | awk '{ if ($2 != "dev") { print "up ip route add " $1 " via " $3 } }')

    echo "auto $intf"
    echo "iface $intf inet static"
    for ip in "${ips[@]}"; do
        local addr=${ip%%/*}
        local cidr=${ip#*/}
        local netmask=$(calcular_netmask $cidr)
        echo "    address $addr"
        echo "    netmask $netmask"
    done
    for route in "${routes[@]}"; do
        echo "    $route"
    done
    echo ""
}

# Función para procesar una VLAN
procesar_vlan() {
    local vlan=$1
    local link=$(ip a s | grep $vlan@ | cut -d : -f2 | cut -d @ -f 2)
    local ip=$(ip addr show $vlan | grep -o 'inet [0-9./]*' | awk '{print $2}')
    local routes=$(ip route | grep -w "$vlan" | awk '{ if ($2 != "dev") { print "up ip route add " $1 " via " $3 } }')

    echo "auto $vlan"
    echo "iface $vlan inet static"
    echo "    vlan-raw-device $link"
    local addr=${ip%%/*}
    local cidr=${ip#*/}
    local netmask=$(calcular_netmask $cidr)
    echo "    address $addr"
    echo "    netmask $netmask"
    for route in "${routes[@]}"; do
        echo "    $route"
    done
    echo ""
}

# Crear archivo /etc/network/interfaces
{
    echo "# Configuración de red generada automáticamente"
    echo "source /etc/network/interfaces.d/*"

    # Procesar interfaces físicas
    for intf in $(ls /sys/class/net/ | grep -vE 'vlan|lo'); do
        procesar_interfaz $intf
    done

    # Verificar si existen VLANs
    vlan_list=$(ls /sys/class/net/ | grep 'vlan' | sort -V)
    if [[ $vlan_list ]]; then
        # Procesar VLANs
        for vlan in $vlan_list; do
            procesar_vlan $vlan
        done
    fi
} > /etc/network/interfaces
