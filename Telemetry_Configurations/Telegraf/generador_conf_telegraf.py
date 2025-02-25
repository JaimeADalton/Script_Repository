#!/usr/bin/env python3
import os
import re
import sys
from pysnmp.hlapi import *
from pysnmp.smi import builder, view, compiler

# Configuración de MIBs
mib_builder = builder.MibBuilder()
mib_sources = mib_builder.getMibSources() + (builder.DirMibSource('/usr/share/snmp/mibs'),)
mib_builder.setMibSources(*mib_sources)
compiler.addMibCompiler(mib_builder)
try:
    mib_builder.loadModules('IF-MIB', 'RFC1213-MIB')
except Exception as e:
    print(f"Error al cargar MIBs: {e}")
    sys.exit(1)
mib_view_controller = view.MibViewController(mib_builder)

TELEGRAF_DIR = '/etc/telegraf/telegraf.d'
# Variable booleana para incluir la IP en el device_alias.
# Si es True, se añade la IP; si es False, se omite.
INCLUDE_IP_IN_ALIAS = False

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

TEMPLATE_ICMP = """
[[inputs.ping]]
  urls = ["{agent_ip}"]
  count = 1
  interval = "5s"
  name_override = "icmp_ping"

  [inputs.ping.tags]
    device_alias = "{device_alias}"

[[processors.rename]]
  [[processors.rename.replace]]
    tag = "url"
    dest = "source"
"""

try:
    import psutil
    import signal
except ImportError:
    print("La librería 'psutil' no está instalada. Instálala con 'pip install psutil'.")
    sys.exit(1)

def list_sedes():
    try:
        sedes = sorted([f for f in os.listdir(TELEGRAF_DIR) if os.path.isdir(os.path.join(TELEGRAF_DIR, f))])
        return sedes
    except FileNotFoundError:
        print(f"Error: El directorio {TELEGRAF_DIR} no existe.")
        return []

def is_valid_ip(ip):
    pattern = re.compile(r"^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$")
    return pattern.match(ip) is not None

def prompt_yes_no(prompt):
    while True:
        response = input(prompt).strip().lower()
        if response == 's':
            return True
        elif response == 'n':
            return False
        else:
            print("Respuesta inválida. Introduce 's' o 'n'.")

def snmp_get(ip, community, oid, version):
    try:
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=version),
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
            ContextData(),
            ObjectType(ObjectIdentity(oid).resolveWithMib(mib_view_controller))
        )
        error_indication, error_status, error_index, var_binds = next(iterator)
        if error_indication:
            print(f"Error SNMP GET: {error_indication}")
            return None
        elif error_status:
            print(f"Error SNMP: {error_status.prettyPrint()}")
            return None
        return var_binds[0][1].prettyPrint() if var_binds else None
    except Exception as e:
        print(f"Excepción en SNMP GET: {e}")
        return None

def snmp_walk(ip, community, oid, version):
    result = []
    try:
        for (error_indication, error_status, error_index, var_binds) in nextCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=version),
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
            ContextData(),
            ObjectType(ObjectIdentity(oid).resolveWithMib(mib_view_controller)),
            lexicographicMode=False
        ):
            if error_indication:
                print(f"Error SNMP WALK: {error_indication}")
                break
            elif error_status:
                print(f"Error SNMP: {error_status.prettyPrint()}")
                break
            else:
                for var_bind in var_binds:
                    oid_obj, value = var_bind
                    oid_tuple = oid_obj.asTuple()
                    result.append((oid_tuple, value.prettyPrint()))
        return result
    except Exception as e:
        print(f"Excepción en SNMP WALK: {e}")
        return []

def generate_selected_interfaces_config(agent_ip, table_name, selected_interfaces, snmp_version):
    config = ""
    for if_index, if_descr, device_alias in selected_interfaces:
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
    device_alias = "{device_alias}"

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
    try:
        for proc in psutil.process_iter(['pid', 'name']):
            if proc.info['name'] == 'telegraf':
                os.kill(proc.info['pid'], signal.SIGHUP)
                print("Telegraf recargado exitosamente.")
                return
        print("No se encontró el proceso Telegraf.")
    except Exception as e:
        print(f"Error al recargar Telegraf: {e}")

