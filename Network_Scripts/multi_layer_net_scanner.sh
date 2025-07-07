#!/bin/bash

# Colores
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
END="\e[0m"

archivo="ip.txt"
log_file="network_scan_$(date +%Y%m%d_%H%M%S).log"

# Variables globales para cachear resultados
declare -A PING_CACHE
declare -A ARP_CACHE
declare -A PORT_CACHE
declare -a IP_LIST

# Limpia la pantalla
function cleaner {
    clear && clear
}

# Lee las IPs desde un archivo una sola vez
function load_ips {
    if [ ! -e "$archivo" ]; then
        echo "El archivo $archivo no existe. Se abortará la ejecución del script."
        exit 1
    fi
    mapfile -t IP_LIST < "$archivo"
}

# Capa 3 - Prueba ICMP (IP) con cache
function icmp_ping {
    local ip=$1
    
    # Si ya está en cache, devolver resultado
    if [[ -n "${PING_CACHE[$ip]+set}" ]]; then
        echo "${PING_CACHE[$ip]}"
        return
    fi
    
    # Hacer ping solo una vez
    ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
    local result=$?
    PING_CACHE[$ip]=$result
    echo $result
}

# Capa 2 - Verificación MAC (ARP) optimizada
function arp_check {
    local ip=$1
    
    # Si ya está en cache, devolver resultado
    if [[ -n "${ARP_CACHE[$ip]+set}" ]]; then
        echo "${ARP_CACHE[$ip]}"
        return
    fi
    
    # Si ya hicimos ping antes, no repetir
    if [[ -z "${PING_CACHE[$ip]+set}" ]]; then
        ping -c 1 -W 1 "$ip" > /dev/null 2>&1
        PING_CACHE[$ip]=$?
    fi
    
    # Esperar menos tiempo
    sleep 0.2
    
    # Buscamos la MAC usando ip neigh
    local mac=$(ip neigh show "$ip" 2>/dev/null | awk '{print $5}')
    
    if [[ -n "$mac" && "$mac" != "00:00:00:00:00:00" && "$mac" != "<incomplete>" ]]; then
        ARP_CACHE[$ip]="$mac"
        echo "$mac"
    else
        ARP_CACHE[$ip]="N/A"
        echo "N/A"
    fi
}

# Capa 7 - Escaneo de puertos paralelo y optimizado
function port_scan {
    local ip=$1
    
    # Si ya está en cache, devolver resultado
    if [[ -n "${PORT_CACHE[$ip]+set}" ]]; then
        echo "${PORT_CACHE[$ip]}"
        return
    fi
    
    local ports=("22" "23" "25" "53" "80" "110" "143" "443" "993" "995")
    local open_ports=()
    local scan_pids=()
    local temp_dir="/tmp/portscan_$$"
    
    # Crear directorio temporal para resultados
    mkdir -p "$temp_dir"
    
    # Lanzar todos los escaneos en paralelo
    for port in "${ports[@]}"; do
        (
            if timeout 0.5 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
                echo "$port" > "$temp_dir/port_$port"
            fi
        ) &
        scan_pids+=($!)
    done
    
    # Esperar a que terminen todos los escaneos (máximo 1 segundo)
    local wait_time=0
    while [[ $wait_time -lt 10 ]]; do
        local all_done=true
        for pid in "${scan_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        
        if $all_done; then
            break
        fi
        
        sleep 0.1
        ((wait_time++))
    done
    
    # Recopilar resultados
    for port in "${ports[@]}"; do
        if [[ -f "$temp_dir/port_$port" ]]; then
            open_ports+=("$port")
        fi
    done
    
    # Limpiar archivos temporales
    rm -rf "$temp_dir"
    
    # Guardar en cache y devolver
    if [[ ${#open_ports[@]} -gt 0 ]]; then
        PORT_CACHE[$ip]="${open_ports[*]}"
        echo "${open_ports[*]}"
    else
        PORT_CACHE[$ip]="N/A"
        echo "N/A"
    fi
}

# Obtener información del fabricante de la MAC (básico)
function get_vendor {
    local mac=$1
    local oui=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')
    
    case "$oui" in
        "00:50:56"|"00:0C:29"|"00:05:69") echo "VMware" ;;
        "08:00:27") echo "VirtualBox" ;;
        "00:15:5D"|"00:03:FF") echo "Microsoft" ;;
        "00:1B:21"|"00:A0:C9") echo "Intel" ;;
        "00:E0:4C") echo "Realtek" ;;
        "00:23:AE") echo "Cisco" ;;
        "00:D0:C9") echo "Micro-Star" ;;
        "00:1A:A0") echo "Dell" ;;
        "00:50:B6") echo "HP" ;;
        *) echo "Unknown" ;;
    esac
}

