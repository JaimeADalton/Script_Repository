#!/usr/bin/env python3
import os
import re
import sys
from pysnmp.hlapi import *
from pysnmp.smi import builder, view, compiler

# -----------------------------------------------------------------------------
# CONFIGURACIÓN INICIAL DE MIBs
# -----------------------------------------------------------------------------
mib_builder = builder.MibBuilder()
mib_sources = mib_builder.getMibSources() + (builder.DirMibSource('/usr/share/snmp/mibs/ietf'),)
mib_builder.setMibSources(*mib_sources)
compiler.addMibCompiler(mib_builder)
# Cargamos solo el IF-MIB (no es necesario cargar RFC1213-MIB ya que usaremos OID numérico para sysName)
try:
    mib_builder.loadModules('IF-MIB')
except Exception as e:
    print(f"Error al cargar MIBs: {e}")
    sys.exit(1)
mib_view_controller = view.MibViewController(mib_builder)

# Directorio base de configuraciones
TELEGRAF_DIR = '/etc/telegraf/telegraf.d'

# -----------------------------------------------------------------------------
# PLANTILLAS DE CONFIGURACIÓN
# -----------------------------------------------------------------------------
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

TEMPLATE_SELECTED_INTERFACES = """
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
    oid = "1.3.6.1.2.1.1.5.0"
    is_tag = true

  [[inputs.snmp.table]]
    name = "{table_name}"
    inherit_tags = ["hostname"]
"""

TEMPLATE_ICMP = """
[[inputs.ping]]
  urls = ["{agent_ip}"]
  count = 1
  interval = "5s"
  name_override = "icmp_ping"

  [inputs.ping.tags]
    device_alias = "{device_alias}"
    sede = "{sede}"

[[processors.rename]]
  [[processors.rename.replace]]
    tag = "url"
    dest = "source"
"""

# -----------------------------------------------------------------------------
# FUNCIONES AUXILIARES
# -----------------------------------------------------------------------------
def list_sedes():
    try:
        return sorted([f for f in os.listdir(TELEGRAF_DIR) if os.path.isdir(os.path.join(TELEGRAF_DIR, f))])
    except FileNotFoundError:
        print(f"Error: El directorio {TELEGRAF_DIR} no existe.")
        return []

def is_valid_ip(ip):
    pattern = re.compile(r"""
        ^
        (?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}
        (?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)
        $
    """, re.VERBOSE)
    return pattern.match(ip) is not None

def prompt_yes_no(prompt):
    while True:
        resp = input(prompt).strip().lower()
        if resp in ['s', 'y']:
            return True
        elif resp in ['n']:
            return False
        else:
            print("Respuesta inválida. Introduce 's' o 'n'.")

def snmp_get(ip, community, oid):
    try:
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=1),
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
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
            if var_binds:
                return var_binds[0][1].prettyPrint()
            else:
                print("No se recibió ningún valor SNMP.")
                return None
    except Exception as e:
        print(f"Excepción durante la consulta SNMP: {e}")
        return None

def snmp_walk(ip, community, oid):
    result = []
    try:
        for (error_indication, error_status, error_index, var_binds) in nextCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=1),
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
            ContextData(),
            ObjectType(ObjectIdentity(oid)),
            lexicographicMode=False
        ):
            if error_indication:
                print(f"Error en la consulta SNMP: {error_indication}")
                break
            elif error_status:
                print(f"{error_status.prettyPrint()} en {error_index and var_binds[int(error_index)-1] or '?'}")
                break
            else:
                for var_bind in var_binds:
                    oid_str, value = var_bind
                    result.append((oid_str.prettyPrint(), value.prettyPrint()))
        return result
    except Exception as e:
        print(f"Excepción durante el SNMP walk: {e}")
        return []

def get_hostname_snmp(ip, community="GestionGrp"):
    # Usamos el OID numérico para sysName
    return snmp_get(ip, community, "1.3.6.1.2.1.1.5.0")

def create_new_sede(sede_name=None):
    if sede_name is None:
        sede_name = input("Introduce el nombre de la nueva sede: ").strip()
    sede_path = os.path.join(TELEGRAF_DIR, sede_name)
    if os.path.exists(sede_path):
        print(f"La sede {sede_name} ya existe.")
        return sede_name
    try:
        os.makedirs(sede_path)
        print(f"Sede {sede_name} creada exitosamente.")
        return sede_name
    except Exception as e:
        print(f"Error al crear la sede {sede_name}: {e}")
        return None

