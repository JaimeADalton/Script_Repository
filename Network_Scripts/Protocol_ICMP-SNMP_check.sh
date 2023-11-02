#!/bin/bash

# Colores
ROJO="\e[31m"
VERDE="\e[32m"
END="\e[0m"

# Limpia la pantalla
function cleaner {
    clear && clear
}

# Lee las IPs desde un archivo
function read_ips {
    cat ip.txt
}

# Realiza un snmpget a una IP usando una comunidad específica
function snmp_get {
    timeout -s SIGINT 0.1 snmpget -v2c -c "$1" "$2" SNMPv2-MIB::sysName.0 > /dev/null 2>&1
}

# Verifica el resultado del comando y muestra el estado de la IP
function check_status {
    if [[ $? -eq 0 ]]; then
        echo -e "${VERDE}$1\tUp${END}"
    else
        echo -e "${ROJO}$1\tDown${END}"
    fi
}

# Menú principal
function menu {
    cleaner
    PS3="Seleccione un protocolo: "
    options=("ICMP" "SNMP" "Salir")
    
    select protocol in "${options[@]}"
    do
        case $protocol in
            "ICMP")
                cleaner
                echo "Protocolo ICMP. Sondeando ..."
                echo ""
                while IFS= read -r ip; do
                    ping -c 1 -W 1 -q "$ip" > /dev/null
                    check_status "$ip"
                done < <(read_ips)
                ;;
            "SNMP")
                submenu_snmp
                ;;
            "Salir")
                exit
                ;;
            *)
                echo "Opción inválida. Intente nuevamente."
                ;;
        esac
    done
}

# Submenú SNMP
function submenu_snmp {
    cleaner
    PS3="Seleccione una comunidad SNMP: "
    snmp_options=("public" "Salir")
    
    select snmp_option in "${snmp_options[@]}"
    do
        case $snmp_option in
            "Salir")
                menu
                ;;
            *)
                cleaner
                echo "Protocolo SNMP. Sondeando con comunidad: $snmp_option"
                echo ""
                while IFS= read -r ip; do
                    snmp_get "$snmp_option" "$ip"
                    check_status "$ip"
                done < <(read_ips)
                ;;
        esac
    done
}

menu
