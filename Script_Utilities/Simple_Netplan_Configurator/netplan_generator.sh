#!/bin/bash

# Crear archivo netplan
echo "network:" > netplan.yaml
echo "  version: 2" >> netplan.yaml
echo "  renderer: networkd" >> netplan.yaml

# Procesar interfaces físicas
echo "  ethernets:" >> netplan.yaml
for intf in $(ls /sys/class/net/ | grep -vE 'vlan|lo'); do
    ips=$(ip addr show $intf | grep -o 'inet [0-9./]*' | awk '{print $2}')
    if [[ $ips ]]; then
        echo "    $intf:" >> netplan.yaml
        echo "      dhcp4: no" >> netplan.yaml
        echo "      addresses:" >> netplan.yaml
        for ip in $ips; do
            echo "        - $ip" >> netplan.yaml
        done

        # Verificar y agregar rutas para la interfaz
        routes=$(ip route | grep "$intf" | awk '{ if ($2 != "dev") { print "          - to: " $1 "\n            via: " $3 } }')
        if [[ $routes ]]; then
            echo "      routes:" >> netplan.yaml
            echo "$routes" >> netplan.yaml
        fi
    fi
done

# Verificar si existen VLANs
vlan_list=$(ip a s | grep @ | cut -d : -f2 | cut -d @ -f 1 | sed 's/\ //g')
if [[ $vlan_list ]]; then
    echo "  vlans:" >> netplan.yaml

    # Procesar VLANs
    for vlan in $vlan_list; do
        id=$(echo $vlan | grep -o '[0-9]*')
        link=$(ip a s | grep $vlan@ | cut -d : -f2 | cut -d @ -f 2)
        ip=$(ip addr show $vlan | grep -o 'inet [0-9./]*' | awk '{print $2}')

        echo "      $vlan:" >> netplan.yaml
        echo "          id: $id" >> netplan.yaml
        echo "          link: $link" >> netplan.yaml
        echo "          addresses: [$ip]" >> netplan.yaml

        # Verificar y agregar rutas para la VLAN
        routes=$(ip route | grep "$vlan" | awk '{ if ($2 != "dev") { print "          - to: " $1 "\n            via: " $3 } }')
        if [[ $routes ]]; then
            echo "          routes:" >> netplan.yaml
            echo "$routes" >> netplan.yaml
        fi
    done
fi