def get_interfaces(agent_ip, community):
    oid = "IF-MIB::ifDescr"
    interfaces = []
    snmp_results = snmp_walk(agent_ip, community, oid)
    if not snmp_results:
        return None
    for oid_str, value in snmp_results:
        match = re.match(r'.*::ifDescr\.(\d+)$', oid_str)
        if match:
            interfaces.append((match.group(1), value))
    return interfaces

def generate_selected_interfaces_config(agent_ip, device_alias, table_name, selected_interfaces):
    config = TEMPLATE_SELECTED_INTERFACES.format(agent_ip=agent_ip, device_alias=device_alias, table_name=table_name)
    for if_index, if_descr in selected_interfaces:
        config += f"""
    [[inputs.snmp.table.field]]
      oid = "IF-MIB::ifHCInOctets.{if_index}"
      name = "{if_descr}_In"

    [[inputs.snmp.table.field]]
      oid = "IF-MIB::ifHCOutOctets.{if_index}"
      name = "{if_descr}_Out"
"""
    return config

# -----------------------------------------------------------------------------
# FUNCIÓN PARA AÑADIR AGENTES (mejorada)
# -----------------------------------------------------------------------------
def add_agent():
    sedes = list_sedes()
    if not sedes:
        print("No hay sedes disponibles.")
        if not prompt_yes_no("¿Deseas añadir una nueva sede? (s/n): "):
            return
        else:
            sede = create_new_sede()
            if not sede:
                return
    else:
        print("\nSelecciona la sede o escribe su nombre:")
        for i, s in enumerate(sedes, start=1):
            print(f"{i}. {s}")
        print(f"{len(sedes)+1}. Añadir nueva sede")
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
            sede_lower = sede_input.lower()
            sedes_lower = [s.lower() for s in sedes]
            if sede_lower in sedes_lower:
                sede = sedes[sedes_lower.index(sede_lower)]
            else:
                sede = create_new_sede(sede_input)
                if not sede:
                    return

    ips_input = input("Introduce las IPs de los agentes SNMP, separadas por espacios: ").strip()
    agent_ips = [ip.strip() for ip in ips_input.split() if ip.strip()]
    if not agent_ips:
        print("No se introdujeron IPs válidas.")
        return

    for agent_ip in agent_ips:
        if not is_valid_ip(agent_ip):
            print(f"IP inválida: {agent_ip}")
            continue

        community = "GestionGrp"
        hostname = get_hostname_snmp(agent_ip, community)
        if hostname:
            print(f"Hostname capturado por SNMP: {hostname}")
        else:
            print("No se pudo capturar el hostname por SNMP. Se usará 'UNKNOWN'.")
            hostname = "UNKNOWN"

        device_alias = input(f"Introduce el alias del dispositivo (sugerencia: {hostname}): ").strip()
        device_alias = device_alias if device_alias else hostname

        print("¿Deseas monitorizar todas las interfaces o elegir las interfaces a monitorizar?")
        print("1. Monitorizar todas las interfaces")
        print("2. Elegir las interfaces a monitorizar")
        choice = input("Elige una opción (1 o 2): ").strip()

        snmp_filename = f"snmp_{agent_ip}.conf"
        icmp_filename = f"icmp_{agent_ip}.conf"
        snmp_path = os.path.join(TELEGRAF_DIR, sede, snmp_filename)
        icmp_path = os.path.join(TELEGRAF_DIR, sede, icmp_filename)

        if os.path.exists(snmp_path) or os.path.exists(icmp_path):
            if not prompt_yes_no(f"Los archivos para la IP {agent_ip} ya existen en la sede {sede}. ¿Deseas sobrescribirlos? (s/n): "):
                print("Operación cancelada para este agente.")
                continue

        if choice == '1':
            config_snmp = TEMPLATE_ALL_INTERFACES.format(agent_ip=agent_ip, device_alias=device_alias, table_name=sede)
        elif choice == '2':
            interfaces = get_interfaces(agent_ip, community)
            if not interfaces:
                print("No se pudieron obtener las interfaces del agente SNMP.")
                continue
            print("\nInterfaces disponibles:")
            for i, (if_index, if_descr) in enumerate(interfaces, start=1):
                print(f"{i}. {if_descr} (Index: {if_index})")
            selected_indices = input("Ingresa los números de las interfaces a monitorizar, separados por espacios: ").strip()
            selected_indices = [int(x) for x in selected_indices.split() if x.isdigit()]
            selected_interfaces = []
            for idx in selected_indices:
                if 1 <= idx <= len(interfaces):
                    selected_interfaces.append(interfaces[idx-1])
                else:
                    print(f"Número de interfaz inválido: {idx}")
            if not selected_interfaces:
                print("No se seleccionaron interfaces válidas.")
                continue
            config_snmp = generate_selected_interfaces_config(agent_ip, device_alias, sede, selected_interfaces)
        else:
            print("Opción inválida. Operación cancelada para este agente.")
            continue

        try:
            with open(snmp_path, 'w') as f:
                f.write(config_snmp)
            print(f"Archivo SNMP guardado en {snmp_path}")
        except IOError as e:
            print(f"Error al escribir el archivo SNMP: {e}")
            continue

        config_icmp = TEMPLATE_ICMP.format(agent_ip=agent_ip, device_alias=device_alias, sede=sede)
        try:
            with open(icmp_path, 'w') as f:
                f.write(config_icmp)
            print(f"Archivo ICMP guardado en {icmp_path}")
        except IOError as e:
            print(f"Error al escribir el archivo ICMP: {e}")

