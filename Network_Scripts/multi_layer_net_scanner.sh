#!/bin/bash

# Colores para output
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
END="\e[0m"

# Configuración
LOG_FILE="network_scan_$(date +%Y%m%d_%H%M%S).log"
BATCH_SIZE_FULL=10
BATCH_SIZE_QUICK=30
TEMP_DIR="/tmp/netscan_$$"

# Arrays globales
declare -A PING_CACHE
declare -A ARP_CACHE  
declare -A PORT_CACHE
declare -a IP_LIST
declare -a REDES_DISPONIBLES
declare -a INTERFACES_INFO

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

# ═══════════════════════════════════════════════════════════════════════════
# NUEVAS FUNCIONES PARA DETECCIÓN DE REDES
# ═══════════════════════════════════════════════════════════════════════════

# Detectar todas las redes disponibles
function detectar_redes {
    REDES_DISPONIBLES=()
    INTERFACES_INFO=()
    
    # Obtener interfaces activas con IPs IPv4
    while IFS= read -r linea; do
        local interfaz=$(echo "$linea" | awk '{print $1}')
        local ip_cidr=$(echo "$linea" | awk '{print $2}')
        
        # Extraer IP y máscara
        local ip=$(echo "$ip_cidr" | cut -d'/' -f1)
        local mascara=$(echo "$ip_cidr" | cut -d'/' -f2)
        
        # Calcular red base
        local red_base=$(calcular_red_base "$ip" "$mascara")
        
        REDES_DISPONIBLES+=("${red_base}/${mascara}")
        INTERFACES_INFO+=("${interfaz}|${ip}|${red_base}/${mascara}")
        
    done < <(ip -o -4 addr show | grep -v "127.0.0.1" | awk '{print $2, $4}')
}

# Calcular la dirección de red base
function calcular_red_base {
    local ip=$1
    local mascara=$2
    
    # Convertir IP a número
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    
    # Calcular máscara en formato decimal
    local mask_bits=$((0xFFFFFFFF << (32 - mascara) & 0xFFFFFFFF))
    local m1=$(( (mask_bits >> 24) & 255 ))
    local m2=$(( (mask_bits >> 16) & 255 ))
    local m3=$(( (mask_bits >> 8) & 255 ))
    local m4=$(( mask_bits & 255 ))
    
    # Aplicar máscara
    echo "$((o1 & m1)).$((o2 & m2)).$((o3 & m3)).$((o4 & m4))"
}

# Generar lista de IPs desde CIDR
function generar_ips_desde_cidr {
    local cidr=$1
    local red=$(echo "$cidr" | cut -d'/' -f1)
    local mascara=$(echo "$cidr" | cut -d'/' -f2)
    
    IFS='.' read -r o1 o2 o3 o4 <<< "$red"
    
    IP_LIST=()
    
    case $mascara in
        24)
            # /24 = 254 hosts
            for i in $(seq 1 254); do
                IP_LIST+=("${o1}.${o2}.${o3}.${i}")
            done
            ;;
        25)
            # /25 = 126 hosts
            local inicio=$((o4 & 128))
            for i in $(seq $((inicio + 1)) $((inicio + 126))); do
                IP_LIST+=("${o1}.${o2}.${o3}.${i}")
            done
            ;;
        26)
            # /26 = 62 hosts
            local inicio=$((o4 & 192))
            for i in $(seq $((inicio + 1)) $((inicio + 62))); do
                IP_LIST+=("${o1}.${o2}.${o3}.${i}")
            done
            ;;
        23)
            # /23 = 510 hosts
            for j in $(seq 0 1); do
                for i in $(seq 1 254); do
                    IP_LIST+=("${o1}.${o2}.$((o3 + j)).${i}")
                done
            done
            ;;
        22)
            # /22 = 1022 hosts
            for j in $(seq 0 3); do
                for i in $(seq 1 254); do
                    IP_LIST+=("${o1}.${o2}.$((o3 + j)).${i}")
                done
            done
            ;;
        16)
            # /16 = muchos hosts, advertir
            echo -e "${YELLOW}Advertencia: /16 tiene 65534 hosts. Esto puede tardar mucho.${END}"
            read -p "¿Continuar? [s/N]: " confirmar
            [[ "$confirmar" != "s" && "$confirmar" != "S" ]] && return 1
            
            for j in $(seq 0 255); do
                for i in $(seq 1 254); do
                    IP_LIST+=("${o1}.${o2}.${j}.${i}")
                done
            done
            ;;
        *)
            echo -e "${RED}Máscara /${mascara} no soportada directamente.${END}"
            echo -e "${YELLOW}Máscaras soportadas: /16, /22, /23, /24, /25, /26${END}"
            return 1
            ;;
    esac
    
    return 0
}

