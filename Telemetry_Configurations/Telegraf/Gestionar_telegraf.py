#!/usr/bin/env python3
import os
import re
import sys
from pysnmp.hlapi import *

# Ruta base donde están las configuraciones de las sedes
TELEGRAF_DIR = '/etc/telegraf/telegraf.d'

# Plantilla de configuración de Telegraf para SNMP
TEMPLATE = """
[[inputs.snmp]]
  interval = "30s"
  precision = "30s"
  agents = ['{agent_ip}']
  version = 2
  community = "GestionGrp"
  timeout = "10s"
  retries = 3
  agent_host_tag = "source"

  [inputs.snmp.tags]
    device_alias = "{device_alias}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "1.3.6.1.2.1.1.5.0"
    is_tag = true

  [[inputs.snmp.table]]
    name = "{table_name}"
    inherit_tags = ["hostname"]

    [[inputs.snmp.table.field]]
      name = "ifDescr"
      oid = "IF-MIB::ifDescr"
      is_tag = true

    [[inputs.snmp.table.field]]
      name = "ifHCInOctets"
      oid = "IF-MIB::ifHCInOctets"

    [[inputs.snmp.table.field]]
      name = "ifHCOutOctets"
      oid = "IF-MIB::ifHCOutOctets"
"""

def list_sedes():
    """Lista los subdirectorios en /etc/telegraf/telegraf.d que representan las sedes, ordenados alfabéticamente."""
    try:
        sedes = sorted([
            f for f in os.listdir(TELEGRAF_DIR)
            if os.path.isdir(os.path.join(TELEGRAF_DIR, f))
        ])
        return sedes
    except FileNotFoundError:
        print(f"Error: El directorio {TELEGRAF_DIR} no existe.")
        return []

def is_valid_ip(ip):
    """Valida el formato de una dirección IP IPv4."""
    pattern = re.compile(r"""
        ^
        (?:
          # Dotted variants:
          (?:
            # Decimal 0-255 (no leading zeros)
            (?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)
          \.){3}
          (?:
            25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d
          )
        )
        $
    """, re.VERBOSE)
    return pattern.match(ip) is not None

def prompt_yes_no(prompt):
    """Función para obtener una respuesta sí/no del usuario."""
    while True:
        response = input(prompt).strip().lower()
        if response == 's':
            return True
        elif response == 'n':
            return False
        else:
            print("Respuesta inválida. Por favor, introduce 's' o 'n'.")

def snmp_get(ip, community, oid):
    """Realiza una consulta SNMP para obtener el hostname desde un agente SNMP."""
    try:
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=1),  # SNMP v2c
            UdpTransportTarget((ip, 161), timeout=2, retries=1),
            ContextData(),
            ObjectType(ObjectIdentity(oid))
        )

        error_indication, error_status, error_index, var_binds = next(iterator)

        if error_indication:
            print(f"Error en la consulta SNMP: {error_indication}")
            return None
        elif error_status:
            print(f"{error_status.prettyPrint()} en {error_index and var_binds[int(error_index)-1] or '?'}")
            return None
        else:
            # var_binds contiene la respuesta SNMP. El valor es lo que nos interesa.
            if var_binds:
                return var_binds[0][1].prettyPrint()
            else:
                print("No se recibió ningún valor SNMP.")
                return None
    except Exception as e:
        print(f"Excepción durante la consulta SNMP: {e}")
        return None

