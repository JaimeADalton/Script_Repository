#!/usr/bin/env python3
import os
import re
import sys
from pysnmp.hlapi import *

# Ruta base donde están las configuraciones de las sedes
TELEGRAF_DIR = '/etc/telegraf/telegraf.d'

# Plantilla para monitorizar todas las interfaces (usando nombres simbólicos en los MIBs)
TEMPLATE_ALL_INTERFACES = """
[[inputs.snmp]]
  precision = "30s"
  interval = "30s"
  agents = ['{agent_ip}']
  version = 2
  community = "GestionGrp"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    device_alias = "{device_alias}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
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
    """Lista los subdirectorios en TELEGRAF_DIR que representan las sedes, ordenados alfabéticamente."""
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

def snmp_get(ip, community, oid, version):
    """Realiza una consulta SNMP para obtener un valor desde un agente SNMP."""
    try:
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=version),  # SNMP version 2c
            UdpTransportTarget((ip, 161), timeout=5, retries=3),
            ContextData(),
            ObjectType(ObjectIdentity(oid))
        )

        error_indication, error_status, error_index, var_binds = next(iterator)

        if error_indication:
            print(f"Error en la consulta SNMP GET: {error_indication}")
            return None
        elif error_status:
            print(f"{error_status.prettyPrint()} en {error_index and var_binds[int(error_index)-1] or '?'}")
            return None
        else:
            if var_binds:
                return var_binds[0][1].prettyPrint()
            else:
                print("No se recibió ningún valor SNMP.")
                return None
    except Exception as e:
        print(f"Excepción durante la consulta SNMP GET: {e}")
        return None

def snmp_walk(ip, community, oid, version):
    """Realiza un SNMP walk para obtener una tabla de valores."""
    result = []
    try:
        for (error_indication,
             error_status,
             error_index,
             var_binds) in nextCmd(SnmpEngine(),
                                   CommunityData(community, mpModel=version),
                                   UdpTransportTarget((ip, 161), timeout=5, retries=3),
                                   ContextData(),
                                   ObjectType(ObjectIdentity(oid)),
                                   lexicographicMode=False):

            if error_indication:
                print(f"Error en la consulta SNMP WALK: {error_indication}")
                break
            elif error_status:
                print(f"{error_status.prettyPrint()} en {error_index and var_binds[int(error_index)-1] or '?'}")
                break
            else:
                for var_bind in var_binds:
                    oid_obj, value = var_bind
                    oid_tuple = oid_obj.asTuple()
                    result.append((oid_tuple, value.prettyPrint()))
        return result
    except Exception as e:
        print(f"Excepción durante el SNMP WALK: {e}")
        return []

def add_agent():
    """Función para añadir uno o más nuevos agentes SNMP."""
    sedes = list_sedes()

    if not sedes:
        print("No hay sedes disponibles.")
        add_new_sede = prompt_yes_no("¿Deseas añadir una nueva sede? (s/n): ")
        if not add_new_sede:
            return
        else:
            sede = create_new_sede()
            if not sede:
                return
    else:
        print("\nSelecciona la sede o escribe su nombre:")
        for i, sede in enumerate(sedes):
            print(f"{i + 1}. {sede}")
        print(f"{len(sedes) + 1}. Añadir nueva sede")

        sede_input = input("Elige un número o escribe el nombre de la sede: ").strip()

        if sede_input.isdigit():
            index = int(sede_input) - 1
            if 0 <= index < len(sedes):
                sede = sedes[index]
            elif index == len(sedes):
                sede = create_new_sede()
                if not sede:
                    return
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
                sede = create_new_sede(sede_input)
                if not sede:
                    return

    # Solicitar cuántas IPs se van a introducir
    while True:
        num_ips_input = input("Ingresa cuántas direcciones IP vas a introducir: ").strip()
        if num_ips_input.isdigit() and int(num_ips_input) > 0:
            num_ips = int(num_ips_input)
            break
        else:
            print("Por favor, ingresa un número válido mayor que cero.")

    for _ in range(num_ips):
        agent_ip = input("Introduce la IP del agente SNMP: ").strip()

        if not is_valid_ip(agent_ip):
            print("IP inválida. Por favor, introduce una dirección IP válida.")
            continue

        snmp_version = 2
        mp_model = 1  # Correspondiente a SNMPv2c

        community = 'GestionGrp'  # Comunidad SNMP por defecto

        # Consultamos SNMP para obtener el hostname
        oid_hostname = '1.3.6.1.2.1.1.5.0'  # OID numérico para el hostname
        hostname = snmp_get(agent_ip, community, oid_hostname, mp_model)

        if hostname:
            print(f"Hostname capturado por SNMP: {hostname}")
        else:
            print("No se pudo capturar el hostname por SNMP. Se usará 'UNKNOWN' como alias por defecto.")
            hostname = "UNKNOWN"

        # Sugerencia para el `device_alias`
        device_alias_input = input(f"Introduce el alias del dispositivo (sugerencia: {hostname}): ").strip()
        device_alias = device_alias_input if device_alias_input else hostname

        # Preguntar si desea monitorizar todas las interfaces o elegir las interfaces
        print("¿Deseas monitorizar todas las interfaces o elegir las interfaces a monitorizar?")
        print("1. Monitorizar todas las interfaces")
        print("2. Elegir las interfaces a monitorizar")
        choice = input("Elige una opción (1 o 2): ").strip()

        if choice == '1':
            # Generar configuración para monitorizar todas las interfaces
            config_content = TEMPLATE_ALL_INTERFACES.format(
                agent_ip=agent_ip,
                device_alias=device_alias,
                table_name=sede
            )

            # Nombre del archivo .conf
            default_filename = f"config_{agent_ip}.conf"
            config_filename = input(f"Introduce el nombre para el archivo de configuración (sugerencia: {default_filename}): ").strip()
            config_filename = config_filename if config_filename else default_filename
            config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)

        elif choice == '2':
            # Obtener la lista de interfaces usando OIDs numéricos
            interfaces = get_interfaces(agent_ip, community, mp_model)
            if not interfaces:
                print("No se pudieron obtener las interfaces del agente SNMP.")
                continue

            # Mostrar las interfaces al usuario
            print("\nInterfaces disponibles:")
            for i, (if_index, if_descr) in enumerate(interfaces):
                print(f"{i+1}. {if_descr} (Index: {if_index})")

            # Pedir al usuario que seleccione las interfaces
            selected_indices_input = input("Ingresa los números de las interfaces a monitorizar, separados por espacios: ").strip()
            selected_indices = [s.strip() for s in selected_indices_input.split() if s.strip().isdigit()]
            selected_indices = [int(s) for s in selected_indices]

            selected_interfaces = []
            for idx in selected_indices:
                if 1 <= idx <= len(interfaces):
                    selected_interfaces.append(interfaces[idx -1])
                else:
                    print(f"Número de interfaz inválido: {idx}")

            if not selected_interfaces:
                print("No se seleccionaron interfaces válidas.")
                continue

            # Generar la configuración para las interfaces seleccionadas
            config_content = generate_selected_interfaces_config(
                agent_ip,
                device_alias,
                sede,
                selected_interfaces,
                snmp_version
            )

            # Nombre del archivo .conf
            default_filename = f"config_{agent_ip}.conf"
            config_filename = input(f"Introduce el nombre para el archivo de configuración (sugerencia: {default_filename}): ").strip()
            config_filename = config_filename if config_filename else default_filename
            config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)

        else:
            print("Opción inválida. Operación cancelada para este agente.")
            continue

        # Verificar si el archivo ya existe
        if os.path.exists(config_path):
            if not prompt_yes_no(f"El archivo {config_filename} ya existe en la sede {sede}. ¿Deseas sobrescribirlo? (s/n): "):
                print("Operación cancelada para este agente.")
                continue

        # Crear el archivo de configuración
        try:
            with open(config_path, 'w') as config_file:
                config_file.write(config_content)
            print(f"Agente añadido y archivo guardado en {config_path}")
        except IOError as e:
            print(f"Error al escribir el archivo de configuración: {e}")

def create_new_sede(sede_name=None):
    """Función para crear una nueva sede."""
    if sede_name is None:
        sede_name = input("Introduce el nombre de la nueva sede: ").strip()
    sede_path = os.path.join(TELEGRAF_DIR, sede_name)
    if os.path.exists(sede_path):
        print(f"La sede {sede_name} ya existe.")
        return sede_name
    else:
        try:
            os.makedirs(sede_path)
            print(f"Sede {sede_name} creada exitosamente.")
            return sede_name
        except Exception as e:
            print(f"Error al crear la sede {sede_name}: {e}")
            return None

def get_interfaces(agent_ip, community, mp_model):
    """Obtiene la lista de interfaces del agente SNMP."""
    # OID numérico para ifDescr
    oid = '1.3.6.1.2.1.2.2.1.2'  # ifDescr
    interfaces = []
    snmp_results = snmp_walk(agent_ip, community, oid, mp_model)
    if not snmp_results:
        return None
    base_oid = (1,3,6,1,2,1,2,2,1,2)
    for oid_tuple, value in snmp_results:
        # OID: 1.3.6.1.2.1.2.2.1.2.<ifIndex>
        if oid_tuple[:len(base_oid)] == base_oid and len(oid_tuple) > len(base_oid):
            if_index = oid_tuple[len(base_oid)]
            interfaces.append((str(if_index), value))
    return interfaces

def generate_selected_interfaces_config(agent_ip, device_alias, table_name, selected_interfaces, snmp_version):
    """Genera la configuración de Telegraf para las interfaces seleccionadas."""
    config = f"""# Configuración común para todas las interfaces
