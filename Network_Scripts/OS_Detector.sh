#!/bin/bash

# Definir las redes a analizar
networks=("192.168.1")

# Función de ayuda
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -w  Show only Windows IPs"
    echo "  -l  Show only Linux IPs"
    echo "  -o  Show other recognized OS IPs"
    echo "  -x  Show disconnected IPs"
    echo "  -d  Enable debug mode"
    echo "  -h  Display this help and exit"
    echo
    echo "Example: $0 -wl (Show only Windows and Linux IPs)"
    exit 1
}

# Parse command line options
show_windows=false
show_linux=false
show_other=false
show_disconnected=false
debug=false

if [ $# -eq 0 ]; then
    usage
fi

while getopts "wloxdh" opt; do
    case "$opt" in
    w) show_windows=true ;;
    l) show_linux=true ;;
    o) show_other=true ;;
    x) show_disconnected=true ;;
    d) debug=true; set -x ;;
    h) usage ;;
    *) usage ;;
    esac
done

# Función para determinar el sistema operativo basado en el valor TTL
get_os_by_ttl() {
    ttl=$1
    if [[ $ttl -ge 63 && $ttl -le 65 ]]; then
        echo "Linux"
    elif [[ $ttl -eq 128 || $ttl -eq 129 ]]; then
        echo "Windows"
    elif [[ $ttl -eq 255 || $ttl -eq 254 ]]; then
        echo "Other"
    elif [[ $ttl -ge 30 && $ttl -le 32 ]]; then
        echo "Other"
    else
        echo "Unknown OS"
    fi
}

# Realizar un ping a cada dirección IP en las redes especificadas y agrupar por OS
declare -A os_groups
total_ips=0
completed_ips=0

for network in ${networks[@]}; do
    for host in {1..254}; do
        ((total_ips++))
    done
done

for network in ${networks[@]}; do
    for host in {1..254}; do
        ip="$network.$host"
        # Realizar ping y capturar el valor TTL del paquete ICMP
        ttl=$(ping -c 1 -W 0.1 $ip | grep 'ttl=' | sed -E 's/.*ttl=([0-9]+).*/\1/')
        if [ ! -z "$ttl" ]; then
            os=$(get_os_by_ttl $ttl)
            os_groups[$os]+="$ip\n"
        else
            os_groups["Disconnected"]+="$ip\n"
        fi
        ((completed_ips++))
        printf "\rProgress: %d/%d IPs processed (%.2f%%)" $completed_ips $total_ips $((completed_ips * 100 / total_ips))
    done
done
echo ""

# Mostrar resultados según las opciones
[[ $show_windows == "true" ]] && echo -e "Windows IPs:\n${os_groups[Windows]}"
[[ $show_linux == "true" ]] && echo -e "Linux IPs:\n${os_groups[Linux]}"
[[ $show_other == "true" ]] && echo -e "Other OS IPs:\n${os_groups[Other]}"
[[ $show_disconnected == "true" ]] && echo -e "Disconnected IPs:\n${os_groups[Disconnected]}"
