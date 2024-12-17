#!/usr/bin/env python3
import subprocess
import sys
import yaml
import re

NETPLAN_FILE = "/etc/netplan/00-installer-config.yaml"

# Verificar si el archivo existe
try:
    with open(NETPLAN_FILE, "r") as f:
        netplan_data = yaml.safe_load(f)
except FileNotFoundError:
    print(f"Error: El archivo de Netplan {NETPLAN_FILE} no existe.")
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"Error al parsear el archivo YAML {NETPLAN_FILE}: {e}")
    sys.exit(1)

# Obtener rutas del sistema usando ip route
# Salida esperada: líneas tipo "10.0.0.0/24 via 10.0.0.1 dev eth0"
try:
    ip_output = subprocess.check_output(["ip", "route"], text=True)
except subprocess.CalledProcessError as e:
    print("Error al ejecutar 'ip route':", e)
    sys.exit(1)

# Extraer solo las rutas con 'via', formato: destino via gateway
system_routes = set()
for line in ip_output.splitlines():
    # Ejemplo de línea: "10.0.0.0/24 via 10.0.0.1 dev eth0 proto dhcp ..."
    # Queremos extraer destino y next-hop
    match = re.match(r"^(\S+)\s+via\s+(\S+)", line)
    if match:
        dest, via = match.groups()
        # Añadir a set en formato "destino via gateway"
        system_routes.add(f"{dest} via {via}")

# Parsear las rutas de Netplan:
# netplan_data suele tener la estructura de un diccionario con 'network', 'ethernets', etc.
# Pueden existir múltiples bloques de rutas, por ejemplo:
# network:
#   version: 2
#   ethernets:
#     eth0:
#       addresses: [...]
#       routes:
#         - to: 10.0.0.0/24
#           via: 10.0.0.1
#
# Se debe recolectar todas las rutas definidas en cualquier interfaz.
netplan_routes = set()

def normalize_route(route_dest):
    # Quitar /32 si existe
    return re.sub(r"/32$", "", route_dest)

def extract_routes(data):
    if isinstance(data, dict):
        for key, value in data.items():
            if key == "routes" and isinstance(value, list):
                for route in value:
                    if "to" in route and "via" in route:
                        r_to = normalize_route(route["to"])
                        r_via = route["via"]
                        netplan_routes.add(f"{r_to} via {r_via}")
            else:
                extract_routes(value)
    elif isinstance(data, list):
        for item in data:
            extract_routes(item)

# Extraer rutas desde la data de netplan
extract_routes(netplan_data)

# Comparar
missing_routes = sorted(system_routes - netplan_routes)   # Rutas en sistema que no están en netplan
obsolete_routes = sorted(netplan_routes - system_routes)  # Rutas en netplan que no están en sistema

# Contar
system_count = len(system_routes)
netplan_count = len(netplan_routes)
missing_count = len(missing_routes)
obsolete_count = len(obsolete_routes)

# Mostrar resultados
if missing_count == 0:
    print(f"Todas las rutas del sistema están definidas en {NETPLAN_FILE}.")
else:
    print(f"Rutas faltantes en {NETPLAN_FILE} (definidas en el sistema, pero no en Netplan):")
    for route in missing_routes:
        print(f" - {route}")

if obsolete_count == 0:
    print("Todas las rutas de Netplan están activas en el sistema.")
else:
    print("Rutas obsoletas en Netplan (definidas en Netplan, pero no en el sistema):")
    for route in obsolete_routes:
        print(f" - {route}")

print("")
print(f"Total rutas en ip route con 'via': {system_count}")
print(f"Total rutas en Netplan: {netplan_count}")
print(f"Rutas faltantes: {missing_count}")
print(f"Rutas obsoletas: {obsolete_count}")
