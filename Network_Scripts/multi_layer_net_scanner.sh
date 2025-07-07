#!/bin/bash

# Colores para output
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
END="\e[0m"

# Configuración
ARCHIVO_IPS="ip.txt"
LOG_FILE="network_scan_$(date +%Y%m%d_%H%M%S).log"
BATCH_SIZE_FULL=10
BATCH_SIZE_QUICK=30
TEMP_DIR="/tmp/netscan_$$"

# Arrays globales para caché
declare -A PING_CACHE
declare -A ARP_CACHE  
declare -A PORT_CACHE
declare -a IP_LIST

# Crear directorio temporal
mkdir -p "$TEMP_DIR"

# Función para limpiar pantalla
function limpiar_pantalla {
    clear && clear
}

# Función para limpiar archivos temporales
function limpiar_temp {
    rm -rf "$TEMP_DIR"
    unset PING_CACHE ARP_CACHE PORT_CACHE IP_LIST
}

# Cargar IPs únicas desde archivo
function cargar_ips {
    if [[ ! -f "$ARCHIVO_IPS" ]]; then
        echo -e "${RED}Error: El archivo $ARCHIVO_IPS no existe${END}"
        exit 1
    fi
    
    # Cargar IPs únicas ordenadas
    mapfile -t IP_LIST < <(sort -u "$ARCHIVO_IPS")
    echo -e "${BLUE}IPs únicas cargadas: ${#IP_LIST[@]}${END}"
    sleep 1
}

# Test ICMP con caché
function ping_ip {
    local ip=$1
    
    # Revisar caché
    if [[ -n "${PING_CACHE[$ip]+set}" ]]; then
        echo "${PING_CACHE[$ip]}"
        return
    fi
    
    # Hacer ping
    ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
    local resultado=$?
    PING_CACHE[$ip]=$resultado
    echo $resultado
}

# Obtener MAC address
function obtener_mac {
    local ip=$1
    
    # Revisar caché
    if [[ -n "${ARP_CACHE[$ip]+set}" ]]; then
        echo "${ARP_CACHE[$ip]}"
        return
    fi
    
    # Si no hemos hecho ping, hacerlo primero
    if [[ -z "${PING_CACHE[$ip]+set}" ]]; then
        ping -c 1 -W 1 "$ip" > /dev/null 2>&1
        PING_CACHE[$ip]=$?
    fi
    
    # Pequeña espera para tabla ARP
    sleep 0.1
    
    # Obtener MAC
    local mac=$(ip neigh show "$ip" 2>/dev/null | awk '{print $5}')
    
    if [[ -n "$mac" && "$mac" != "<incomplete>" && "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        ARP_CACHE[$ip]="$mac"
        echo "$mac"
    else
        ARP_CACHE[$ip]="N/A"
        echo "N/A"
    fi
}

# Identificar fabricante por MAC
function obtener_fabricante {
    local mac=$1
    [[ "$mac" == "N/A" ]] && echo "N/A" && return
    
    local oui=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')
    
    case "$oui" in
        "00:50:56"|"00:0C:29"|"00:05:69") echo "VMware" ;;
        "08:00:27") echo "VirtualBox" ;;
        "00:15:5D"|"00:03:FF") echo "Microsoft" ;;
        "00:1B:21"|"00:A0:C9") echo "Intel" ;;
        "00:E0:4C") echo "Realtek" ;;
        "00:23:AE") echo "Cisco" ;;
        "00:1A:A0") echo "Dell" ;;
        "00:50:B6") echo "HP" ;;
        *) echo "Unknown" ;;
    esac
}