# Parsear entrada manual de rangos
function parsear_rango_manual {
    local input=$1
    
    IP_LIST=()
    
    # Detectar formato CIDR (192.168.1.0/24)
    if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        generar_ips_desde_cidr "$input"
        return $?
    fi
    
    # Detectar rango con guión (192.168.1.1-254 o 192.168.1.1-192.168.1.254)
    if [[ "$input" =~ - ]]; then
        local parte1=$(echo "$input" | cut -d'-' -f1)
        local parte2=$(echo "$input" | cut -d'-' -f2)
        
        # Formato corto: 192.168.1.1-254
        if [[ "$parte2" =~ ^[0-9]+$ ]]; then
            IFS='.' read -r o1 o2 o3 o4 <<< "$parte1"
            for i in $(seq $o4 $parte2); do
                IP_LIST+=("${o1}.${o2}.${o3}.${i}")
            done
            return 0
        fi
        
        # Formato largo: 192.168.1.1-192.168.1.254
        if [[ "$parte2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IFS='.' read -r s1 s2 s3 s4 <<< "$parte1"
            IFS='.' read -r e1 e2 e3 e4 <<< "$parte2"
            
            # Solo soportamos rangos en el último octeto por simplicidad
            if [[ "$s1.$s2.$s3" == "$e1.$e2.$e3" ]]; then
                for i in $(seq $s4 $e4); do
                    IP_LIST+=("${s1}.${s2}.${s3}.${i}")
                done
                return 0
            else
                echo -e "${RED}Solo se soportan rangos dentro del mismo /24${END}"
                return 1
            fi
        fi
    fi
    
    # Detectar lista separada por comas
    if [[ "$input" =~ , ]]; then
        IFS=',' read -ra ips <<< "$input"
        for ip in "${ips[@]}"; do
            ip=$(echo "$ip" | tr -d ' ')
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                IP_LIST+=("$ip")
            fi
        done
        return 0
    fi
    
    # IP única
    if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IP_LIST+=("$input")
        return 0
    fi
    
    echo -e "${RED}Formato no reconocido${END}"
    return 1
}

# Menú para seleccionar origen de IPs
function menu_seleccion_red {
    limpiar_pantalla
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                      SELECCIÓN DE RED A ESCANEAR                            ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${END}"
    echo ""
    
    # Detectar redes
    detectar_redes
    
    if [[ ${#REDES_DISPONIBLES[@]} -eq 0 ]]; then
        echo -e "${RED}No se detectaron redes activas${END}"
        read -p "Presiona Enter para continuar..."
        return 1
    fi
    
    echo -e "${GREEN}Redes detectadas automáticamente:${END}"
    echo ""
    echo -e "${CYAN}┌─────┬────────────┬───────────────────┬─────────────────────┬───────────┐${END}"
    printf "${CYAN}│ %-3s │ %-10s │ %-17s │ %-19s │ %-9s │${END}\n" "#" "INTERFAZ" "TU IP" "RED" "HOSTS"
    echo -e "${CYAN}├─────┼────────────┼───────────────────┼─────────────────────┼───────────┤${END}"
    
    local idx=1
    for info in "${INTERFACES_INFO[@]}"; do
        IFS='|' read -r interfaz ip red <<< "$info"
        local mascara=$(echo "$red" | cut -d'/' -f2)
        local hosts=$((2 ** (32 - mascara) - 2))
        
        printf "${YELLOW}│ %-3s │${END} %-10s ${YELLOW}│${END} ${GREEN}%-17s${END} ${YELLOW}│${END} %-19s ${YELLOW}│${END} %-9s ${YELLOW}│${END}\n" \
            "$idx" "$interfaz" "$ip" "$red" "$hosts"
        ((idx++))
    done
    
    echo -e "${CYAN}└─────┴────────────┴───────────────────┴─────────────────────┴───────────┘${END}"
    echo ""
    
    local total_redes=${#REDES_DISPONIBLES[@]}
    
    echo -e "${YELLOW}Opciones:${END}"
    echo -e "  ${BOLD}1-${total_redes}${END}     Seleccionar una red específica"
    echo -e "  ${BOLD}A${END}       Escanear TODAS las redes"
    echo -e "  ${BOLD}M${END}       Introducir rango manualmente"
    echo -e "  ${BOLD}F${END}       Cargar desde archivo"
    echo -e "  ${BOLD}Q${END}       Volver al menú principal"
    echo ""
    
    read -p "Selecciona [1-${total_redes}/A/M/F/Q]: " opcion
    
    case "${opcion^^}" in
        [1-9]|[1-9][0-9])
            if [[ $opcion -ge 1 && $opcion -le $total_redes ]]; then
                local red_seleccionada="${REDES_DISPONIBLES[$((opcion-1))]}"
                echo -e "\n${GREEN}Generando lista de IPs para $red_seleccionada...${END}"
                generar_ips_desde_cidr "$red_seleccionada"
                return $?
            else
                echo -e "${RED}Opción inválida${END}"
                sleep 1
                return 1
            fi
            ;;
        A)
            echo -e "\n${GREEN}Generando lista de IPs para TODAS las redes...${END}"
            IP_LIST=()
            for red in "${REDES_DISPONIBLES[@]}"; do
                local temp_list=()
                generar_ips_desde_cidr "$red"
                # Nota: IP_LIST se va acumulando
            done
            
            # Eliminar duplicados y ordenar
            mapfile -t IP_LIST < <(printf '%s\n' "${IP_LIST[@]}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | uniq)
            return 0
            ;;
        M)
            echo ""
            echo -e "${CYAN}Formatos aceptados:${END}"
            echo "  • CIDR:        192.168.1.0/24"
            echo "  • Rango corto: 192.168.1.1-254"
            echo "  • Rango largo: 192.168.1.1-192.168.1.100"
            echo "  • Lista:       192.168.1.1,192.168.1.5,192.168.1.10"
            echo "  • IP única:    192.168.1.1"
            echo ""
            read -p "Introduce el rango: " rango_manual
            parsear_rango_manual "$rango_manual"
            return $?
            ;;
        F)
            echo ""
            read -p "Ruta del archivo: " archivo
            if [[ -f "$archivo" ]]; then
                mapfile -t IP_LIST < <(sort -u "$archivo")
                echo -e "${GREEN}Cargadas ${#IP_LIST[@]} IPs desde $archivo${END}"
                sleep 1
                return 0
            else
                echo -e "${RED}Archivo no encontrado: $archivo${END}"
                sleep 1
                return 1
            fi
            ;;
        Q)
            return 2
            ;;
        *)
            echo -e "${RED}Opción inválida${END}"
            sleep 1
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# FUNCIONES DE ESCANEO (del script original)
# ═══════════════════════════════════════════════════════════════════════════

# Test ICMP con caché
function ping_ip {
    local ip=$1
    
    if [[ -n "${PING_CACHE[$ip]+set}" ]]; then
        echo "${PING_CACHE[$ip]}"
        return
    fi
    
    ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
    local resultado=$?
    PING_CACHE[$ip]=$resultado
    echo $resultado
}

# Obtener MAC address
function obtener_mac {
    local ip=$1
    
    if [[ -n "${ARP_CACHE[$ip]+set}" ]]; then
        echo "${ARP_CACHE[$ip]}"
        return
    fi
    
    if [[ -z "${PING_CACHE[$ip]+set}" ]]; then
        ping -c 1 -W 1 "$ip" > /dev/null 2>&1
        PING_CACHE[$ip]=$?
    fi
    
    sleep 0.1
    
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
        "00:1B:21"|"00:A0:C9"|"3C:FD:FE"|"A4:BF:01") echo "Intel" ;;
        "00:E0:4C"|"52:54:00") echo "Realtek/KVM" ;;
        "00:23:AE"|"00:1A:2F") echo "Cisco" ;;
        "00:1A:A0"|"F8:BC:12") echo "Dell" ;;
        "00:50:B6"|"3C:D9:2B") echo "HP" ;;
        "00:25:90"|"00:26:B9") echo "SuperMicro" ;;
        "52:6B:8D") echo "Proxmox/KVM" ;;
        *) echo "Unknown" ;;
    esac
}