def add_agent():
    while True:
        sedes = list_sedes()
        if not sedes:
            print("No hay sedes disponibles.")
            if not prompt_yes_no("¿Deseas añadir una nueva sede? (s/n): "):
                return
            sede = create_new_sede()
            if not sede:
                return
        else:
            print("\nSelecciona la sede o escribe su nombre:")
            for i, sede in enumerate(sedes):
                print(f"{i + 1}. {sede}")
            print(f"{len(sedes) + 1}. Añadir nueva sede")
            sede_input = input("Elige un número o escribe el nombre: ").strip()
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
                sede_lower = sede_input.lower()
                if sede_lower in [s.lower() for s in sedes]:
                    sede = sedes[[s.lower() for s in sedes].index(sede_lower)]
                else:
                    sede = create_new_sede(sede_input)
                    if not sede:
                        return

        ips_input = input("Introduce las IPs de los agentes SNMP (separadas por comas): ").strip()
        agent_ips = [ip.strip() for ip in ips_input.split(',') if ip.strip()]
        if not agent_ips:
            print("No se introdujeron IPs válidas.")
            continue

        for agent_ip in agent_ips:
            if not is_valid_ip(agent_ip):
                print(f"IP inválida: {agent_ip}")
                continue

            snmp_version = 2
            mp_model = 1
            community = "GestionGrp"
            hostname = snmp_get(agent_ip, community, "1.3.6.1.2.1.1.5.0", mp_model)
            if hostname:
                print(f"Hostname: {hostname}")
            else:
                print("No se pudo obtener el hostname.")
                hostname = None

            device_alias = input(f"Introduce el alias del dispositivo (sugerencia: {hostname if hostname else 'UNKNOWN'}): ").strip()
            device_alias = device_alias or (hostname if hostname else "UNKNOWN")
            # Aplicar variable booleana para incluir o no la IP en el alias
            if INCLUDE_IP_IN_ALIAS:
                device_alias_all = f"{device_alias}: {agent_ip}"
            else:
                device_alias_all = device_alias

            while True:
                print("\n1. Monitorizar todas las interfaces")
                print("2. Elegir interfaces específicas")
                choice = input("Elige una opción (1 o 2): ").strip()
                if choice == '1':
                    config_content = TEMPLATE_ALL_INTERFACES.format(
                        agent_ip=agent_ip,
                        device_alias=device_alias_all,
                        table_name=sede,
                        snmp_version=snmp_version
                    )
                    icmp_device_alias = device_alias_all
                    break
                elif choice == '2':
                    interfaces = get_interfaces(agent_ip, community, mp_model)
                    if not interfaces:
                        print("No se pudieron obtener interfaces.")
                        continue
                    print("\nInterfaces disponibles:")
                    for i, (if_index, if_descr) in enumerate(interfaces):
                        print(f"{i+1}. {if_descr} (Index: {if_index})")
                    selected_indices = input("Ingresa los números de las interfaces (separados por espacios): ").strip()
                    selected_indices = [int(s) for s in selected_indices.split() if s.isdigit()]
                    selected_interfaces = []
                    for idx in selected_indices:
                        if 1 <= idx <= len(interfaces):
                            if_index, if_descr = interfaces[idx-1]
                            alias = input(f"Introduce el alias para la interfaz '{if_descr}' (o deja en blanco para usar '{device_alias}'): ").strip()
                            alias = alias if alias else device_alias
                            selected_interfaces.append((if_index, if_descr, alias))
                        else:
                            print(f"Número de interfaz inválido: {idx}")
                    if not selected_interfaces:
                        print("No se seleccionaron interfaces válidas.")
                        continue
                    config_content = generate_selected_interfaces_config(
                        agent_ip, sede, selected_interfaces, snmp_version
                    )
                    icmp_device_alias = device_alias_all
                    break
                else:
                    print("Opción inválida.")

            config_path = os.path.join(TELEGRAF_DIR, sede, f"snmp_{agent_ip}.conf")
            icmp_path = os.path.join(TELEGRAF_DIR, sede, f"icmp_{agent_ip}.conf")
            if os.path.exists(config_path) or os.path.exists(icmp_path):
                if not prompt_yes_no("Los archivos ya existen. ¿Sobrescribir? (s/n): "):
                    continue

            try:
                with open(config_path, 'w') as f:
                    f.write(config_content)
                print(f"Configuración SNMP guardada en {config_path}")
                with open(icmp_path, 'w') as f:
                    f.write(TEMPLATE_ICMP.format(agent_ip=agent_ip, table_name=sede, device_alias=icmp_device_alias))
                print(f"Configuración ICMP guardada en {icmp_path}")
            except IOError as e:
                print(f"Error al escribir archivos: {e}")
                continue

        reload_telegraf()
        print("Agentes añadidos.")
        break

