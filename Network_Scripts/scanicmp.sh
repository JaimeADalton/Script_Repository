#!/bin/bash

# Colores
RED="\e[31m"
GREEN="\e[32m"
END="\e[0m"

archivo="ip.txt"

# Limpia la pantalla
function cleaner {
    clear && clear
}

# Lee las IPs desde un archivo
function read_ips {
    if [ ! -e "$archivo" ]; then
      echo "El archivo $archivo no existe. Se abortará la ejecución del script."
    exit 1
    fi
    cat $archivo
}

# Realiza una prueba ICMP a una IP
function icmp_ping {
    ping -c 1 -W 0.1 -s 8 -q "$1" > /dev/null 2>&1
    echo $?
}

# Menú principal
function menu {
    cleaner
    PS3="Which IPs do you want to display? "
    options=("Only Up" "Only Down" "Both" "Salir")

    select option in "${options[@]}"
    do
        case $option in
            "Only Up")
                show_ips "up"
                ;;
            "Only Down")
                show_ips "down"
                ;;
            "Both")
                show_ips "both"
                ;;
            "Exit")
                exit
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}

# Muestra IPs según el estado seleccionado
function show_ips {
    cleaner
    if [[ $1 == "up" ]]; then
        echo -e "${GREEN}UP DEVICES${END}"
    elif [[ $1 == "both" ]]; then
        echo "UP AND DOWN DEVICES"
    else
        echo -e "${RED}DOWN DEVICES${END}"
    fi
    echo ""
    while IFS= read -r ip; do
        result=$(icmp_ping "$ip")
        case $1 in
            "up")
                [[ $result -eq 0 ]] && echo -e "${GREEN}$ip${END}"
                ;;
            "down")
                [[ $result -ne 0 ]] && echo -e "${RED}$ip${END}"
                ;;
            "both")
                if [[ $result -eq 0 ]]; then
                    echo -e "${GREEN}$ip\tUp${END}"
                else
                    echo -e "${RED}$ip\tDown${END}"
                fi
                ;;
        esac
    done < <(read_ips)
    exit
}

menu
