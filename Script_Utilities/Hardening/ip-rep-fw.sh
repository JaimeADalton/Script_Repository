#!/usr/bin/env bash
# ip-rep-fw.sh — Firewall por reputación con categorías (OSS/gratis)
# Requiere: bash 4+, ipset, iptables/ip6tables, curl, awk, grep, sed
#set -euo pipefail

# ------------------ CONFIGURACIÓN ------------------
TTL_DAYS="${TTL_DAYS:-7}"
TTL=$((TTL_DAYS*24*3600))
LOCKFILE="${LOCKFILE:-/var/run/ip-rep-fw.lock}"
ACTION="${ACTION:-DROP}"  # DROP o REJECT
CATEGORIES="${CATEGORIES:-bulletproof,botnet_c2,scanners,anonymity,aggregate,malware_misc,threatfox}"
CONF_FILE="${CONF_FILE:-/etc/ip-rep/fw.conf}"
CURL_OPTS=(--fail --silent --show-error --location --max-time 60 --retry 3)

# Configuración de logging
LOG_LEVEL="${LOG_LEVEL:-INFO}"     # DEBUG, INFO, WARN, ERROR
LOG_FILE="${LOG_FILE:-/var/log/ip-rep-fw.log}"
SYSLOG="${SYSLOG:-true}"           # Enviar también a syslog
METRICS_FILE="${METRICS_FILE:-/var/lib/ip-rep/metrics.json}"
STATS_FILE="${STATS_FILE:-/var/lib/ip-rep/stats.log}"

# Fuentes OSS / gratuitas
FEEDS=(
  "spamhaus_drop|bulletproof|https://www.spamhaus.org/drop/drop.txt|cidr"
  "spamhaus_edrop|bulletproof|https://www.spamhaus.org/drop/edrop.txt|cidr"
  "feodo_ip|botnet_c2|https://feodotracker.abuse.ch/downloads/ipblocklist.txt|ip"
  "sslbl_ip|botnet_c2|https://sslbl.abuse.ch/blacklist/sslipblacklist.txt|ip"
  "dshield_block|scanners|https://www.dshield.org/block.txt|dshield24"
  "blocklist_de|scanners|https://www.blocklist.de/downloads/export-ips_all.txt|ip"
  "greensnow|scanners|https://www.blocklist.greensnow.co/greensnow.txt|ip"
  "blocklist_net_ua|scanners|https://blocklist.net.ua/blocklist.csv|ipcsv"
  "tor_exit|anonymity|https://check.torproject.org/api/bulk|tor-bulk"
  "firehol_level1|aggregate|https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset|cidr"
  "ipsum_10|aggregate|https://raw.githubusercontent.com/stamparm/ipsum/master/levels/10.txt|ip"
  "et_compromised|malware_misc|https://rules.emergingthreats.net/blockrules/compromised-ips.txt|ip"
  "threatfox_csv|threatfox|https://threatfox.abuse.ch/export/csv/recent/|threatfox-csv"
)
FEEDS6=(
  "spamhaus_dropv6|bulletproof|https://www.spamhaus.org/drop/dropv6.txt|cidr6"
)

# Parámetros opcionales
FEEDS_ONLY="${FEEDS_ONLY:-}"   # claves específicas
FEEDS_EXTRA="${FEEDS_EXTRA:-}" # claves adicionales
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# ------------------ FUNCIONES DE LOGGING ------------------
readonly SCRIPT_START_TIME=$(date +%s)
readonly SCRIPT_PID=$$
readonly SCRIPT_NAME="ip-rep-fw"

# Colores para terminal (solo si stdout es un terminal)
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[0;33m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly YELLOW=''
    readonly GREEN=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly NC=''
fi

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')
    local color=""
    
    case "$level" in
        DEBUG) color="$PURPLE" ;;
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
    esac
    
    local log_line="[$timestamp] [$level] [PID:$SCRIPT_PID] $message"
    
    # Filtrar por LOG_LEVEL
    case "$LOG_LEVEL" in
        DEBUG) ;; # Mostrar todo
        INFO)  [[ "$level" == "DEBUG" ]] && return ;;
        WARN)  [[ "$level" == "DEBUG" || "$level" == "INFO" ]] && return ;;
        ERROR) [[ "$level" != "ERROR" ]] && return ;;
    esac
    
    # A archivo
    echo "$log_line" >> "$LOG_FILE"
    
    # A syslog
    [[ "$SYSLOG" == "true" ]] && logger -t "$SCRIPT_NAME" -p daemon.info "$level: $message"
    
    # A terminal con colores
    echo -e "${color}$log_line${NC}"
}

