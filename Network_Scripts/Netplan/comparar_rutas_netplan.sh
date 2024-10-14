#!/bin/bash

# Archivo de configuración de Netplan
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# Verificar si el archivo de Netplan existe
if [ ! -f "$NETPLAN_FILE" ]; then
    echo "Error: El archivo de Netplan $NETPLAN_FILE no existe."
    exit 1
fi

# Archivos temporales para almacenar las listas de rutas
SYSTEM_ROUTES=$(mktemp)
NETPLAN_ROUTES=$(mktemp)

# Asegurar la eliminación de archivos temporales al salir del script
trap "rm -f $SYSTEM_ROUTES $NETPLAN_ROUTES" EXIT

# Paso 1: Extraer rutas del sistema usando 'ip route' que tienen 'via'
# Formato: "destino via gateway"
ip route | grep " via " | awk '{print $1 " via " $3}' | sort | uniq > "$SYSTEM_ROUTES"

# Paso 2: Extraer rutas definidas en Netplan
# Usamos awk para parsear el YAML sin /32
awk '
    function trim(str) {
        sub(/^[ \t]+/, "", str);
        sub(/[ \t]+$/, "", str);
        return str;
    }

    BEGIN {
        in_routes = 0;
        route_to = "";
        route_via = "";
    }

    # Buscar líneas que contienen "routes:"
    /^\s*routes:/ {
        in_routes = 1;
        route_indent = match($0, /[^ ]/); # Indentación de la línea "routes:"
        next;
    }

    in_routes == 1 {
        if (match($0, /^\s*- to:\s*(.*)/, m)) {
            route_to = trim(m[1]);
            sub(/\/32$/, "", route_to);
            next;
        }
        if (match($0, /^\s*via:\s*(.*)/, m)) {
            route_via = trim(m[1]);
            print route_to " via " route_via;
        }
    }
' "$NETPLAN_FILE" | sort | uniq > "$NETPLAN_ROUTES"

# Paso 3: Comparar listas de rutas y eliminar líneas en blanco
missing_routes=$(comm -23 "$SYSTEM_ROUTES" "$NETPLAN_ROUTES" | grep -v '^$')

# Paso 4: Contar las rutas
system_count=$(wc -l < "$SYSTEM_ROUTES")
netplan_count=$(wc -l < "$NETPLAN_ROUTES")
missing_count=$(echo "$missing_routes" | grep -c '^[^ ]')

# Paso 5: Mostrar los resultados
if [ "$missing_count" -eq 0 ]; then
    echo "Todas las rutas actuales están definidas en $NETPLAN_FILE."
else
    echo "Rutas faltantes en $NETPLAN_FILE:"
    echo "$missing_routes" | while read -r route; do
        [ -n "$route" ] && echo " - $route"
    done
fi

# Resumen
echo ""
echo "Total rutas en ip route con 'via': $system_count"
echo "Total rutas en Netplan: $netplan_count"
echo "Rutas faltantes: $missing_count"