# Escaneo de puertos optimizado
function escanear_puertos {
    local ip=$1
    
    # Revisar caché
    if [[ -n "${PORT_CACHE[$ip]+set}" ]]; then
        echo "${PORT_CACHE[$ip]}"
        return
    fi
    
    local puertos=("22" "23" "25" "53" "80" "110" "143" "443" "993" "995")
    local puertos_abiertos=()
    
    # Preferir nc si está disponible
    if command -v nc >/dev/null 2>&1; then
        for puerto in "${puertos[@]}"; do
            if nc -z -w1 "$ip" "$puerto" 2>/dev/null; then
                puertos_abiertos+=("$puerto")
            fi
        done
    else
        # Fallback a /dev/tcp paralelo
        for puerto in "${puertos[@]}"; do
            (timeout 0.3 bash -c "echo >/dev/tcp/$ip/$puerto" 2>/dev/null && echo "$puerto" > "$TEMP_DIR/port_${ip}_${puerto}") &
        done
        
        # Esperar un poco
        sleep 0.5
        
        # Recolectar resultados
        for puerto in "${puertos[@]}"; do
            [[ -f "$TEMP_DIR/port_${ip}_${puerto}" ]] && puertos_abiertos+=("$puerto")
        done
        
        # Limpiar
        rm -f "$TEMP_DIR/port_${ip}_"*
    fi
    
    # Guardar en caché
    if [[ ${#puertos_abiertos[@]} -gt 0 ]]; then
        PORT_CACHE[$ip]="${puertos_abiertos[*]}"
        echo "${puertos_abiertos[*]}"
    else
        PORT_CACHE[$ip]="N/A"
        echo "N/A"
    fi
}

# Escaneo completo de un host
function escanear_host {
    local ip=$1
    local ping_result=$(ping_ip "$ip")
    local mac="N/A"
    local vendor="N/A"
    local ports="N/A"
    
    if [[ $ping_result -eq 0 ]]; then
        mac=$(obtener_mac "$ip")
        [[ "$mac" != "N/A" ]] && vendor=$(obtener_fabricante "$mac")
        ports=$(escanear_puertos "$ip")
    fi
    
    echo "$ip,$ping_result,$mac,$vendor,$ports"
}

# Barra de progreso
function mostrar_progreso {
    local actual=$1
    local total=$2
    local ancho=50
    local porcentaje=$((actual * 100 / total))
    local completado=$((actual * ancho / total))
    
    printf "\r["
    printf "%${completado}s" | tr ' ' '='
    printf "%$((ancho - completado))s"
    printf "] %d%% (%d/%d)" "$porcentaje" "$actual" "$total"
}

# Mostrar tabla de resultados del lote actual
function mostrar_lote_actual {
    local inicio=$1
    local fin=$2
    local total=$3
    local tipo=$4
    
    limpiar_pantalla
    
    if [[ "$tipo" == "completo" ]]; then
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo -e "${CYAN}           ESCANEO COMPLETO - Lote ${inicio}-${fin} de ${total} IPs${END}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo ""
        echo -e "${CYAN}┌─────────────────┬──────────┬───────────────────┬──────────────┬──────────────────────────────┐${END}"
        printf "${CYAN}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" "IP" "ESTADO" "MAC" "FABRICANTE" "PUERTOS"
        echo -e "${CYAN}├─────────────────┼──────────┼───────────────────┼──────────────┼──────────────────────────────┤${END}"
        
        local lote_up=0
        local lote_down=0
        
        for ((i=inicio; i<fin; i++)); do
            if [[ -f "$TEMP_DIR/resultado_$i" ]]; then
                local resultado=$(cat "$TEMP_DIR/resultado_$i")
                IFS=',' read -r ip estado mac vendor puertos <<< "$resultado"
                
                if [[ $estado -eq 0 ]]; then
                    printf "${GREEN}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" \
                        "$ip" "UP" "$mac" "$vendor" "$puertos"
                    ((lote_up++))
                else
                    printf "${RED}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" \
                        "$ip" "DOWN" "N/A" "N/A" "N/A"
                    ((lote_down++))
                fi
            else
                local ip="${IP_LIST[$i]}"
                printf "${YELLOW}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" \
                    "$ip" "SCAN..." "..." "..." "..."
            fi
        done
        
        echo -e "${CYAN}└─────────────────┴──────────┴───────────────────┴──────────────┴──────────────────────────────┘${END}"
        echo ""
        echo -e "${GREEN}UP: $lote_up${END} | ${RED}DOWN: $lote_down${END}"
    else
        # Escaneo rápido
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo -e "${CYAN}           ESCANEO RÁPIDO - Lote ${inicio}-${fin} de ${total} IPs${END}"  
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo ""
        
        for ((i=inicio; i<fin; i++)); do
            if [[ -f "$TEMP_DIR/ping_$i" ]]; then
                local ip="${IP_LIST[$i]}"
                local estado=$(cat "$TEMP_DIR/ping_$i")
                if [[ "$estado" == "0" ]]; then
                    echo -e "${GREEN}✓ $ip - UP${END}"
                else
                    echo -e "${RED}✗ $ip - DOWN${END}"
                fi
            fi
        done
    fi
    
    echo ""
}

# Escaneo completo con visualización en tiempo real
function escaneo_completo {
    limpiar_pantalla
    echo -e "${YELLOW}Iniciando escaneo completo de red...${END}"
    echo -e "${CYAN}Capas OSI: 2 (ARP), 3 (ICMP), 7 (Puertos)${END}"
    sleep 2
    
    local total=${#IP_LIST[@]}
    local completados=0
    local total_up=0
    local total_down=0
    
    # Crear archivo de log
    echo "IP,ICMP_STATUS,MAC_ADDRESS,VENDOR,OPEN_PORTS,TIMESTAMP" > "$LOG_FILE"
    
    # Procesar por lotes
    for ((i=0; i<total; i+=BATCH_SIZE_FULL)); do
        local fin=$((i + BATCH_SIZE_FULL))
        [[ $fin -gt $total ]] && fin=$total
        
        # Limpiar resultados anteriores del lote
        rm -f "$TEMP_DIR/resultado_"* "$TEMP_DIR/estado_"*
        
        # Mostrar estado inicial del lote
        mostrar_lote_actual $i $fin $total "completo"
        mostrar_progreso $completados $total
        
        # Lanzar escaneos en paralelo
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                local resultado=$(escanear_host "$ip")
                echo "$resultado" > "$TEMP_DIR/resultado_$j"
                touch "$TEMP_DIR/estado_$j"
            ) &
        done
        
        # Monitorear progreso del lote
        local lote_completo=false
        while ! $lote_completo; do
            lote_completo=true
            local lote_terminados=0
            
            # Contar terminados
            for ((j=i; j<fin; j++)); do
                if [[ -f "$TEMP_DIR/estado_$j" ]]; then
                    ((lote_terminados++))
                else
                    lote_completo=false
                fi
            done
            
            # Actualizar visualización
            completados=$((i + lote_terminados))
            mostrar_lote_actual $i $fin $total "completo"
            mostrar_progreso $completados $total
            
            [[ $lote_completo == false ]] && sleep 0.3
        done
        
        # Guardar resultados del lote al log
        for ((j=i; j<fin; j++)); do
            if [[ -f "$TEMP_DIR/resultado_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/resultado_$j")
                echo "$resultado,$(date +%Y-%m-%d\ %H:%M:%S)" >> "$LOG_FILE"
                
                # Contar estadísticas
                IFS=',' read -r ip estado resto <<< "$resultado"
                if [[ $estado -eq 0 ]]; then
                    ((total_up++))
                else
                    ((total_down++))
                fi
            fi
        done
        
        # Pausa para ver resultados del lote
        echo -e "\n${BLUE}Lote completado. Total acumulado - UP: $total_up | DOWN: $total_down${END}"
        sleep 2
    done
    
    # Mostrar resumen final
    limpiar_pantalla
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                    ESCANEO COMPLETADO                        ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${END}"
    echo ""
    echo -e "${GREEN}Hosts UP: $total_up${END}"
    echo -e "${RED}Hosts DOWN: $total_down${END}"
    echo -e "${BLUE}Total escaneado: $total${END}"
    echo -e "${YELLOW}Log guardado en: $LOG_FILE${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Escaneo rápido con visualización
function escaneo_rapido {
    limpiar_pantalla
    echo -e "${YELLOW}Iniciando escaneo rápido (solo ICMP)...${END}"
    sleep 1
    
    local total=${#IP_LIST[@]}
    local total_up=0
    local total_down=0
    
    # Procesar por lotes
    for ((i=0; i<total; i+=BATCH_SIZE_QUICK)); do
        local fin=$((i + BATCH_SIZE_QUICK))
        [[ $fin -gt $total ]] && fin=$total
        
        # Limpiar resultados anteriores
        rm -f "$TEMP_DIR/ping_"* "$TEMP_DIR/ping_estado_"*
        
        # Mostrar estado inicial
        mostrar_lote_actual $i $fin $total "rapido"
        mostrar_progreso $i $total
        
        # Lanzar pings en paralelo
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                local resultado=$(ping_ip "$ip")
                echo "$resultado" > "$TEMP_DIR/ping_$j"
                touch "$TEMP_DIR/ping_estado_$j"
            ) &
        done
        
        # Esperar y actualizar
        local lote_completo=false
        while ! $lote_completo; do
            lote_completo=true
            
            for ((j=i; j<fin; j++)); do
                if [[ ! -f "$TEMP_DIR/ping_estado_$j" ]]; then
                    lote_completo=false
                    break
                fi
            done
            
            # Actualizar vista
            mostrar_lote_actual $i $fin $total "rapido"
            mostrar_progreso $((i + $(ls "$TEMP_DIR"/ping_estado_* 2>/dev/null | wc -l))) $total
            
            [[ $lote_completo == false ]] && sleep 0.1
        done
        
        # Contar resultados del lote
        for ((j=i; j<fin; j++)); do
            if [[ -f "$TEMP_DIR/ping_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/ping_$j")
                if [[ $resultado -eq 0 ]]; then
                    ((total_up++))
                else
                    ((total_down++))
                fi
            fi
        done
        
        echo -e "\n${BLUE}Lote completado. UP: $total_up | DOWN: $total_down${END}"
        sleep 1
    done
    
    # Resumen final
    limpiar_pantalla
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║              ESCANEO RÁPIDO COMPLETADO                       ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${END}"
    echo ""
    echo -e "${GREEN}Hosts UP: $total_up${END}"
    echo -e "${RED}Hosts DOWN: $total_down${END}"
    echo -e "${BLUE}Total escaneado: $total${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Mostrar solo hosts UP o DOWN
function mostrar_hosts {
    local tipo=$1
    limpiar_pantalla
    
    if [[ "$tipo" == "up" ]]; then
        echo -e "${GREEN}═══════════════════════════════════════════${END}"
        echo -e "${GREEN}           HOSTS ACTIVOS (UP)              ${END}"
        echo -e "${GREEN}═══════════════════════════════════════════${END}"
    else
        echo -e "${RED}═══════════════════════════════════════════${END}"
        echo -e "${RED}          HOSTS INACTIVOS (DOWN)           ${END}"
        echo -e "${RED}═══════════════════════════════════════════${END}"
    fi
    echo ""
    
    local total=${#IP_LIST[@]}
    local encontrados=0
    
    for ((i=0; i<total; i++)); do
        local ip="${IP_LIST[$i]}"
        local resultado=$(ping_ip "$ip")
        
        mostrar_progreso $((i+1)) $total
        
        if [[ "$tipo" == "up" && $resultado -eq 0 ]]; then
            echo -e "\n${GREEN}✓ $ip${END}"
            ((encontrados++))
        elif [[ "$tipo" == "down" && $resultado -ne 0 ]]; then
            echo -e "\n${RED}✗ $ip${END}"
            ((encontrados++))
        fi
    done
    
    echo -e "\n\n${BLUE}Total encontrados: $encontrados de $total${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Menú principal
function menu_principal {
    while true; do
        limpiar_pantalla
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${END}"
        echo -e "${CYAN}║         Network Scanner v3.0 - Optimizado                    ║${END}"
        echo -e "${CYAN}║      Escaneo de Capas 2, 3 y 7 del modelo OSI              ║${END}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${END}"
        echo ""
        echo -e "${YELLOW}1)${END} Escaneo Rápido (Solo Ping)"
        echo -e "${YELLOW}2)${END} Escaneo Completo (Capas 2,3,7)"
        echo -e "${YELLOW}3)${END} Ver Solo Hosts UP"
        echo -e "${YELLOW}4)${END} Ver Solo Hosts DOWN"
        echo -e "${YELLOW}5)${END} Salir"
        echo ""
        read -p "Seleccione una opción [1-5]: " opcion
        
        case $opcion in
            1) escaneo_rapido ;;
            2) escaneo_completo ;;
            3) mostrar_hosts "up" ;;
            4) mostrar_hosts "down" ;;
            5) echo -e "${GREEN}Saliendo...${END}"; exit 0 ;;
            *) echo -e "${RED}Opción inválida${END}"; sleep 1 ;;
        esac
    done
}

# Verificar permisos
function verificar_permisos {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Nota: Ejecutar como root mejora la precisión${END}"
        echo -e "${YELLOW}Para mejor rendimiento, instale 'netcat' (nc)${END}"
        echo ""
        sleep 2
    fi
}

# Función principal
function main {
    # Configurar limpieza al salir
    trap limpiar_temp EXIT INT TERM
    
    # Cargar IPs
    cargar_ips
    
    # Verificar permisos
    verificar_permisos
    
    # Mostrar menú
    menu_principal
}

# Ejecutar
main
