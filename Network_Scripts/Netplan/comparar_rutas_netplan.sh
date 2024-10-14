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
# Usaremos un parsing más robusto del archivo YAML

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

    # Si estamos dentro de "routes:"
    in_routes == 1 {
        # Línea que inicia una nueva ruta "- to:"
        if (match($0, /^\s*- to:\s*(.*)/, m)) {
            current_indent = match($0, /[^ ]/);
            if (current_indent <= route_indent) {
                in_routes = 0; # Salimos de la sección de rutas
                next;
            }
            route_to = trim(m[1]);
            route_via = "";
        }
        # Línea que contiene "via:"
        else if (match($0, /^\s*via:\s*(.*)/, m)) {
            route_via = trim(m[1]);
            if (route_to != "") {
                # Eliminar notación /32 si existe
                sub(/\/32$/, "", route_to);
                print route_to " via " route_via;
                route_to = "";
                route_via = "";
            }
        }
        # Si encontramos una nueva sección o una disminución en la indentación, salimos de "routes:"
        else if (match($0, /^[^ ]/, m) && match($0, /[^ ]/)) {
            in_routes = 0;
        }
    }
' "$NETPLAN_FILE" | sort | uniq > "$NETPLAN_ROUTES"

# Paso 3: Mostrar las rutas extraídas para depuración
echo "Rutas extraídas del sistema (ip route):"
cat "$SYSTEM_ROUTES"
echo ""
echo "Rutas extraídas de Netplan (sin /32):"
cat "$NETPLAN_ROUTES"
echo ""

# Paso 4: Comparar las listas de rutas
# Encontrar rutas que están en el sistema pero no en Netplan
missing_routes=$(comm -23 "$SYSTEM_ROUTES" "$NETPLAN_ROUTES")

# Contar las rutas
system_count=$(wc -l < "$SYSTEM_ROUTES")
netplan_count=$(wc -l < "$NETPLAN_ROUTES")
echo "$missing_routes"
missing_count=$(echo "$missing_routes" | grep -c '^')

# Paso 5: Mostrar los resultados
if [ "$missing_count" -eq 0 ]; then
    echo "Todas las rutas actuales están definidas en $NETPLAN_FILE."
else
    echo "Rutas faltantes en $NETPLAN_FILE:"
    # Solo imprimir rutas si hay rutas faltantes
    if [ -n "$missing_routes" ]; then
        echo "$missing_routes" | while read -r route; do
            [ -n "$route" ] && echo " - $route"
        done
    fi
fi

# Resumen
echo ""
echo "Total rutas en ip route con 'via': $system_count"
echo "Total rutas en Netplan: $netplan_count"
echo "Rutas faltantes: $((missing_count))"
