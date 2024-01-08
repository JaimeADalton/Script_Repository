#!/bin/bash

# Colores
ROJO="\e[31m"
VERDE="\e[32m"
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
    PS3="¿Qué IPs desea mostrar?: "
    options=("Solo Up" "Solo Down" "Ambas" "Salir")

    select option in "${options[@]}"
    do
        case $option in
            "Solo Up")
                show_ips "up"
                ;;
            "Solo Down")
                show_ips "down"
                ;;
            "Ambas")
                show_ips "both"
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

# Muestra IPs según el estado seleccionado
function show_ips {
    cleaner
    echo "Sondeando ..."
    echo ""
    while IFS= read -r ip; do
        result=$(icmp_ping "$ip")
        case $1 in
            "up")
                [[ $result -eq 0 ]] && echo -e "${VERDE}$ip\tUp${END}"
                ;;
            "down")
                [[ $result -ne 0 ]] && echo -e "${ROJO}$ip\tDown${END}"
                ;;
            "both")
                if [[ $result -eq 0 ]]; then
                    echo -e "${VERDE}$ip\tUp${END}"
                else
                    echo -e "${ROJO}$ip\tDown${END}"
                fi
                ;;
        esac
    done < <(read_ips)
    exit
}

menu