log_debug() { log_message "DEBUG" "$1"; }
log_info()  { log_message "INFO" "$1"; }
log_warn()  { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

log_metrics() {
    local category="$1"
    local metric="$2"
    local value="$3"
    local timestamp=$(date +%s)
    
    # JSON estructurado para métricas
    local metric_json="{\"timestamp\":$timestamp,\"category\":\"$category\",\"metric\":\"$metric\",\"value\":$value,\"ttl_days\":$TTL_DAYS}"
    echo "$metric_json" >> "$METRICS_FILE"
    log_debug "Metric recorded: $category.$metric = $value"
}

log_performance() {
    local operation="$1"
    local start_time="$2"
    local end_time="${3:-$(date +%s)}"
    local duration=$((end_time - start_time))
    
    log_info "Performance: $operation completed in ${duration}s"
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $operation ${duration}s" >> "$STATS_FILE"
}

# ------------------ FUNCIONES PRINCIPALES ------------------
req() { 
    local url="$1"
    local start_time=$(date +%s)
    log_debug "HTTP request starting: $url"
    
    if curl "${CURL_OPTS[@]}" "$url"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_debug "HTTP request successful: $url (${duration}s)"
        return 0
    else
        local exit_code=$?
        log_error "HTTP request failed: $url (exit code: $exit_code)"
        return $exit_code
    fi
}

emit_v4(){ 
    log_debug "Extracting IPv4 addresses/CIDRs from input"
    local count=$(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' | awk -F/ '{print $1 (NF==2?"/"$2:"/32")}' | tee >(wc -l >&2) | cat)
    log_debug "Extracted IPv4 entries: $(echo "$count" | wc -l)"
    echo "$count"
}

emit_v6(){ 
    log_debug "Extracting IPv6 addresses/CIDRs from input"
    local count=$(grep -Eio '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(/[0-9]{1,3})?' | awk -F/ '{print tolower($1) (NF==2?"/"$2:"/128")}' | tee >(wc -l >&2) | cat)
    log_debug "Extracted IPv6 entries: $(echo "$count" | wc -l)"
    echo "$count"
}

parse_feed(){
    local key="$1" url="$2" parser="$3"
    local start_time=$(date +%s)
    
    log_info "Processing feed: $key ($parser) from $url"
    
    local result=""
    local entries_count=0
    
    case "$parser" in
        cidr)
            log_debug "Using CIDR parser for $key"
            result=$(req "$url" | grep -vE '^\s*;|^\s*$' | emit_v4)
            entries_count=$(echo "$result" | wc -l)
            ;;
        cidr6)
            log_debug "Using CIDR6 parser for $key"
            result=$(req "$url" | grep -vE '^\s*;|^\s*$' | emit_v6)
            entries_count=$(echo "$result" | wc -l)
            ;;
        ip)
            log_debug "Using IP parser for $key"
            result=$(req "$url" | grep -E '^[0-9]+\.' | awk '{print $1"/32"}')
            entries_count=$(echo "$result" | wc -l)
            ;;
        dshield24)
            log_debug "Using DShield24 parser for $key"
            result=$(req "$url" | awk '/^[0-9]/{print $1"/24"}')
            entries_count=$(echo "$result" | wc -l)
            ;;
        ipcsv)
            log_debug "Using IP CSV parser for $key"
            result=$(req "$url" | grep -E '^[0-9]+\.' | awk -F, '{print $1"/32"}')
            entries_count=$(echo "$result" | wc -l)
            ;;
        tor-bulk)
            log_debug "Using Tor bulk parser for $key"
            result=$(req "$url" | grep -E '^[0-9]+\.' | awk '{print $1"/32"}')
            entries_count=$(echo "$result" | wc -l)
            ;;
        threatfox-csv)
            log_debug "Using ThreatFox CSV parser for $key"
            result=$(req "$url" | awk -F',' 'tolower($3) ~ /^ip(:port)?$/ {split($2,a,":"); if(a[1]~/^[0-9.]+$/) print a[1]"/32"}')
            entries_count=$(echo "$result" | wc -l)
            ;;
        *)
            log_error "Unknown parser: $parser for feed $key"
            return 1
            ;;
    esac
    
    log_performance "parse_feed_$key" "$start_time"
    log_metrics "$key" "entries_downloaded" "$entries_count"
    
    if [[ $entries_count -eq 0 ]]; then
        log_warn "Feed $key returned 0 entries - possible issue with source"
    elif [[ $entries_count -lt 10 ]]; then
        log_warn "Feed $key returned only $entries_count entries - unusually low"
    else
        log_info "Feed $key processed successfully: $entries_count entries"
    fi
    
    echo "$result"
}