# -----------------------------------------------------------------------------
# FUNCIÓN PARA ELIMINAR AGENTES
# -----------------------------------------------------------------------------
def delete_agent():
    sedes = list_sedes()
    agent_ip = input("Introduce la IP del agente a eliminar: ").strip()
    if not is_valid_ip(agent_ip):
        print("IP inválida. Introduce una dirección IP válida.")
        return

    snmp_filename = f"snmp_{agent_ip}.conf"
    icmp_filename = f"icmp_{agent_ip}.conf"
    archivos_eliminados = []

    for sede in sedes:
        for path in [os.path.join(TELEGRAF_DIR, sede, snmp_filename),
                     os.path.join(TELEGRAF_DIR, sede, icmp_filename)]:
            if os.path.exists(path):
                try:
                    with open(path, 'r') as f:
                        content = f.read()
                    match = re.search(r'device_alias\s*=\s*"(.*?)"', content)
                    device_alias = match.group(1) if match else "UNKNOWN"
                except IOError as e:
                    print(f"Error al leer {path}: {e}")
                    continue
                if prompt_yes_no(f"¿Estás seguro de eliminar el agente '{device_alias}' con IP {agent_ip} y archivo {path}? (s/n): "):
                    try:
                        os.remove(path)
                        archivos_eliminados.append(path)
                        print(f"Archivo eliminado: {path}")
                    except IOError as e:
                        print(f"Error al eliminar {path}: {e}")
                else:
                    print(f"Eliminación cancelada para {path}.")

    if not archivos_eliminados:
        print(f"No se encontró ningún archivo de configuración para la IP {agent_ip} en ninguna sede.")
    else:
        print(f"Agente con IP {agent_ip} eliminado correctamente.")

# -----------------------------------------------------------------------------
# FUNCIÓN PRINCIPAL
# -----------------------------------------------------------------------------
def main():
    # Reconfiguramos MIB builder con otra fuente adicional
    mib_builder = builder.MibBuilder()
    mib_sources = mib_builder.getMibSources() + (builder.DirMibSource('/usr/share/snmp/mibs'),)
    mib_builder.setMibSources(*mib_sources)
    compiler.addMibCompiler(mib_builder, sources=['http://mibs.snmplabs.com/asn1/@mib@'])
    global mib_view_controller
    mib_view_controller = view.MibViewController(mib_builder)

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
            print("Opción inválida, elige 1, 2 o 3.")

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("Este script debe ejecutarse con permisos de superusuario (sudo).")
        sys.exit(1)
    try:
        import pysnmp
    except ImportError:
        print("La librería 'pysnmp' no está instalada. Ejecuta 'pip install pysnmp'.")
        sys.exit(1)
    main()
