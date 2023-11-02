#!/bin/bash

# Definición de colores
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

# Función para resaltar palabras en rojo
highlight_red() {
    sed -E "s/($1)/${RED}\1${NC}/g"
}

# Función para resaltar palabras en amarillo
highlight_yellow() {
    sed -E "s/($1)/${YELLOW}\1${NC}/g"
}

# Función para resaltar palabras en verde
highlight_green() {
    sed -E "s/($1)/${GREEN}\1${NC}/g"
}

# Palabras clave para resaltar
RED_KEYWORDS="CRITIC|critic|ERROR|ERR|error|FATAL|fatal|PANIC|panic|FAIL|fail|EXCEPTION|exception|ABORT|abort|CRASH|crash|SEVERE|severe|ALERT|alert|EMERGENCY|emergency|TIMEOUT|timeout|BROKEN|broken|UNREACHABLE|unreachable|DOWN|down"
YELLOW_KEYWORDS="WARNING|warning|WARN|warn|NOTICE|notice|DEPRECATED|deprecated|RETRY|retry|TIMEOUT|timeout|DELAY|delay|PENDING|pending"
GREEN_KEYWORDS="info|INFO|SUCCESS|success|OK|ok|PASSED|passed|UP|up|ONLINE|online|ENABLED|enabled|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})"

# Aplicar resaltado
cat $1 | highlight_red "$RED_KEYWORDS" | highlight_yellow "$YELLOW_KEYWORDS" | highlight_green "$GREEN_KEYWORDS"