[global_tags]
  device_alias = "{device_alias}"

"""

    for if_index, if_descr in selected_interfaces:
        config += f"""# Configuración SNMP para la interfaz {if_descr} (índice {if_index})
[[inputs.snmp]]
  name = "{table_name}"
  agents = ['{agent_ip}']
  version = 2
  community = "GestionGrp"
  interval = "30s"
  precision = "30s"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    ifDescr = "{if_descr}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
    is_tag = true

  [[inputs.snmp.field]]
    name = "ifHCInOctets"
    oid = "IF-MIB::ifHCInOctets.{if_index}"

  [[inputs.snmp.field]]
    name = "ifHCOutOctets"
    oid = "IF-MIB::ifHCOutOctets.{if_index}"

"""

    return config

def delete_agent():
    """Función para eliminar un agente buscando por IP en archivos con nombre específico."""
    sedes = list_sedes()
    agent_ip = input("Introduce la IP del agente a eliminar: ").strip()

    if not is_valid_ip(agent_ip):
        print("IP inválida. Por favor, introduce una dirección IP válida.")
        return

    config_filename = f"config_{agent_ip}.conf"
    archivos_eliminados = []

    # Recorrer todas las sedes y buscar el archivo de configuración
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

            # Confirmar con el usuario antes de eliminar
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