build_set(){
    local fam="${1:-}" cat="${2:-}"
    local start_time=$(date +%s)
    
    [[ -z "$fam" || -z "$cat" ]] && { 
        log_error "build_set requiere familia y categoría"
        return 1
    }

    log_info "Building ipset for family=$fam category=$cat"
    
    local set_live="drop_${fam}_${cat}"
    local set_new="${set_live}_new"
    local tmp; tmp="$(mktemp)" || {
        log_error "Failed to create temp file for $fam/$cat"
        return 1
    }
    
    trap 'rm -f "$tmp"; log_debug "Cleaned up temp file: $tmp"' RETURN
    log_debug "Created temp file: $tmp"

    local -a catalog=("${FEEDS[@]}")
    [[ "$fam" == "v6" ]] && catalog=("${FEEDS6[@]}")
    
    log_debug "Processing ${#catalog[@]} potential feeds for $fam/$cat"
    
    local feeds_processed=0
    local total_entries=0
    
    for def in "${catalog[@]}"; do
        IFS='|' read -r key c url parser <<<"$def"
        [[ "$c" != "$cat" ]] && {
            log_debug "Skipping feed $key: category mismatch ($c != $cat)"
            continue
        }
        [[ -n "${FEEDS_ONLY:-}" && ",${FEEDS_ONLY}," != *",${key},"* ]] && {
            log_debug "Skipping feed $key: not in FEEDS_ONLY list"
            continue
        }
        
        log_info "Processing feed $key for category $cat"
        feeds_processed=$((feeds_processed + 1))
        
        if parse_feed "$key" "$url" "$parser" >> "$tmp"; then
            log_info "Successfully processed feed: $key"
        else
            log_error "Failed to process feed: $key"
        fi
    done
    
    # Procesar y eliminar duplicados
    log_debug "Removing duplicates and sorting entries"
    local before_dedup=$(wc -l < "$tmp")
    sort -u "$tmp" -o "$tmp"
    local after_dedup=$(wc -l < "$tmp")
    local duplicates_removed=$((before_dedup - after_dedup))
    
    log_info "Deduplication: $before_dedup -> $after_dedup entries ($duplicates_removed duplicates removed)"
    log_metrics "$cat" "feeds_processed" "$feeds_processed"
    log_metrics "$cat" "entries_before_dedup" "$before_dedup"
    log_metrics "$cat" "entries_after_dedup" "$after_dedup"
    log_metrics "$cat" "duplicates_removed" "$duplicates_removed"

    # Crear nuevo ipset
    log_info "Creating new ipset: $set_new"
    ipset destroy "$set_new" 2>/dev/null || true
    
    if [[ "$fam" == "v4" ]]; then
        log_debug "Creating IPv4 ipset with TTL=${TTL}s"
        ipset create "$set_new" hash:net family inet timeout "$TTL" || {
            log_error "Failed to create IPv4 ipset: $set_new"
            return 1
        }
    else
        log_debug "Creating IPv6 ipset with TTL=${TTL}s"
        ipset create "$set_new" hash:net family inet6 timeout "$TTL" || {
            log_error "Failed to create IPv6 ipset: $set_new"
            return 1
        }
    fi

    # Poblar ipset
    log_info "Populating ipset $set_new with $after_dedup entries"
    local added_count=0
    local failed_count=0
    
    while read -r cidr; do
        if [[ -n "$cidr" ]]; then
            if ipset add "$set_new" "$cidr" -exist timeout "$TTL" 2>/dev/null; then
                added_count=$((added_count + 1))
                [[ $((added_count % 1000)) -eq 0 ]] && log_debug "Added $added_count entries to $set_new"
            else
                failed_count=$((failed_count + 1))
                log_debug "Failed to add entry to ipset: $cidr"
            fi
        fi
    done < "$tmp"
    
    log_info "Ipset population completed: $added_count added, $failed_count failed"
    log_metrics "$cat" "entries_added" "$added_count"
    log_metrics "$cat" "entries_failed" "$failed_count"

    # Crear set live si no existe
    if ! ipset list "$set_live" &>/dev/null; then
        log_info "Creating live ipset: $set_live"
        if [[ "$fam" == "v4" ]]; then
            ipset create "$set_live" hash:net family inet timeout "$TTL" || {
                log_error "Failed to create live IPv4 ipset: $set_live"
                return 1
            }
        else
            ipset create "$set_live" hash:net family inet6 timeout "$TTL" || {
                log_error "Failed to create live IPv6 ipset: $set_live"
                return 1
            }
        fi
    else
        log_debug "Live ipset already exists: $set_live"
    fi

    # Atomic swap
    log_info "Performing atomic swap: $set_live <-> $set_new"
    if ipset swap "$set_live" "$set_new"; then
        log_info "Atomic swap completed successfully"
        ipset destroy "$set_new" || log_warn "Failed to destroy temp set: $set_new"
    else
        log_error "Atomic swap failed for $set_live"
        return 1
    fi
    
    log_performance "build_set_${fam}_${cat}" "$start_time"
    log_info "Successfully built set for family=$fam category=$cat ($added_count entries)"
}

