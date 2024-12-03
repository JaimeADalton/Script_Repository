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
  version = {snmp_version}
  community = "GestionGrp"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    snmp_device_alias = "{device_alias_with_ip}"

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

# Plantilla para monitoreo ICMP
TEMPLATE_ICMP = """
[[inputs.ping]]
  urls = ["{agent_ip}"]
  count = 1
  interval = "5s"
  name_override = "{table_name}"

  [inputs.ping.tags]
    icmp_device_alias = "{device_alias_with_ip}"

[[processors.rename]]
  [[processors.rename.replace]]
    tag = "url"
    dest = "source"
"""

import psutil
import signal

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
        print(f"Realizando consulta SNMP para obtener el hostname de {ip}...")
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=version),  # SNMP version 2c
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
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
        print(f"Consultando interfaces del agente {ip}...")
        for (error_indication,
             error_status,
             error_index,
             var_binds) in nextCmd(SnmpEngine(),
                                   CommunityData(community, mpModel=version),
                                   UdpTransportTarget((ip, 161), timeout=5, retries=1),
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

def generate_selected_interfaces_config(agent_ip, table_name, selected_interfaces, snmp_version):
    """Genera la configuración de Telegraf para las interfaces seleccionadas."""
    config = ""

    for if_index, if_descr, device_alias in selected_interfaces:
        # Construir device_alias con el formato deseado: "nombre: IP"
        device_alias_with_ip = f"{device_alias}: {agent_ip}"

        config += f"""# Configuración SNMP para la interfaz {if_descr} (índice {if_index})
[[inputs.snmp]]
  name = "{table_name}"
  agents = ['{agent_ip}']
  version = {snmp_version}
  community = "GestionGrp"
  interval = "30s"
  precision = "30s"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    ifDescr = "{if_descr}"
    snmp_device_alias = "{device_alias_with_ip}"

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

def reload_telegraf():
    """Recarga Telegraf enviando una señal SIGHUP al proceso."""
    for proc in psutil.process_iter(['pid', 'name']):
        if proc.info['name'] == 'telegraf':
            os.kill(proc.info['pid'], signal.SIGHUP)
            print("Telegraf recargado exitosamente.")
            return
    print("No se encontró el proceso Telegraf.")

def add_agent():
    """Función para añadir uno o más nuevos agentes SNMP."""
    while True:
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
                    continue
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

        # Solicitar las IPs a introducir
        ips_input = input("Introduce las direcciones IP de los agentes SNMP, separadas por comas: ").strip()
        agent_ips = [ip.strip() for ip in ips_input.split(',') if ip.strip()]
        if not agent_ips:
            print("No se introdujeron direcciones IP válidas.")
            continue

        for agent_ip in agent_ips:
            if not is_valid_ip(agent_ip):
                print(f"IP inválida: {agent_ip}. Se omitirá esta dirección.")
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
                print("No se pudo capturar el hostname por SNMP.")
                hostname = None

            # Sugerencia para el `device_alias`
            if hostname:
                device_alias_input = input(f"Introduce el alias del dispositivo (sugerencia: {hostname}): ").strip()
            else:
                device_alias_input = input("Introduce el alias del dispositivo (por ejemplo, 'Router Oficina Central'): ").strip()

            device_alias = device_alias_input if device_alias_input else (hostname if hostname else "UNKNOWN")

            # Construir device_alias_with_ip para las plantillas
            device_alias_with_ip = f"{device_alias}: {agent_ip}"

            # Selección de las interfaces a monitorizar
            while True:
                print("\n¿Deseas monitorizar todas las interfaces o elegir las interfaces a monitorizar?")
                print("1. Monitorizar todas las interfaces (recomendado si no estás seguro)")
                print("2. Elegir las interfaces a monitorizar (para monitorear interfaces específicas)")
                choice = input("Elige una opción (1 o 2): ").strip()

                if choice == '1':
                    # Generar configuración para monitorizar todas las interfaces
                    config_content = TEMPLATE_ALL_INTERFACES.format(
                        agent_ip=agent_ip,
                        device_alias_with_ip=device_alias_with_ip,
                        table_name=sede,
                        snmp_version=snmp_version
                    )
                    # Para ICMP, usar el alias del dispositivo
                    icmp_device_alias_with_ip = device_alias_with_ip
                    break

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
                    while True:
                        selected_indices_input = input("Ingresa los números de las interfaces a monitorizar, separados por espacios: ").strip()
                        selected_indices = [s.strip() for s in selected_indices_input.split() if s.strip().isdigit()]
                        selected_indices = [int(s) for s in selected_indices]

                        selected_interfaces = []
                        for idx in selected_indices:
                            if 1 <= idx <= len(interfaces):
                                if_index, if_descr = interfaces[idx -1]
                                # Solicitar device_alias para cada interfaz
                                device_alias_interface = input(f"Introduce el alias para la interfaz '{if_descr}' (o deja en blanco para usar '{device_alias}'): ").strip()
                                device_alias_final = device_alias_interface if device_alias_interface else device_alias
                                selected_interfaces.append((if_index, if_descr, device_alias_final))
                            else:
                                print(f"Número de interfaz inválido: {idx}")
                        if selected_interfaces:
                            break
                        else:
                            print("No se seleccionaron interfaces válidas. Por favor, inténtalo de nuevo.")

                    # Generar la configuración para las interfaces seleccionadas
                    config_content = generate_selected_interfaces_config(
                        agent_ip,
                        sede,
                        selected_interfaces,
                        snmp_version
                    )

                    # Determinar el alias para la configuración ICMP
                    if len(selected_interfaces) == 1:
                        # Usar el alias de la única interfaz seleccionada
                        icmp_device_alias_with_ip = f"{selected_interfaces[0][2]}: {agent_ip}"
                    else:
                        # Si hay múltiples interfaces, puedes optar por concatenar los alias o pedir al usuario que elija
                        # Por simplicidad, usaremos el alias de la primera interfaz
                        icmp_device_alias_with_ip = f"{selected_interfaces[0][2]}: {agent_ip}"

                    break

                else:
                    print("Opción inválida. Por favor, elige 1 o 2.")

            # Rutas de los archivos de configuración
            config_filename = f"snmp_{agent_ip}.conf"
            config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)

            icmp_config_filename = f"icmp_{agent_ip}.conf"
            icmp_config_path = os.path.join(TELEGRAF_DIR, sede, icmp_config_filename)

            # Generar configuración para monitoreo ICMP
            icmp_config_content = TEMPLATE_ICMP.format(
                agent_ip=agent_ip,
                table_name=sede,
                device_alias_with_ip=icmp_device_alias_with_ip
            )

            # Verificar si los archivos ya existen
            existing_files = []
            if os.path.exists(config_path):
                existing_files.append(config_path)
            if os.path.exists(icmp_config_path):
                existing_files.append(icmp_config_path)

            if existing_files:
                print("\nLos siguientes archivos ya existen y serán sobrescritos:")
                for f in existing_files:
                    print(f"- {f}")
                if not prompt_yes_no("¿Deseas continuar? (s/n): "):
                    print("Operación cancelada para este agente.")
                    continue

            # Crear o sobrescribir los archivos de configuración
            try:
                with open(config_path, 'w') as config_file:
                    config_file.write(config_content)
                print(f"Archivo de configuración SNMP guardado en {config_path}")
            except IOError as e:
                print(f"Error al escribir el archivo de configuración SNMP: {e}")
                continue

            try:
                with open(icmp_config_path, 'w') as config_file:
                    config_file.write(icmp_config_content)
                print(f"Archivo de configuración ICMP guardado en {icmp_config_path}")
            except IOError as e:
                print(f"Error al escribir el archivo de configuración ICMP: {e}")
                continue

        # Recargar Telegraf para aplicar los cambios
        reload_telegraf()
        print("Agentes añadidos exitosamente.")
        break

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

def delete_agent():
    """Función para eliminar un agente buscando por IP en archivos con nombre específico."""
    while True:
        sedes = list_sedes()
        if not sedes:
            print("No hay sedes disponibles.")
            return

        print("\nSelecciona la sede donde se encuentra el agente o escribe su nombre:")
        for i, sede in enumerate(sedes):
            print(f"{i + 1}. {sede}")

        sede_input = input("Elige un número o escribe el nombre de la sede: ").strip()

        if sede_input.isdigit():
            index = int(sede_input) - 1
            if 0 <= index < len(sedes):
                sede = sedes[index]
            else:
                print("Opción inválida.")
                continue
        else:
            sede_input = sede_input.strip()
            sede_lower = sede_input.lower()
            sedes_lower = [s.lower() for s in sedes]
            if sede_lower in sedes_lower:
                sede = sedes[sedes_lower.index(sede_lower)]
            else:
                print("La sede especificada no existe.")
                continue

        agent_ip = input("Introduce la IP del agente a eliminar: ").strip()

        if not is_valid_ip(agent_ip):
            print("IP inválida. Por favor, introduce una dirección IP válida.")
            continue

        config_filenames = [
            f"config_{agent_ip}.conf",
            f"icmp_{agent_ip}.conf"
        ]
        archivos_eliminados = []

        # Buscar y eliminar los archivos de configuración en la sede especificada
        for config_filename in config_filenames:
            config_path = os.path.join(TELEGRAF_DIR, sede, config_filename)
            if os.path.exists(config_path):
                # Leer el alias del dispositivo desde el archivo de configuración SNMP
                if config_filename.startswith("config_"):
                    try:
                        with open(config_path, 'r') as config_file:
                            content = config_file.read()
                        match = re.search(r'device_alias\s*=\s*"(.*?)"', content)
                        device_alias = match.group(1) if match else "UNKNOWN"
                    except IOError as e:
                        print(f"Error al leer el archivo {config_path}: {e}")
                        continue
                    confirm_message = f"¿Estás seguro de eliminar el agente '{device_alias}' con IP {agent_ip} y archivo {config_path}? (s/n): "
                else:
                    # Para archivos ICMP, no hay device_alias
                    confirm_message = f"¿Estás seguro de eliminar el archivo de configuración ICMP para la IP {agent_ip} en {config_path}? (s/n): "

                # Confirmar con el usuario antes de eliminar
                if prompt_yes_no(confirm_message):
                    try:
                        os.remove(config_path)
                        archivos_eliminados.append(config_path)
                        print(f"Archivo eliminado: {config_path}")
                    except IOError as e:
                        print(f"Error al eliminar el archivo {config_path}: {e}")
                else:
                    print(f"Eliminación del archivo {config_path} cancelada.")
            else:
                print(f"No se encontró el archivo {config_path}.")

        if archivos_eliminados:
            # Recargar Telegraf para aplicar los cambios
            reload_telegraf()
            print(f"Agente con IP {agent_ip} eliminado correctamente.")
        else:
            print(f"No se encontró ningún archivo de configuración para la IP {agent_ip} en la sede {sede}.")

        break

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
            sys.exit(0)
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