# Escaneo de puertos optimizado
function escanear_puertos {
    local ip=$1
    
    if [[ -n "${PORT_CACHE[$ip]+set}" ]]; then
        echo "${PORT_CACHE[$ip]}"
        return
    fi
    
    local puertos=("22" "23" "25" "53" "80" "110" "143" "443" "993" "995" "3389" "8080" "8443")
    local puertos_abiertos=()
    
    if command -v nc >/dev/null 2>&1; then
        for puerto in "${puertos[@]}"; do
            if nc -z -w1 "$ip" "$puerto" 2>/dev/null; then
                puertos_abiertos+=("$puerto")
            fi
        done
    else
        for puerto in "${puertos[@]}"; do
            (timeout 0.3 bash -c "echo >/dev/tcp/$ip/$puerto" 2>/dev/null && echo "$puerto" > "$TEMP_DIR/port_${ip}_${puerto}") &
        done
        
        sleep 0.5
        
        for puerto in "${puertos[@]}"; do
            [[ -f "$TEMP_DIR/port_${ip}_${puerto}" ]] && puertos_abiertos+=("$puerto")
        done
        
        rm -f "$TEMP_DIR/port_${ip}_"*
    fi
    
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

# Verificar que hay IPs cargadas
function verificar_ips_cargadas {
    if [[ ${#IP_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}No hay IPs cargadas. Selecciona una red primero.${END}"
        sleep 2
        return 1
    fi
    return 0
}

# Escaneo completo con visualización en tiempo real
function escaneo_completo {
    verificar_ips_cargadas || return
    
    limpiar_pantalla
    echo -e "${YELLOW}Iniciando escaneo completo de red...${END}"
    echo -e "${CYAN}Capas OSI: 2 (ARP), 3 (ICMP), 7 (Puertos)${END}"
    echo -e "${BLUE}IPs a escanear: ${#IP_LIST[@]}${END}"
    sleep 2
    
    local total=${#IP_LIST[@]}
    local completados=0
    local total_up=0
    local total_down=0
    
    # Limpiar caché para nuevo escaneo
    PING_CACHE=()
    ARP_CACHE=()
    PORT_CACHE=()
    
    echo "IP,ICMP_STATUS,MAC_ADDRESS,VENDOR,OPEN_PORTS,TIMESTAMP" > "$LOG_FILE"
    
    for ((i=0; i<total; i+=BATCH_SIZE_FULL)); do
        local fin=$((i + BATCH_SIZE_FULL))
        [[ $fin -gt $total ]] && fin=$total
        
        rm -f "$TEMP_DIR/resultado_"* "$TEMP_DIR/estado_"*
        
        mostrar_lote_actual $i $fin $total "completo"
        mostrar_progreso $completados $total
        
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                local resultado=$(escanear_host "$ip")
                echo "$resultado" > "$TEMP_DIR/resultado_$j"
                touch "$TEMP_DIR/estado_$j"
            ) &
        done
        
        local lote_completo=false
        while ! $lote_completo; do
            lote_completo=true
            local lote_terminados=0
            
            for ((j=i; j<fin; j++)); do
                if [[ -f "$TEMP_DIR/estado_$j" ]]; then
                    ((lote_terminados++))
                else
                    lote_completo=false
                fi
            done
            
            completados=$((i + lote_terminados))
            mostrar_lote_actual $i $fin $total "completo"
            mostrar_progreso $completados $total
            
            [[ $lote_completo == false ]] && sleep 0.3
        done
        
        for ((j=i; j<fin; j++)); do
            if [[ -f "$TEMP_DIR/resultado_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/resultado_$j")
                echo "$resultado,$(date +%Y-%m-%d\ %H:%M:%S)" >> "$LOG_FILE"
                
                IFS=',' read -r ip estado resto <<< "$resultado"
                if [[ $estado -eq 0 ]]; then
                    ((total_up++))
                else
                    ((total_down++))
                fi
            fi
        done
        
        echo -e "\n${BLUE}Lote completado. Total acumulado - UP: $total_up | DOWN: $total_down${END}"
        sleep 2
    done
    
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
    verificar_ips_cargadas || return
    
    limpiar_pantalla
    echo -e "${YELLOW}Iniciando escaneo rápido (solo ICMP)...${END}"
    echo -e "${BLUE}IPs a escanear: ${#IP_LIST[@]}${END}"
    sleep 1
    
    local total=${#IP_LIST[@]}
    local total_up=0
    local total_down=0
    
    # Limpiar caché
    PING_CACHE=()
    
    for ((i=0; i<total; i+=BATCH_SIZE_QUICK)); do
        local fin=$((i + BATCH_SIZE_QUICK))
        [[ $fin -gt $total ]] && fin=$total
        
        rm -f "$TEMP_DIR/ping_"* "$TEMP_DIR/ping_estado_"*
        
        mostrar_lote_actual $i $fin $total "rapido"
        mostrar_progreso $i $total
        
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                local resultado=$(ping_ip "$ip")
                echo "$resultado" > "$TEMP_DIR/ping_$j"
                touch "$TEMP_DIR/ping_estado_$j"
            ) &
        done
        
        local lote_completo=false
        while ! $lote_completo; do
            lote_completo=true
            
            for ((j=i; j<fin; j++)); do
                if [[ ! -f "$TEMP_DIR/ping_estado_$j" ]]; then
                    lote_completo=false
                    break
                fi
            done
            
            mostrar_lote_actual $i $fin $total "rapido"
            mostrar_progreso $((i + $(ls "$TEMP_DIR"/ping_estado_* 2>/dev/null | wc -l))) $total
            
            [[ $lote_completo == false ]] && sleep 0.1
        done
        
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
    
    verificar_ips_cargadas || return
    
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
        echo -e "${CYAN}║         Network Scanner v4.0 - Multi-Red                     ║${END}"
        echo -e "${CYAN}║      Escaneo de Capas 2, 3 y 7 del modelo OSI               ║${END}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${END}"
        echo ""
        
        # Mostrar red seleccionada actualmente
        if [[ ${#IP_LIST[@]} -gt 0 ]]; then
            echo -e "${GREEN}Red cargada: ${#IP_LIST[@]} IPs${END}"
            echo -e "${BLUE}Rango: ${IP_LIST[0]} - ${IP_LIST[-1]}${END}"
        else
            echo -e "${YELLOW}⚠ No hay red seleccionada${END}"
        fi
        echo ""
        
        echo -e "${YELLOW}1)${END} Seleccionar Red / Rango de IPs"
        echo -e "${YELLOW}2)${END} Escaneo Rápido (Solo Ping)"
        echo -e "${YELLOW}3)${END} Escaneo Completo (Capas 2,3,7)"
        echo -e "${YELLOW}4)${END} Ver Solo Hosts UP"
        echo -e "${YELLOW}5)${END} Ver Solo Hosts DOWN"
        echo -e "${YELLOW}6)${END} Salir"
        echo ""
        read -p "Seleccione una opción [1-6]: " opcion
        
        case $opcion in
            1) 
                menu_seleccion_red
                local ret=$?
                if [[ $ret -eq 0 ]]; then
                    echo -e "\n${GREEN}✓ ${#IP_LIST[@]} IPs cargadas correctamente${END}"
                    sleep 1
                fi
                ;;
            2) escaneo_rapido ;;
            3) escaneo_completo ;;
            4) mostrar_hosts "up" ;;
            5) mostrar_hosts "down" ;;
            6) echo -e "${GREEN}Saliendo...${END}"; exit 0 ;;
            *) echo -e "${RED}Opción inválida${END}"; sleep 1 ;;
        esac
    done
}

# Verificar permisos
function verificar_permisos {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Nota: Ejecutar como root mejora la precisión del ARP${END}"
        echo -e "${YELLOW}Para mejor rendimiento, instale 'netcat' (nc)${END}"
        echo ""
        sleep 2
    fi
}

# Función principal
function main {
    trap limpiar_temp EXIT INT TERM
    verificar_permisos
    menu_principal
}

# Ejecutar
main