ensure_rules(){
    local fam="${1:-}" cat="${2:-}"
    [[ -z "$fam" || -z "$cat" ]] && {
        log_error "ensure_rules requires family and category"
        return 1
    }
    
    log_info "Ensuring iptables rules for family=$fam category=$cat"
    
    local proto chain
    if [[ "$fam" == "v4" ]]; then 
        proto="iptables"
        chain="IPREP_${cat^^}_IN"
    else 
        proto="ip6tables"
        chain="IPREP_${cat^^}_IN6"
    fi
    
    log_debug "Using protocol=$proto chain=$chain"

    # Crear cadena si no existe
    if $proto -nL "$chain" &>/dev/null; then
        log_debug "Chain $chain already exists"
    else
        log_info "Creating iptables chain: $chain"
        if $proto -N "$chain"; then
            log_info "Successfully created chain: $chain"
        else
            log_error "Failed to create chain: $chain"
            return 1
        fi
    fi
    
    # Crear regla en la cadena
    if $proto -C "$chain" -m set --match-set "drop_${fam}_${cat}" src -j "$ACTION" 2>/dev/null; then
        log_debug "Rule already exists in chain $chain"
    else
        log_info "Adding rule to chain $chain: DROP from set drop_${fam}_${cat}"
        if $proto -A "$chain" -m set --match-set "drop_${fam}_${cat}" src -j "$ACTION"; then
            log_info "Successfully added rule to chain: $chain"
        else
            log_error "Failed to add rule to chain: $chain"
            return 1
        fi
    fi
    
    # Agregar salto a INPUT
    if $proto -C INPUT -j "$chain" 2>/dev/null; then
        log_debug "Jump to $chain already exists in INPUT"
    else
        log_info "Adding jump from INPUT to $chain"
        if $proto -I INPUT -j "$chain"; then
            log_info "Successfully added INPUT jump to: $chain"
        else
            log_error "Failed to add INPUT jump to: $chain"
        fi
    fi
    
    # Agregar salto a FORWARD
    if $proto -C FORWARD -j "$chain" 2>/dev/null; then
        log_debug "Jump to $chain already exists in FORWARD"
    else
        log_info "Adding jump from FORWARD to $chain"
        if $proto -I FORWARD -j "$chain"; then
            log_info "Successfully added FORWARD jump to: $chain"
        else
            log_error "Failed to add FORWARD jump to: $chain"
        fi
    fi
    
    log_info "Rules ensured for family=$fam category=$cat"
}