def add_agent():
    """Función para añadir un nuevo agente SNMP."""
    sedes = list_sedes()

    if not sedes:
        print("No hay sedes disponibles.")
        return

    print("\nSelecciona la sede o escribe su nombre:")
    for i, sede in enumerate(sedes):
        print(f"{i + 1}. {sede}")

    sede_input = input("Elige un número o escribe el nombre de la sede: ").strip()

    if sede_input.isdigit():
        index = int(sede_input) - 1
        if 0 <= index < len(sedes):
            sede = sedes[index]
        else:
            print("Opción inválida.")
            return
    else:
        sede_input = sede_input.strip()
        sede_lower = sede_input.lower()
        sedes_lower = [s.lower() for s in sedes]
        if sede_lower in sedes_lower:
            sede = sedes[sedes_lower.index(sede_lower)]
        else:
            print(f"La sede '{sede_input}' no existe.")
            return

    agent_ip = input("Introduce la IP del agente SNMP: ").strip()

    if not is_valid_ip(agent_ip):
        print("IP inválida. Por favor, introduce una dirección IP válida.")
        return

    # Consultamos SNMP para obtener el hostname
    oid = '1.3.6.1.2.1.1.5.0'  # OID numérico para el hostname
    community = 'public'         # Comunidad SNMP por defecto
    hostname = snmp_get(agent_ip, community, oid)

    if hostname:
        print(f"Hostname capturado por SNMP: {hostname}")
    else:
        print("No se pudo capturar el hostname por SNMP. Se usará 'UNKNOWN' como alias por defecto.")
        hostname = "UNKNOWN"

    # Sugerencia para el `device_alias`
    device_alias = input(f"Introduce el alias del dispositivo (sugerencia: {hostname}): ").strip() or hostname

    # Nombre del archivo .conf
    config_filename = f"config_{agent_ip}.conf"
    config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)

    # Verificar si el archivo ya existe
    if os.path.exists(config_path):
        if not prompt_yes_no(f"El archivo {config_filename} ya existe en la sede {sede}. ¿Deseas sobrescribirlo? (s/n): "):
            print("Operación cancelada.")
            return

    # Crear el archivo de configuración con la plantilla
    config_content = TEMPLATE.format(agent_ip=agent_ip, device_alias=device_alias, table_name=sede)

    try:
        with open(config_path, 'w') as config_file:
            config_file.write(config_content)
        print(f"Agente añadido y archivo guardado en {config_path}")
    except IOError as e:
        print(f"Error al escribir el archivo de configuración: {e}")

def delete_agent():
    """Función para eliminar un agente buscando por IP en todas las sedes."""
    agent_ip = input("Introduce la IP del agente a eliminar: ").strip()

    if not is_valid_ip(agent_ip):
        print("IP inválida. Por favor, introduce una dirección IP válida.")
        return

    config_filename = f"config_{agent_ip}.conf"
    archivos_eliminados = []

    # Recorrer todas las sedes y buscar el archivo de configuración
    sedes = list_sedes()
    for sede in sedes:
        config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)
        if os.path.exists(config_path):
            # Leer el alias del dispositivo desde el archivo de configuración
            try:
                with open(config_path, 'r') as config_file:
                    content = config_file.read()
                match = re.search(r'device_alias\s*=\s*"(.*?)"', content)
                device_alias = match.group(1) if match else "UNKNOWN"
            except IOError as e:
                print(f"Error al leer el archivo {config_path}: {e}")
                continue

            # Confirmar con el usuario antes de eliminar, incluyendo la ruta del archivo
            if prompt_yes_no(f"¿Estás seguro de eliminar el agente '{device_alias}' con IP {agent_ip} y archivo {config_path}? (s/n): "):
                try:
                    os.remove(config_path)
                    archivos_eliminados.append(config_path)
                    print(f"Archivo eliminado: {config_path}")
                except IOError as e:
                    print(f"Error al eliminar el archivo {config_path}: {e}")
            else:
                print(f"Eliminación del archivo {config_path} cancelada.")

    if not archivos_eliminados:
        print(f"No se encontró ningún archivo de configuración para la IP {agent_ip} en ninguna sede.")
    else:
        print(f"Agente con IP {agent_ip} eliminado correctamente.")

def main():
    """Función principal del script."""
    while True:
        print("\n--- Gestión de Telegraf ---")
        print("1. Añadir agente")
        print("2. Eliminar agente")
        print("3. Salir")

        choice = input("Elige una opción: ").strip()

        if choice == '1':
            add_agent()
        elif choice == '2':
            delete_agent()
        elif choice == '3':
            print("Saliendo...")
            break
        else:
            print("Opción inválida, por favor elige 1, 2 o 3.")

if __name__ == "__main__":
    # Verificar si se está ejecutando como root
    if os.geteuid() != 0:
        print("Este script debe ser ejecutado con permisos de superusuario (sudo).")
        sys.exit(1)

    # Verificar si pysnmp está instalado
    try:
        import pysnmp
    except ImportError:
        print("La librería 'pysnmp' no está instalada. Puedes instalarla ejecutando 'pip install pysnmp'.")
        sys.exit(1)

    main()