# Escaneo completo de un host (optimizado)
function full_scan {
    local ip=$1
    local icmp_result=$(icmp_ping "$ip")
    local mac="N/A"
    local vendor="N/A"
    local open_ports="N/A"
    
    # Si responde a ping, obtenemos más información
    if [[ $icmp_result -eq 0 ]]; then
        mac=$(arp_check "$ip")
        if [[ "$mac" != "N/A" ]]; then
            vendor=$(get_vendor "$mac")
        fi
        open_ports=$(port_scan "$ip")
    fi
    
    echo "$ip,$icmp_result,$mac,$vendor,$open_ports"
}

# Escaneo paralelo de múltiples hosts
function parallel_scan {
    local ips=("$@")
    local results=()
    local temp_dir="/tmp/netscan_$"
    local batch_size=10  # Procesar en lotes de 10
    local completed=0
    
    mkdir -p "$temp_dir"
    
    # Procesar en lotes para evitar sobrecarga
    for ((i=0; i<${#ips[@]}; i+=batch_size)); do
        local batch_pids=()
        local batch_end=$((i+batch_size))
        [[ $batch_end -gt ${#ips[@]} ]] && batch_end=${#ips[@]}
        
        # Lanzar escaneos del lote actual
        for ((j=i; j<batch_end; j++)); do
            local ip="${ips[$j]}"
            (
                local result=$(full_scan "$ip")
                echo "$result" > "$temp_dir/result_$j"
                echo "done" > "$temp_dir/status_$j"
            ) &
            batch_pids+=($!)
        done
        
        # Monitorear progreso mientras esperamos
        local all_done=false
        while ! $all_done; do
            all_done=true
            local current_completed=0
            
            # Contar cuántos han terminado
            for ((k=0; k<${#ips[@]}; k++)); do
                if [[ -f "$temp_dir/status_$k" ]]; then
                    ((current_completed++))
                fi
            done
            
            # Actualizar barra si hay cambios
            if [[ $current_completed -ne $completed ]]; then
                completed=$current_completed
                progress_bar $completed ${#ips[@]}
            fi
            
            # Verificar si todos los del lote actual terminaron
            for pid in "${batch_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    all_done=false
                    break
                fi
            done
            
            [[ $all_done == false ]] && sleep 0.1
        done
    done
    
    # Recopilar todos los resultados en orden
    for ((i=0; i<${#ips[@]}; i++)); do
        if [[ -f "$temp_dir/result_$i" ]]; then
            results+=("$(cat "$temp_dir/result_$i")")
        fi
    done
    
    # Limpiar
    rm -rf "$temp_dir"
    
    echo "${results[@]}"
}

# Barra de progreso simple
function progress_bar {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    for ((i=0; i<completed; i++)); do printf "="; done
    for ((i=completed; i<width; i++)); do printf " "; done
    printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
}

# Menú principal
function menu {
    cleaner
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║              Enhanced Network Scanner v2.0                   ║${END}"
    echo -e "${CYAN}║          Escaneo de Capas 2, 3 y 7 del modelo OSI           ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${END}"
    echo ""
    PS3="¿Qué tipo de escaneo deseas realizar? "
    options=("Escaneo Rápido (Solo Ping)" "Escaneo Completo (Capas 2,3,7)" "Ver Solo UP" "Ver Solo DOWN" "Salir")
    
    select option in "${options[@]}"
    do
        case $option in
            "Escaneo Rápido (Solo Ping)")
                quick_scan
                ;;
            "Escaneo Completo (Capas 2,3,7)")
                full_network_scan
                ;;
            "Ver Solo UP")
                show_ips "up"
                ;;
            "Ver Solo DOWN")
                show_ips "down"
                ;;
            "Salir")
                exit
                ;;
            *)
                echo "Opción inválida. Intenta de nuevo."
                ;;
        esac
    done
}

# Escaneo rápido paralelo
function quick_scan {
    cleaner
    echo -e "${YELLOW}Realizando escaneo rápido...${END}"
    echo ""
    
    local total=${#IP_LIST[@]}
    local up_count=0
    local down_count=0
    local temp_dir="/tmp/quickscan_$"
    local batch_size=20
    local completed=0
    
    mkdir -p "$temp_dir"
    
    # Lanzar todos los pings en paralelo pero en lotes controlados
    for ((i=0; i<total; i+=batch_size)); do
        local batch_pids=()
        local batch_end=$((i+batch_size))
        [[ $batch_end -gt $total ]] && batch_end=$total
        
        for ((j=i; j<batch_end; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                if [[ $(icmp_ping "$ip") -eq 0 ]]; then
                    echo "up" > "$temp_dir/ping_$j"
                else
                    echo "down" > "$temp_dir/ping_$j"
                fi
                echo "done" > "$temp_dir/status_$j"
            ) &
            batch_pids+=($!)
        done
        
        # Monitorear progreso del lote actual
        local batch_done=false
        while ! $batch_done; do
            batch_done=true
            local current_completed=0
            
            # Contar cuántos han terminado en total
            for ((k=0; k<total; k++)); do
                if [[ -f "$temp_dir/status_$k" ]]; then
                    ((current_completed++))
                fi
            done
            
            # Actualizar barra si hay cambios
            if [[ $current_completed -ne $completed ]]; then
                completed=$current_completed
                progress_bar $completed $total
            fi
            
            # Verificar si el lote actual terminó
            for pid in "${batch_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    batch_done=false
                    break
                fi
            done
            
            [[ $batch_done == false ]] && sleep 0.05
        done
    done
    
    # Asegurar que la barra llegue al 100%
    progress_bar $total $total
    
    # Contar resultados
    for ((i=0; i<total; i++)); do
        if [[ -f "$temp_dir/ping_$i" ]]; then
            local status=$(cat "$temp_dir/ping_$i")
            if [[ "$status" == "up" ]]; then
                ((up_count++))
            else
                ((down_count++))
            fi
        fi
    done
    
    rm -rf "$temp_dir"
    
    echo ""
    echo ""
    echo -e "${GREEN}Hosts UP: $up_count${END}"
    echo -e "${RED}Hosts DOWN: $down_count${END}"
    echo -e "${BLUE}Total escaneados: $total${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
    menu
}

# Escaneo completo con paralelización
function full_network_scan {
    cleaner
    echo -e "${YELLOW}Realizando escaneo completo (Capas 2, 3 y 7)...${END}"
    echo -e "${YELLOW}Con optimización paralela...${END}"
    echo ""
    
    local total=${#IP_LIST[@]}
    local temp_dir="/tmp/fullscan_$"
    local batch_size=10
    local completed=0
    local results=()
    
    mkdir -p "$temp_dir"
    
    # Encabezado del log
    echo "IP,ICMP_STATUS,MAC_ADDRESS,VENDOR,OPEN_PORTS,TIMESTAMP" > "$log_file"
    
    # Mostrar barra de progreso inicial
    progress_bar 0 $total
    
    # Procesar en lotes con actualización de progreso
    for ((i=0; i<total; i+=batch_size)); do
        local batch_pids=()
        local batch_end=$((i+batch_size))
        [[ $batch_end -gt $total ]] && batch_end=$total
        
        # Lanzar escaneos del lote actual
        for ((j=i; j<batch_end; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                local result=$(full_scan "$ip")
                echo "$result" > "$temp_dir/result_$j"
                echo "$result,$(date)" >> "$log_file"
                echo "done" > "$temp_dir/status_$j"
            ) &
            batch_pids+=($!)
        done
        
        # Monitorear progreso mientras esperamos
        local all_done=false
        while ! $all_done; do
            all_done=true
            local current_completed=0
            
            # Contar cuántos han terminado
            for ((k=0; k<total; k++)); do
                if [[ -f "$temp_dir/status_$k" ]]; then
                    ((current_completed++))
                fi
            done
            
            # Actualizar barra si hay cambios
            if [[ $current_completed -ne $completed ]]; then
                completed=$current_completed
                progress_bar $completed $total
            fi
            
            # Verificar si todos los del lote actual terminaron
            for pid in "${batch_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    all_done=false
                    break
                fi
            done
            
            [[ $all_done == false ]] && sleep 0.1
        done
    done
    
    # Asegurar que la barra llegue al 100%
    progress_bar $total $total
    
    # Recopilar todos los resultados en orden
    for ((i=0; i<total; i++)); do
        if [[ -f "$temp_dir/result_$i" ]]; then
            results+=("$(cat "$temp_dir/result_$i")")
        fi
    done
    
    # Limpiar
    rm -rf "$temp_dir"
    
    echo ""
    echo ""
    display_results "${results[@]}"
}

# Mostrar resultados formateados
function display_results {
    local results=("$@")
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                                                                                    RESULTADOS DEL ESCANEO COMPLETO                                                                                     ║${END}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${END}"
    printf "${CYAN}║ %-15s ║ %-8s ║ %-17s ║ %-12s ║ %-30s ║${END}\n" "IP ADDRESS" "STATUS" "MAC ADDRESS" "VENDOR" "OPEN PORTS"
    echo -e "${CYAN}╠═════════════════╬══════════╬═══════════════════╬══════════════╬════════════════════════════════╣${END}"
    
    local up_count=0
    local down_count=0
    
    for result in "${results[@]}"; do
        IFS=',' read -r ip icmp_status mac vendor ports <<< "$result"
        
        if [[ $icmp_status -eq 0 ]]; then
            printf "${GREEN}║ %-15s ║ %-8s ║ %-17s ║ %-12s ║ %-30s ║${END}\n" "$ip" "UP" "$mac" "$vendor" "$ports"
            ((up_count++))
        else
            printf "${RED}║ %-15s ║ %-8s ║ %-17s ║ %-12s ║ %-30s ║${END}\n" "$ip" "DOWN" "$mac" "$vendor" "$ports"
            ((down_count++))
        fi
    done
    
    echo -e "${CYAN}╚═════════════════╩══════════╩═══════════════════╩══════════════╩════════════════════════════════╝${END}"
    echo ""
    echo -e "${GREEN}Hosts UP: $up_count${END}"
    echo -e "${RED}Hosts DOWN: $down_count${END}"
    echo -e "${BLUE}Total escaneados: $((up_count + down_count))${END}"
    echo -e "${YELLOW}Log guardado en: $log_file${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
    menu
}

# Muestra IPs según el estado seleccionado (optimizada)
function show_ips {
    cleaner
    if [[ $1 == "up" ]]; then
        echo -e "${GREEN}DISPOSITIVOS UP${END}"
    else
        echo -e "${RED}DISPOSITIVOS DOWN${END}"
    fi
    echo ""
    
    local total=${#IP_LIST[@]}
    local count=0
    local found_ips=()
    
    # Primero verificar cache, luego escanear los que faltan
    for i in "${!IP_LIST[@]}"; do
        local ip="${IP_LIST[$i]}"
        local result
        
        # Usar cache si existe
        if [[ -n "${PING_CACHE[$ip]+set}" ]]; then
            result=${PING_CACHE[$ip]}
        else
            result=$(icmp_ping "$ip")
        fi
        
        progress_bar $((i+1)) $total
        
        case $1 in
            "up")
                if [[ $result -eq 0 ]]; then
                    found_ips+=("$ip")
                    ((count++))
                fi
                ;;
            "down")
                if [[ $result -ne 0 ]]; then
                    found_ips+=("$ip")
                    ((count++))
                fi
                ;;
        esac
    done
    
    echo ""
    echo ""
    # Mostrar todas las IPs encontradas
    for ip in "${found_ips[@]}"; do
        if [[ $1 == "up" ]]; then
            echo -e "${GREEN}$ip${END}"
        else
            echo -e "${RED}$ip${END}"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Total encontrados: $count${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
    menu
}

# Verificar si el script se ejecuta como root para algunas funciones
function check_permissions {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Nota: Ejecutar como root mejora la precisión del escaneo de puertos${END}"
        echo ""
    fi
}

# Limpiar cache al salir
function cleanup {
    unset PING_CACHE
    unset ARP_CACHE
    unset PORT_CACHE
    unset IP_LIST
}

# Función principal
function main {
    # Configurar trap para limpiar al salir
    trap cleanup EXIT
    
    # Cargar IPs una sola vez
    load_ips
    
    check_permissions
    menu
}

# Ejecutar el script
main