ensure_all(){
    log_info "Setting up aggregate ipsets and rules"
    
    for fam in v4 v6; do
        local set_all="drop_${fam}_all"
        log_info "Processing aggregate set: $set_all"
        
        # Crear set agregado si no existe
        if ipset list "$set_all" &>/dev/null; then
            log_debug "Aggregate set already exists: $set_all"
        else
            log_info "Creating aggregate set: $set_all"
            # Crear set agregado sin especificar family (compatibilidad con ipset v7.19)
            ipset create "$set_all" list:set || {
                log_error "Failed to create aggregate set: $set_all"
                continue
            }
        fi
        
        # Limpiar y repoblar
        log_debug "Flushing aggregate set: $set_all"
        ipset flush "$set_all"
        
        IFS=',' read -ra cats <<<"${CATEGORIES:-}"
        local added_sets=0
        
        for c in "${cats[@]}"; do
            if [[ -n "$c" ]]; then
                local category_set="drop_${fam}_${c}"
                log_debug "Adding $category_set to aggregate set $set_all"
                if ipset add "$set_all" "$category_set" -exist; then
                    added_sets=$((added_sets + 1))
                    log_debug "Successfully added $category_set to aggregate"
                else
                    log_warn "Failed to add $category_set to aggregate (set may not exist yet)"
                fi
            fi
        done
        
        log_info "Aggregate set $set_all populated with $added_sets category sets"
        log_metrics "aggregate" "${fam}_sets_added" "$added_sets"
        
        # Crear reglas iptables para el set agregado
        local proto="iptables"
        [[ "$fam" == "v6" ]] && proto="ip6tables"
        
        log_info "Ensuring $proto rules for aggregate set $set_all"
        
        # INPUT rule
        if $proto -C INPUT -m set --match-set "$set_all" src -j "$ACTION" 2>/dev/null; then
            log_debug "$proto INPUT rule already exists for $set_all"
        else
            log_info "Adding $proto INPUT rule for $set_all"
            if $proto -I INPUT -m set --match-set "$set_all" src -j "$ACTION"; then
                log_info "Successfully added $proto INPUT rule for $set_all"
            else
                log_error "Failed to add $proto INPUT rule for $set_all"
            fi
        fi
        
        # FORWARD rule
        if $proto -C FORWARD -m set --match-set "$set_all" src -j "$ACTION" 2>/dev/null; then
            log_debug "$proto FORWARD rule already exists for $set_all"
        else
            log_info "Adding $proto FORWARD rule for $set_all"
            if $proto -I FORWARD -m set --match-set "$set_all" src -j "$ACTION"; then
                log_info "Successfully added $proto FORWARD rule for $set_all"
            else
                log_error "Failed to add $proto FORWARD rule for $set_all"
            fi
        fi
    done
    
    log_info "Aggregate setup completed"
}

generate_final_report() {
    local end_time=$(date +%s)
    local total_runtime=$((end_time - SCRIPT_START_TIME))
    
    log_info "=== FINAL EXECUTION REPORT ==="
    log_info "Script runtime: ${total_runtime}s"
    log_info "TTL configuration: ${TTL_DAYS} days (${TTL}s)"
    log_info "Action: $ACTION"
    log_info "Categories processed: $CATEGORIES"
    
    # Contar entradas en cada set
    for fam in v4 v6; do
        for cat in $(IFS=','; echo ${CATEGORIES}); do
            [[ -z "$cat" ]] && continue
            local set_name="drop_${fam}_${cat}"
            if ipset list "$set_name" &>/dev/null; then
                local count=$(ipset list "$set_name" | grep -c "^[0-9a-f]")
                log_info "Set $set_name: $count entries"
                log_metrics "$cat" "${fam}_final_count" "$count"
            fi
        done
        
        # Contar agregado
        local set_all="drop_${fam}_all"
        if ipset list "$set_all" &>/dev/null; then
            local member_count=$(ipset list "$set_all" | grep -c "^drop_")
            log_info "Aggregate set $set_all: $member_count member sets"
            log_metrics "aggregate" "${fam}_member_sets" "$member_count"
        fi
    done
    
    log_metrics "execution" "total_runtime" "$total_runtime"
    log_info "=== END REPORT ==="
}