def create_new_sede(sede_name=None):
    if not sede_name:
        sede_name = input("Nombre de la nueva sede: ").strip()
    sede_path = os.path.join(TELEGRAF_DIR, sede_name)
    if os.path.exists(sede_path):
        print(f"La sede {sede_name} ya existe.")
        return sede_name
    try:
        os.makedirs(sede_path)
        print(f"Sede {sede_name} creada.")
        return sede_name
    except Exception as e:
        print(f"Error al crear sede: {e}")
        return None

def get_interfaces(agent_ip, community, mp_model):
    oid = '1.3.6.1.2.1.2.2.1.2'
    interfaces = []
    snmp_results = snmp_walk(agent_ip, community, oid, mp_model)
    if not snmp_results:
        return []
    base_oid = (1,3,6,1,2,1,2,2,1,2)
    for oid_tuple, value in snmp_results:
        if oid_tuple[:len(base_oid)] == base_oid and len(oid_tuple) > len(base_oid):
            if_index = oid_tuple[len(base_oid)]
            interfaces.append((str(if_index), value))
    return interfaces

def delete_agent():
    sedes = list_sedes()
    if not sedes:
        print("No hay sedes disponibles.")
        return
    print("\nSelecciona la sede:")
    for i, sede in enumerate(sedes):
        print(f"{i + 1}. {sede}")
    sede_input = input("Elige un número o nombre: ").strip()
    if sede_input.isdigit():
        index = int(sede_input) - 1
        if 0 <= index < len(sedes):
            sede = sedes[index]
        else:
            print("Opción inválida.")
            return
    else:
        sede_lower = sede_input.lower()
        if sede_lower in [s.lower() for s in sedes]:
            sede = sedes[[s.lower() for s in sedes].index(sede_lower)]
        else:
            print("Sede no encontrada.")
            return

    agent_ip = input("IP del agente a eliminar: ").strip()
    if not is_valid_ip(agent_ip):
        print("IP inválida.")
        return

    config_path = os.path.join(TELEGRAF_DIR, sede, f"snmp_{agent_ip}.conf")
    icmp_path = os.path.join(TELEGRAF_DIR, sede, f"icmp_{agent_ip}.conf")
    archivos_eliminados = []
    for path in [config_path, icmp_path]:
        if os.path.exists(path):
            if prompt_yes_no(f"¿Eliminar {path}? (s/n): "):
                try:
                    os.remove(path)
                    archivos_eliminados.append(path)
                    print(f"Eliminado: {path}")
                except IOError as e:
                    print(f"Error al eliminar {path}: {e}")
    if archivos_eliminados:
        reload_telegraf()
        print("Agente eliminado.")
    else:
        print("No se encontraron archivos para eliminar.")

def main():
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
            print("Opción inválida.")

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("Ejecuta el script con sudo.")
        sys.exit(1)
    try:
        import pysnmp
    except ImportError:
        print("Instala 'pysnmp' con 'pip install pysnmp'.")
        sys.exit(1)
    main()
