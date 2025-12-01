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
                local base=$(echo "$red" | cut -d'/' -f1)
                local mascara=$(echo "$red" | cut -d'/' -f2)
                IFS='.' read -r o1 o2 o3 o4 <<< "$base"
                
                # Solo soportamos /24 para múltiples redes (simplicidad)
                if [[ "$mascara" == "24" ]]; then
                    for i in $(seq 1 254); do
                        IP_LIST+=("${o1}.${o2}.${o3}.${i}")
                    done
                    echo -e "  ${GREEN}✓${END} $red añadida (254 IPs)"
                else
                    echo -e "  ${YELLOW}⚠${END} $red omitida (solo /24 soportado en modo 'todas')"
                fi
            done
            
            if [[ ${#IP_LIST[@]} -eq 0 ]]; then
                echo -e "${RED}No se pudieron cargar IPs${END}"
                sleep 2
                return 1
            fi
            
            # Eliminar duplicados y ordenar
            mapfile -t IP_LIST < <(printf '%s\n' "${IP_LIST[@]}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | uniq)
            echo -e "\n${GREEN}Total: ${#IP_LIST[@]} IPs cargadas${END}"
            sleep 1
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
# FUNCIÓN PARA BUSCAR IPs LIBRES
# ═══════════════════════════════════════════════════════════════════════════

function buscar_ips_libres {
    limpiar_pantalla
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                        BUSCAR IPs LIBRES                                     ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${END}"
    echo ""
    
    # Detectar redes
    detectar_redes
    
    if [[ ${#REDES_DISPONIBLES[@]} -eq 0 ]]; then
        echo -e "${RED}No se detectaron redes activas${END}"
        read -p "Presiona Enter para continuar..."
        return 1
    fi
    
    # Mostrar redes disponibles
    echo -e "${GREEN}Redes disponibles:${END}"
    echo ""
    local idx=1
    for info in "${INTERFACES_INFO[@]}"; do
        IFS='|' read -r interfaz ip red <<< "$info"
        echo -e "  ${YELLOW}$idx)${END} $red (${interfaz} - Tu IP: ${GREEN}$ip${END})"
        ((idx++))
    done
    echo ""
    
    local total_redes=${#REDES_DISPONIBLES[@]}
    
    # Seleccionar red(es)
    echo -e "${CYAN}¿En qué red(es) buscar?${END}"
    echo -e "  Ejemplos: ${BOLD}1${END} | ${BOLD}1,2,3${END} | ${BOLD}A${END} (todas)"
    read -p "Selección: " seleccion_redes
    
    # Parsear selección de redes
    local redes_a_escanear=()
    
    if [[ "${seleccion_redes^^}" == "A" ]]; then
        redes_a_escanear=("${REDES_DISPONIBLES[@]}")
    else
        IFS=',' read -ra indices <<< "$seleccion_redes"
        for idx in "${indices[@]}"; do
            idx=$(echo "$idx" | tr -d ' ')
            if [[ "$idx" =~ ^[0-9]+$ && $idx -ge 1 && $idx -le $total_redes ]]; then
                redes_a_escanear+=("${REDES_DISPONIBLES[$((idx-1))]}")
            fi
        done
    fi
    
    if [[ ${#redes_a_escanear[@]} -eq 0 ]]; then
        echo -e "${RED}No se seleccionó ninguna red válida${END}"
        sleep 2
        return 1
    fi
    
    # Cuántas IPs libres buscar
    echo ""
    read -p "¿Cuántas IPs libres necesitas? [1-50]: " cantidad
    
    if ! [[ "$cantidad" =~ ^[0-9]+$ ]] || [[ $cantidad -lt 1 || $cantidad -gt 50 ]]; then
        echo -e "${RED}Cantidad inválida. Usando 5 por defecto.${END}"
        cantidad=5
    fi
    
    # Rango de búsqueda (opcional)
    echo ""
    echo -e "${CYAN}¿Rango específico dentro de cada red?${END}"
    echo -e "  Ejemplo: ${BOLD}100-200${END} para buscar solo en .100-.200"
    echo -e "  Dejar vacío para buscar en todo el rango (1-254)"
    read -p "Rango [Enter=todo]: " rango_especifico
    
    local rango_inicio=1
    local rango_fin=254
    
    if [[ "$rango_especifico" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        rango_inicio=${BASH_REMATCH[1]}
        rango_fin=${BASH_REMATCH[2]}
        if [[ $rango_inicio -lt 1 ]]; then rango_inicio=1; fi
        if [[ $rango_fin -gt 254 ]]; then rango_fin=254; fi
    fi
    
    echo ""
    echo -e "${YELLOW}Buscando $cantidad IPs libres en ${#redes_a_escanear[@]} red(es)...${END}"
    echo -e "${BLUE}Rango de búsqueda: .${rango_inicio} - .${rango_fin}${END}"
    echo ""
    
    # Arrays para resultados
    declare -a ips_libres=()
    declare -a ips_ocupadas=()
    local encontradas=0
    local escaneadas=0
    
    # Archivo de resultados
    local archivo_libres="ips_libres_$(date +%Y%m%d_%H%M%S).txt"
    echo "# IPs Libres encontradas - $(date)" > "$archivo_libres"
    echo "# Redes escaneadas: ${redes_a_escanear[*]}" >> "$archivo_libres"
    echo "# Rango: .${rango_inicio} - .${rango_fin}" >> "$archivo_libres"
    echo "" >> "$archivo_libres"
    
    # Escanear cada red
    for red in "${redes_a_escanear[@]}"; do
        [[ $encontradas -ge $cantidad ]] && break
        
        local base=$(echo "$red" | cut -d'/' -f1)
        IFS='.' read -r o1 o2 o3 o4 <<< "$base"
        
        echo -e "${CYAN}Escaneando red: $red${END}"
        
        # Generar IPs del rango
        local ips_red=()
        for ((i=rango_inicio; i<=rango_fin && encontradas < cantidad; i++)); do
            ips_red+=("${o1}.${o2}.${o3}.${i}")
        done
        
        local total_red=${#ips_red[@]}
        local idx=0
        
        # Escanear en lotes
        for ((i=0; i<total_red && encontradas < cantidad; i+=20)); do
            local fin=$((i + 20))
            [[ $fin -gt $total_red ]] && fin=$total_red
            
            # Limpiar temporales
            rm -f "$TEMP_DIR/libre_"*
            
            # Lanzar pings en paralelo
            for ((j=i; j<fin; j++)); do
                local ip="${ips_red[$j]}"
                (
                    ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
                    echo "$?" > "$TEMP_DIR/libre_$j"
                ) &
            done
            
            wait
            
            # Revisar resultados
            for ((j=i; j<fin && encontradas < cantidad; j++)); do
                local ip="${ips_red[$j]}"
                ((escaneadas++))
                
                if [[ -f "$TEMP_DIR/libre_$j" ]]; then
                    local resultado=$(cat "$TEMP_DIR/libre_$j")
                    if [[ "$resultado" != "0" ]]; then
                        # IP libre (no responde)
                        ips_libres+=("$ip")
                        echo -e "${GREEN}  ✓ $ip - LIBRE${END}"
                        echo "$ip" >> "$archivo_libres"
                        ((encontradas++))
                    else
                        ips_ocupadas+=("$ip")
                    fi
                fi
            done
            
            printf "\r  Progreso: %d/%d escaneadas, %d/%d libres encontradas" \
                $escaneadas $total_red $encontradas $cantidad
        done
        echo ""
    done
    
    # Limpiar temporales
    rm -f "$TEMP_DIR/libre_"*
    
    # Mostrar resumen
    limpiar_pantalla
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                    BÚSQUEDA DE IPs LIBRES - RESULTADOS                      ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${END}"
    echo ""
    echo -e "${BLUE}Redes escaneadas: ${redes_a_escanear[*]}${END}"
    echo -e "${BLUE}Rango buscado: .${rango_inicio} - .${rango_fin}${END}"
    echo -e "${BLUE}IPs verificadas: $escaneadas${END}"
    echo ""
    
    if [[ ${#ips_libres[@]} -gt 0 ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${END}"
        echo -e "${GREEN}║  IPs LIBRES ENCONTRADAS: ${#ips_libres[@]}                              ║${END}"
        echo -e "${GREEN}╠═══════════════════════════════════════════════════════════╣${END}"
        
        local col=0
        printf "${GREEN}║${END} "
        for ip in "${ips_libres[@]}"; do
            printf "%-17s" "$ip"
            ((col++))
            if [[ $col -eq 3 ]]; then
                printf "${GREEN}║${END}\n${GREEN}║${END} "
                col=0
            fi
        done
        [[ $col -ne 0 ]] && printf "%*s${GREEN}║${END}\n" $((17 * (3 - col))) ""
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${END}"
        
        echo ""
        echo -e "${YELLOW}Resultados guardados en: $archivo_libres${END}"
        
        # Preguntar si copiar al portapapeles (si está disponible xclip)
        if command -v xclip >/dev/null 2>&1; then
            echo ""
            read -p "¿Copiar IPs al portapapeles? [s/N]: " copiar
            if [[ "${copiar^^}" == "S" ]]; then
                printf '%s\n' "${ips_libres[@]}" | xclip -selection clipboard
                echo -e "${GREEN}✓ Copiado al portapapeles${END}"
            fi
        fi
    else
        echo -e "${RED}No se encontraron IPs libres en el rango especificado${END}"
    fi
    
    echo ""
    read -p "Presiona Enter para continuar..."
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
    local total_up=0
    local total_down=0
    
    # Arrays para guardar resultados detallados
    declare -a resultados_up=()
    declare -a hosts_down=()
    
    # Limpiar caché para nuevo escaneo
    PING_CACHE=()
    ARP_CACHE=()
    PORT_CACHE=()
    rm -f "$TEMP_DIR/resultado_"*
    
    # Archivo de log CSV
    local archivo_csv="scan_completo_$(date +%Y%m%d_%H%M%S).csv"
    local archivo_txt="scan_completo_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "IP,ESTADO,MAC_ADDRESS,FABRICANTE,PUERTOS_ABIERTOS,TIMESTAMP" > "$archivo_csv"
    
    for ((i=0; i<total; i+=BATCH_SIZE_FULL)); do
        local fin=$((i + BATCH_SIZE_FULL))
        [[ $fin -gt $total ]] && fin=$total
        
        # Lanzar escaneos en paralelo
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                # Hacer ping
                ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
                local ping_result=$?
                local mac="N/A"
                local vendor="N/A"
                local ports="N/A"
                
                if [[ $ping_result -eq 0 ]]; then
                    # Obtener MAC
                    sleep 0.1
                    mac=$(ip neigh show "$ip" 2>/dev/null | awk '{print $5}')
                    if [[ -z "$mac" || "$mac" == "<incomplete>" || ! "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                        mac="N/A"
                    fi
                    
                    # Obtener fabricante
                    if [[ "$mac" != "N/A" ]]; then
                        local oui=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')
                        case "$oui" in
                            "00:50:56"|"00:0C:29"|"00:05:69") vendor="VMware" ;;
                            "08:00:27") vendor="VirtualBox" ;;
                            "00:15:5D"|"00:03:FF") vendor="Microsoft" ;;
                            "00:1B:21"|"00:A0:C9"|"3C:FD:FE"|"A4:BF:01") vendor="Intel" ;;
                            "00:E0:4C"|"52:54:00") vendor="Realtek/KVM" ;;
                            "00:23:AE"|"00:1A:2F") vendor="Cisco" ;;
                            "00:1A:A0"|"F8:BC:12") vendor="Dell" ;;
                            "00:50:B6"|"3C:D9:2B") vendor="HP" ;;
                            "00:25:90"|"00:26:B9") vendor="SuperMicro" ;;
                            "52:6B:8D") vendor="Proxmox/KVM" ;;
                            *) vendor="Unknown" ;;
                        esac
                    fi
                    
                    # Escanear puertos
                    local puertos_list=("22" "23" "80" "443" "3389" "8080")
                    local puertos_abiertos=""
                    for puerto in "${puertos_list[@]}"; do
                        if timeout 0.5 bash -c "echo >/dev/tcp/$ip/$puerto" 2>/dev/null; then
                            [[ -n "$puertos_abiertos" ]] && puertos_abiertos+=" "
                            puertos_abiertos+="$puerto"
                        fi
                    done
                    [[ -z "$puertos_abiertos" ]] && puertos_abiertos="N/A"
                    ports="$puertos_abiertos"
                fi
                
                echo "$ip,$ping_result,$mac,$vendor,$ports" > "$TEMP_DIR/resultado_$j"
            ) &
        done
        
        # Esperar a que terminen todos los del lote
        wait
        
        # Mostrar resultados del lote
        limpiar_pantalla
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo -e "${CYAN}           ESCANEO COMPLETO - Lote $((i/BATCH_SIZE_FULL + 1)) de $(( (total + BATCH_SIZE_FULL - 1) / BATCH_SIZE_FULL ))${END}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo ""
        echo -e "${CYAN}┌─────────────────┬──────────┬───────────────────┬──────────────┬──────────────────────────────┐${END}"
        printf "${CYAN}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" "IP" "ESTADO" "MAC" "FABRICANTE" "PUERTOS"
        echo -e "${CYAN}├─────────────────┼──────────┼───────────────────┼──────────────┼──────────────────────────────┤${END}"
        
        local lote_up=0
        local lote_down=0
        
        for ((j=i; j<fin; j++)); do
            if [[ -f "$TEMP_DIR/resultado_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/resultado_$j")
                IFS=',' read -r ip estado mac vendor puertos <<< "$resultado"
                
                local timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
                
                if [[ "$estado" == "0" ]]; then
                    printf "${GREEN}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" \
                        "$ip" "UP" "$mac" "$vendor" "$puertos"
                    ((lote_up++))
                    ((total_up++))
                    resultados_up+=("$ip|$mac|$vendor|$puertos")
                    echo "$ip,UP,$mac,$vendor,$puertos,$timestamp" >> "$archivo_csv"
                else
                    printf "${RED}│ %-15s │ %-8s │ %-17s │ %-12s │ %-28s │${END}\n" \
                        "$ip" "DOWN" "N/A" "N/A" "N/A"
                    ((lote_down++))
                    ((total_down++))
                    hosts_down+=("$ip")
                    echo "$ip,DOWN,N/A,N/A,N/A,$timestamp" >> "$archivo_csv"
                fi
            fi
        done
        
        echo -e "${CYAN}└─────────────────┴──────────┴───────────────────┴──────────────┴──────────────────────────────┘${END}"
        echo ""
        mostrar_progreso $fin $total
        echo -e "\n${BLUE}Lote: UP=$lote_up DOWN=$lote_down | Total acumulado: UP=$total_up DOWN=$total_down${END}"
        sleep 2
    done
    
    # Limpiar archivos temporales
    rm -f "$TEMP_DIR/resultado_"*
    
    # Guardar resumen en archivo de texto
    {
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "           ESCANEO COMPLETO (Capas 2,3,7) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "RESUMEN:"
        echo "  Total escaneado: $total"
        echo "  Hosts UP:        $total_up"
        echo "  Hosts DOWN:      $total_down"
        echo ""
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "HOSTS ACTIVOS (UP) - DETALLE:"
        echo "════════════════════════════════════════════════════════════════════════════════"
        printf "%-17s %-19s %-14s %s\n" "IP" "MAC" "FABRICANTE" "PUERTOS"
        echo "--------------------------------------------------------------------------------"
        for entry in "${resultados_up[@]}"; do
            IFS='|' read -r ip mac vendor puertos <<< "$entry"
            printf "%-17s %-19s %-14s %s\n" "$ip" "$mac" "$vendor" "$puertos"
        done
        echo ""
        echo "════════════════════════════════════════════════════════════════════════════════"
        echo "HOSTS INACTIVOS (DOWN):"
        echo "════════════════════════════════════════════════════════════════════════════════"
        for ip in "${hosts_down[@]}"; do
            echo "  $ip"
        done
    } > "$archivo_txt"
    
    # Mostrar resumen completo
    mostrar_resumen_completo "$total" "$total_up" "$total_down" "$archivo_csv" "$archivo_txt" resultados_up hosts_down
}

# Función para mostrar resumen del escaneo completo
function mostrar_resumen_completo {
    local total=$1
    local total_up=$2
    local total_down=$3
    local archivo_csv=$4
    local archivo_txt=$5
    local -n arr_up=$6
    local -n arr_down=$7
    
    limpiar_pantalla
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                          ESCANEO COMPLETO - RESULTADOS                                   ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════════════╝${END}"
    echo ""
    echo -e "${BLUE}Total escaneado: $total${END}"
    echo -e "${GREEN}Hosts UP:        $total_up${END}"
    echo -e "${RED}Hosts DOWN:      $total_down${END}"
    echo ""
    
    # Mostrar tabla de hosts UP
    if [[ ${#arr_up[@]} -gt 0 ]]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════════════╗${END}"
        echo -e "${GREEN}║  HOSTS ACTIVOS (UP): ${#arr_up[@]}                                                                    ║${END}"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════════════════╣${END}"
        echo -e "${GREEN}║${END} $(printf '%-17s' 'IP') $(printf '%-19s' 'MAC') $(printf '%-14s' 'FABRICANTE') $(printf '%-20s' 'PUERTOS') ${GREEN}║${END}"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════════════════╣${END}"
        
        for entry in "${arr_up[@]}"; do
            IFS='|' read -r ip mac vendor puertos <<< "$entry"
            echo -e "${GREEN}║${END} $(printf '%-17s' "$ip") $(printf '%-19s' "$mac") $(printf '%-14s' "$vendor") $(printf '%-20s' "$puertos") ${GREEN}║${END}"
        done
        
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════════════╝${END}"
    fi
    
    echo ""
    
    # Preguntar si mostrar hosts DOWN
    if [[ ${#arr_down[@]} -gt 0 ]]; then
        read -p "¿Mostrar hosts DOWN? [s/N]: " mostrar_down
        if [[ "${mostrar_down^^}" == "S" ]]; then
            echo ""
            echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${END}"
            echo -e "${RED}║  HOSTS INACTIVOS (DOWN): ${#arr_down[@]}                                            ║${END}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════════╣${END}"
            
            local col=0
            printf "${RED}║${END} "
            for ip in "${arr_down[@]}"; do
                printf "%-17s" "$ip"
                ((col++))
                if [[ $col -eq 4 ]]; then
                    printf " ${RED}║${END}\n${RED}║${END} "
                    col=0
                fi
            done
            [[ $col -ne 0 ]] && printf "%*s ${RED}║${END}\n" $((17 * (4 - col))) ""
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${END}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Archivos guardados:${END}"
    echo -e "  ${BLUE}CSV:${END} $archivo_csv"
    echo -e "  ${BLUE}TXT:${END} $archivo_txt"
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
    
    # Arrays para guardar resultados
    declare -a hosts_up=()
    declare -a hosts_down=()
    
    # Archivo de resultados
    local archivo_resultado="scan_rapido_$(date +%Y%m%d_%H%M%S).txt"
    
    # Limpiar caché y archivos
    PING_CACHE=()
    rm -f "$TEMP_DIR/ping_"* "$TEMP_DIR/ping_estado_"*
    
    for ((i=0; i<total; i+=BATCH_SIZE_QUICK)); do
        local fin=$((i + BATCH_SIZE_QUICK))
        [[ $fin -gt $total ]] && fin=$total
        
        # Lanzar pings en paralelo
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
                echo "$?" > "$TEMP_DIR/ping_$j"
            ) &
        done
        
        # Esperar a que terminen todos los del lote
        wait
        
        # Contar y mostrar resultados del lote
        local lote_up=0
        local lote_down=0
        
        limpiar_pantalla
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo -e "${CYAN}           ESCANEO RÁPIDO - Lote $((i/BATCH_SIZE_QUICK + 1)) de $(( (total + BATCH_SIZE_QUICK - 1) / BATCH_SIZE_QUICK ))${END}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${END}"
        echo ""
        
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            if [[ -f "$TEMP_DIR/ping_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/ping_$j")
                if [[ "$resultado" == "0" ]]; then
                    echo -e "${GREEN}✓ $ip - UP${END}"
                    ((lote_up++))
                    ((total_up++))
                    hosts_up+=("$ip")
                else
                    echo -e "${RED}✗ $ip - DOWN${END}"
                    ((lote_down++))
                    ((total_down++))
                    hosts_down+=("$ip")
                fi
            fi
        done
        
        echo ""
        mostrar_progreso $fin $total
        echo -e "\n${BLUE}Lote: UP=$lote_up DOWN=$lote_down | Total acumulado: UP=$total_up DOWN=$total_down${END}"
        sleep 1
    done
    
    # Limpiar archivos temporales del escaneo
    rm -f "$TEMP_DIR/ping_"*
    
    # Guardar resultados en archivo
    {
        echo "════════════════════════════════════════════════════════════════════"
        echo "           ESCANEO RÁPIDO (ICMP) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════════"
        echo ""
        echo "RESUMEN:"
        echo "  Total escaneado: $total"
        echo "  Hosts UP:        $total_up"
        echo "  Hosts DOWN:      $total_down"
        echo ""
        echo "════════════════════════════════════════════════════════════════════"
        echo "HOSTS ACTIVOS (UP):"
        echo "════════════════════════════════════════════════════════════════════"
        for ip in "${hosts_up[@]}"; do
            echo "  $ip"
        done
        echo ""
        echo "════════════════════════════════════════════════════════════════════"
        echo "HOSTS INACTIVOS (DOWN):"
        echo "════════════════════════════════════════════════════════════════════"
        for ip in "${hosts_down[@]}"; do
            echo "  $ip"
        done
    } > "$archivo_resultado"
    
    # Mostrar resumen completo
    mostrar_resumen_rapido "$total" "$total_up" "$total_down" "$archivo_resultado" hosts_up hosts_down
}

# Función para mostrar resumen del escaneo rápido
function mostrar_resumen_rapido {
    local total=$1
    local total_up=$2
    local total_down=$3
    local archivo=$4
    local -n arr_up=$5
    local -n arr_down=$6
    
    limpiar_pantalla
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${END}"
    echo -e "${CYAN}║                    ESCANEO RÁPIDO COMPLETADO                                 ║${END}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${END}"
    echo ""
    echo -e "${BLUE}Total escaneado: $total${END}"
    echo -e "${GREEN}Hosts UP:        $total_up${END}"
    echo -e "${RED}Hosts DOWN:      $total_down${END}"
    echo ""
    
    # Mostrar hosts UP
    if [[ ${#arr_up[@]} -gt 0 ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${END}"
        echo -e "${GREEN}║  HOSTS ACTIVOS (UP): ${#arr_up[@]}                                                   ║${END}"
        echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════════════╣${END}"
        
        local col=0
        printf "${GREEN}║${END} "
        for ip in "${arr_up[@]}"; do
            printf "%-17s" "$ip"
            ((col++))
            if [[ $col -eq 4 ]]; then
                printf " ${GREEN}║${END}\n${GREEN}║${END} "
                col=0
            fi
        done
        [[ $col -ne 0 ]] && printf "%*s ${GREEN}║${END}\n" $((17 * (4 - col))) ""
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${END}"
    fi
    
    echo ""
    
    # Preguntar si mostrar hosts DOWN
    if [[ ${#arr_down[@]} -gt 0 ]]; then
        read -p "¿Mostrar hosts DOWN? [s/N]: " mostrar_down
        if [[ "${mostrar_down^^}" == "S" ]]; then
            echo ""
            echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${END}"
            echo -e "${RED}║  HOSTS INACTIVOS (DOWN): ${#arr_down[@]}                                            ║${END}"
            echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════════╣${END}"
            
            local col=0
            printf "${RED}║${END} "
            for ip in "${arr_down[@]}"; do
                printf "%-17s" "$ip"
                ((col++))
                if [[ $col -eq 4 ]]; then
                    printf " ${RED}║${END}\n${RED}║${END} "
                    col=0
                fi
            done
            [[ $col -ne 0 ]] && printf "%*s ${RED}║${END}\n" $((17 * (4 - col))) ""
            echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${END}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Resultados guardados en: $archivo${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Mostrar solo hosts UP o DOWN
function mostrar_hosts {
    local tipo=$1
    
    verificar_ips_cargadas || return
    
    limpiar_pantalla
    
    local titulo=""
    local color=""
    local simbolo=""
    
    if [[ "$tipo" == "up" ]]; then
        titulo="HOSTS ACTIVOS (UP)"
        color="${GREEN}"
        simbolo="✓"
    else
        titulo="HOSTS INACTIVOS (DOWN)"
        color="${RED}"
        simbolo="✗"
    fi
    
    echo -e "${color}═══════════════════════════════════════════${END}"
    echo -e "${color}           $titulo              ${END}"
    echo -e "${color}═══════════════════════════════════════════${END}"
    echo ""
    
    local total=${#IP_LIST[@]}
    local encontrados=0
    declare -a resultados=()
    
    # Archivo de resultados
    local archivo_resultado="hosts_${tipo}_$(date +%Y%m%d_%H%M%S).txt"
    
    # Limpiar caché para escaneo fresco
    PING_CACHE=()
    rm -f "$TEMP_DIR/host_"*
    
    echo -e "${YELLOW}Escaneando ${total} hosts...${END}"
    echo ""
    
    # Usar procesamiento paralelo por lotes
    local batch_size=30
    
    for ((i=0; i<total; i+=batch_size)); do
        local fin=$((i + batch_size))
        [[ $fin -gt $total ]] && fin=$total
        
        # Lanzar pings en paralelo
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            (
                ping -c 1 -W 1 -s 8 -q "$ip" > /dev/null 2>&1
                echo "$?" > "$TEMP_DIR/host_$j"
            ) &
        done
        
        wait
        
        # Procesar resultados del lote
        for ((j=i; j<fin; j++)); do
            local ip="${IP_LIST[$j]}"
            if [[ -f "$TEMP_DIR/host_$j" ]]; then
                local resultado=$(cat "$TEMP_DIR/host_$j")
                
                if [[ "$tipo" == "up" && "$resultado" == "0" ]]; then
                    echo -e "${color}$simbolo $ip${END}"
                    resultados+=("$ip")
                    ((encontrados++))
                elif [[ "$tipo" == "down" && "$resultado" != "0" ]]; then
                    echo -e "${color}$simbolo $ip${END}"
                    resultados+=("$ip")
                    ((encontrados++))
                fi
            fi
        done
        
        mostrar_progreso $fin $total
    done
    
    # Limpiar temporales
    rm -f "$TEMP_DIR/host_"*
    
    # Guardar resultados
    {
        echo "════════════════════════════════════════════════════════════════════"
        echo "           $titulo - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════════"
        echo ""
        echo "Total escaneado: $total"
        echo "Encontrados:     $encontrados"
        echo ""
        echo "Lista de IPs:"
        echo "────────────────────────────────────────────────────────────────────"
        for ip in "${resultados[@]}"; do
            echo "$ip"
        done
    } > "$archivo_resultado"
    
    echo -e "\n"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${END}"
    echo -e "${BLUE}Total encontrados: $encontrados de $total${END}"
    echo -e "${YELLOW}Resultados guardados en: $archivo_resultado${END}"
    echo ""
    read -p "Presiona Enter para continuar..."
}

# Menú principal
function menu_principal {
    while true; do
        limpiar_pantalla
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${END}"
        echo -e "${CYAN}║         Network Scanner v5.0 - Multi-Red                     ║${END}"
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
        
        echo -e "${MAGENTA}─── CONFIGURACIÓN ───${END}"
        echo -e "${YELLOW}1)${END} Seleccionar Red / Rango de IPs"
        echo ""
        echo -e "${MAGENTA}─── ESCANEOS ───${END}"
        echo -e "${YELLOW}2)${END} Escaneo Rápido (Solo Ping)"
        echo -e "${YELLOW}3)${END} Escaneo Completo (Capas 2,3,7)"
        echo -e "${YELLOW}4)${END} Ver Solo Hosts UP"
        echo -e "${YELLOW}5)${END} Ver Solo Hosts DOWN"
        echo ""
        echo -e "${MAGENTA}─── HERRAMIENTAS ───${END}"
        echo -e "${YELLOW}6)${END} Buscar IPs Libres"
        echo ""
        echo -e "${YELLOW}0)${END} Salir"
        echo ""
        read -p "Seleccione una opción [0-6]: " opcion
        
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
            6) buscar_ips_libres ;;
            0) echo -e "${GREEN}Saliendo...${END}"; exit 0 ;;
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