# ------------------ MAIN ------------------
log_info "=== IP Reputation Firewall Starting ==="
log_info "PID: $SCRIPT_PID"
log_info "Version: Enhanced with extensive logging"
log_info "Log level: $LOG_LEVEL"
log_info "Log file: $LOG_FILE"
log_info "Metrics file: $METRICS_FILE"

# Crear directorios necesarios
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$METRICS_FILE")" "$(dirname "$STATS_FILE")" 2>/dev/null

# Lock file
log_debug "Acquiring lock: $LOCKFILE"
exec 9>"$LOCKFILE"
if flock -n 9; then
    log_info "Lock acquired successfully"
else
    log_warn "Another process is running, exiting"
    echo "otro proceso en curso"
    exit 0
fi

# Cargar módulos del kernel
log_info "Loading required kernel modules"
if modprobe ip_set_hash_net 2>/dev/null; then
    log_debug "Loaded module: ip_set_hash_net"
else
    log_warn "Failed to load module ip_set_hash_net (may already be loaded)"
fi

if modprobe ip_set_list_set 2>/dev/null; then
    log_debug "Loaded module: ip_set_list_set"
else
    log_warn "Failed to load module ip_set_list_set (may already be loaded)"
fi

# Ajustar categorías si FEEDS_ONLY está definido
if [[ -n "${FEEDS_ONLY:-}" ]]; then
    log_info "FEEDS_ONLY specified: $FEEDS_ONLY"
    log_info "Recalculating categories based on selected feeds"
    
    ORIGINAL_CATEGORIES="$CATEGORIES"
    CATEGORIES=""
    
    for def in "${FEEDS[@]}"; do
        IFS='|' read -r key cat _ _ <<<"$def"
        if [[ ",${FEEDS_ONLY}," == *",${key},"* ]]; then
            log_debug "Feed $key (category: $cat) selected"
            CATEGORIES+="${cat},"
        fi
    done
    
    CATEGORIES="$(echo "$CATEGORIES" | awk -v RS=, '!a[$0]++' OFS=, | sed 's/,$//')"
    log_info "Categories recalculated: $ORIGINAL_CATEGORIES -> $CATEGORIES"
fi

# Procesar cada categoría
log_info "Starting main processing loop"
IFS=',' read -ra cats <<<"${CATEGORIES:-}"
log_info "Will process ${#cats[@]} categories: ${cats[*]}"

for c in "${cats[@]}"; do
    [[ -z "$c" ]] && continue
    
    log_info "=== Processing category: $c ==="
    
    cat_start_time=$(date +%s)
    
    # Build sets
    if build_set "v4" "$c"; then
        log_info "IPv4 set built successfully for category: $c"
    else
        log_error "Failed to build IPv4 set for category: $c"
    fi
    
    if build_set "v6" "$c"; then
        log_info "IPv6 set built successfully for category: $c"
    else
        log_error "Failed to build IPv6 set for category: $c"
    fi
    
    # Ensure rules
    if ensure_rules "v4" "$c"; then
        log_info "IPv4 rules ensured for category: $c"
    else
        log_error "Failed to ensure IPv4 rules for category: $c"
    fi
    
    if ensure_rules "v6" "$c"; then
        log_info "IPv6 rules ensured for category: $c"
    else
        log_error "Failed to ensure IPv6 rules for category: $c"
    fi
    
    log_performance "category_$c" "$cat_start_time"
    log_info "=== Completed category: $c ==="
done

# Setup aggregate rules
log_info "Setting up aggregate rules and sets"
if ensure_all; then
    log_info "Aggregate setup completed successfully"
else
    log_error "Aggregate setup failed"
fi

# Generate final report
generate_final_report

# Final success message
final_timestamp=$(date -u +'%FT%TZ')
log_info "=== IP Reputation Firewall Completed Successfully ==="
echo "ok $final_timestamp ttl_days=$TTL_DAYS cats=${CATEGORIES}"
