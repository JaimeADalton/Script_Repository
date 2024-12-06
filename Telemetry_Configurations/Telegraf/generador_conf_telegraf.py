#!/usr/bin/env python3
import os
import re
import sys
import psutil
import signal
from pysnmp.hlapi import *

# -----------------------------------------------------------------------------
# CONFIGURACIÓN BÁSICA
# -----------------------------------------------------------------------------
TELEGRAF_DIR = '/etc/telegraf/telegraf.d'
COMMUNITY = 'GestionGrp'
SNMP_VERSION = 2  # Versión SNMPv2c
MP_MODEL = 1

# Plantillas de configuración para Telegraf:
# Estas plantillas crean entradas para el input SNMP y ICMP, utilizando tags
# coherentes (device_id, sede, source, etc.) que permitirán dashboards dinámicos.

# Plantilla SNMP (todas las interfaces)
TEMPLATE_SNMP_ALL = """
[[inputs.snmp]]
  name_override = "snmp_interfaces"
  agents = ["{agent_ip}"]
  version = {snmp_version}
  community = "{community}"
  interval = "30s"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    device_id = "{device_id}"
    sede = "{sede}"

  # Etiqueta hostname obtenida por SNMP
  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
    is_tag = true

  # Tabla de interfaces (ifTable): obtiene automáticamente todas las interfaces
  [[inputs.snmp.table]]
    name = "interfaces"
    inherit_tags = ["hostname"]
    oid = "IF-MIB::ifTable"

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

# Plantilla SNMP (interfaces seleccionadas manualmente)
TEMPLATE_SNMP_SELECTED = """
[[inputs.snmp]]
  name_override = "snmp_interfaces"
  agents = ["{agent_ip}"]
  version = {snmp_version}
  community = "{community}"
  interval = "30s"
  timeout = "5s"
  retries = 1
  agent_host_tag = "source"

  [inputs.snmp.tags]
    device_id = "{device_id}"
    sede = "{sede}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
    is_tag = true
{interface_fields}
"""

# Plantilla ICMP
TEMPLATE_ICMP = """
[[inputs.ping]]
  urls = ["{agent_ip}"]
  count = 1
  interval = "5s"
  name_override = "icmp_ping"

  [inputs.ping.tags]
    device_id = "{device_id}"
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
    """Lista los subdirectorios en TELEGRAF_DIR que representan sedes (clientes)."""
    try:
        sedes = [
            f for f in os.listdir(TELEGRAF_DIR)
            if os.path.isdir(os.path.join(TELEGRAF_DIR, f))
        ]
        sedes.sort()
        return sedes
    except FileNotFoundError:
        print(f"ERROR: El directorio {TELEGRAF_DIR} no existe. Por favor créalo o ajusta TELEGRAF_DIR.")
        return []


def is_valid_ip(ip):
    """Valida el formato IPv4 usando una expresión regular."""
    pattern = re.compile(r'^((25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(25[0-5]|2[0-4]\d|[01]?\d?\d)$')
    return bool(pattern.match(ip))


def prompt_yes_no(prompt):
    """Pregunta al usuario sí/no, forzando una respuesta válida."""
    while True:
        response = input(prompt).strip().lower()
        if response in ['s','y','si','sí']:
            return True
        elif response in ['n','no']:
            return False
        else:
            print("Respuesta inválida. Por favor, introduce 's' o 'n'.")


def snmp_get(ip, community, oid, version):
    """Realiza una consulta SNMP GET a un OID específico y devuelve el resultado."""
    try:
        iterator = getCmd(
            SnmpEngine(),
            CommunityData(community, mpModel=version),
            UdpTransportTarget((ip, 161), timeout=5, retries=1),
            ContextData(),
            ObjectType(ObjectIdentity(oid))
        )

        error_indication, error_status, error_index, var_binds = next(iterator)

        if error_indication or error_status:
            return None
        else:
            if var_binds:
                return var_binds[0][1].prettyPrint()
            else:
                return None
    except Exception:
        return None


def snmp_walk(ip, community, oid, version):
    """Realiza una consulta SNMP WALK para obtener múltiples valores."""
    results = []
    try:
        for (error_indication,
             error_status,
             error_index,
             var_binds) in nextCmd(SnmpEngine(),
                                   CommunityData(community, mpModel=version),
                                   UdpTransportTarget((ip, 161), timeout=5, retries=1),
                                   ContextData(),
                                   ObjectType(ObjectIdentity(oid)),
                                   lexicographicMode=False):
            if error_indication or error_status:
                break
            else:
                for var_bind in var_binds:
                    oid_obj, value = var_bind
                    oid_tuple = oid_obj.asTuple()
                    results.append((oid_tuple, value.prettyPrint()))
        return results
    except Exception:
        return []


def get_hostname_snmp(ip):
    """Obtiene el hostname vía SNMP usando el OID sysName."""
    oid_hostname = '1.3.6.1.2.1.1.5.0'
    hostname = snmp_get(ip, COMMUNITY, oid_hostname, MP_MODEL)
    return hostname


def get_interfaces_snmp(ip):
    """Obtiene la lista de interfaces (ifDescr) mediante SNMP WALK."""
    oid = '1.3.6.1.2.1.2.2.1.2'  # ifDescr
    result = snmp_walk(ip, COMMUNITY, oid, MP_MODEL)
    if not result:
        return []
    base_oid = (1,3,6,1,2,1,2,2,1,2)
    interfaces = []
    for oid_tuple, value in result:
        if oid_tuple[:len(base_oid)] == base_oid and len(oid_tuple) > len(base_oid):
            if_index = oid_tuple[len(base_oid)]
            interfaces.append((if_index, value))
    return interfaces


def create_sede(sede_name=None):
    """Crea una nueva sede (directorio) si no existe."""
    if sede_name is None:
        sede_name = input("Introduce el nombre de la nueva sede (cliente): ").strip()
    if not sede_name:
        print("Nombre de sede inválido.")
        return None
    sede_path = os.path.join(TELEGRAF_DIR, sede_name)
    if os.path.exists(sede_path):
        print(f"La sede '{sede_name}' ya existe, no se crea.")
        return sede_name
    try:
        os.makedirs(sede_path, exist_ok=True)
        print(f"Sede '{sede_name}' creada exitosamente.")
        return sede_name
    except Exception as e:
        print(f"Error al crear la sede {sede_name}: {e}")
        return None


def reload_telegraf():
    """Recarga el proceso de Telegraf enviando SIGHUP, para que lea nuevos .conf."""
    for proc in psutil.process_iter(['pid', 'name']):
        if proc.info['name'] == 'telegraf':
            try:
                os.kill(proc.info['pid'], signal.SIGHUP)
                print("Telegraf recargado exitosamente. Ahora Grafana verá las nuevas métricas.")
                return
            except Exception as e:
                print(f"Error al recargar Telegraf: {e}")
                return
    print("No se encontró el proceso Telegraf en ejecución. Asegúrate de que Telegraf esté instalado y corriendo.")


def generate_snmp_config_all_interfaces(agent_ip, sede, device_id):
    """Genera la configuración SNMP para monitorizar todas las interfaces de un dispositivo."""
    return TEMPLATE_SNMP_ALL.format(
        agent_ip=agent_ip,
        snmp_version=SNMP_VERSION,
        community=COMMUNITY,
        device_id=device_id,
        sede=sede
    )


def generate_icmp_config(agent_ip, sede, device_id):
    """Genera la configuración ICMP para monitorizar latencia y pérdida de paquetes."""
    return TEMPLATE_ICMP.format(
        agent_ip=agent_ip,
        device_id=device_id,
        sede=sede
    )


def generate_snmp_config_selected_interfaces(agent_ip, sede, device_id, selected_interfaces):
    """Genera la configuración SNMP para un conjunto limitado de interfaces seleccionadas por el usuario."""
    field_lines = ""
    for if_index, if_descr in selected_interfaces:
        # Sanitizamos el nombre de la interfaz para usarlo en el campo:
        safe_if_descr = re.sub(r'\W+', '_', if_descr)
        field_lines += f"""
  [[inputs.snmp.field]]
    name = "ifHCInOctets_{safe_if_descr}"
    oid = "IF-MIB::ifHCInOctets.{if_index}"

  [[inputs.snmp.field]]
    name = "ifHCOutOctets_{safe_if_descr}"
    oid = "IF-MIB::ifHCOutOctets.{if_index}"
"""
    return TEMPLATE_SNMP_SELECTED.format(
        agent_ip=agent_ip,
        snmp_version=SNMP_VERSION,
        community=COMMUNITY,
        device_id=device_id,
        sede=sede,
        interface_fields=field_lines
    )


def make_device_id(alias, ip, sede):
    """Genera un device_id único a partir de alias, sede e ip."""
    alias_clean = re.sub(r'\s+', '_', alias.lower())
    sede_clean = re.sub(r'\s+', '_', sede.lower())
    ip_clean = ip.replace('.', '_')
    return f"{alias_clean}_{sede_clean}_{ip_clean}"


def check_device_id_exists(sede, device_id):
    """Verifica si un device_id ya existe en los archivos de configuración de la sede."""
    sede_path = os.path.join(TELEGRAF_DIR, sede)
    if not os.path.isdir(sede_path):
        return False
    for fname in os.listdir(sede_path):
        if fname.endswith(".conf"):
            try:
                with open(os.path.join(sede_path, fname), 'r') as f:
                    content = f.read()
                    if f"device_id = \"{device_id}\"" in content:
                        return True
            except:
                continue
    return False


def write_config_file(path, content):
    """Escribe el contenido en un archivo. Si ya existe, solicita confirmación para sobrescribir."""
    if os.path.exists(path):
        print(f"\nEl archivo {path} ya existe, se procederá a sobrescribirlo.")
        if not prompt_yes_no("¿Deseas continuar con la sobrescritura? (s/n): "):
            print("Operación cancelada por el usuario.")
            return False
    try:
        with open(path, 'w') as f:
            f.write(content)
        print(f"Archivo guardado correctamente: {path}")
        return True
    except IOError as e:
        print(f"Error al escribir el archivo {path}: {e}")
        return False


def select_sede():
    """Permite al usuario seleccionar una sede existente o crear una nueva."""
    while True:
        sedes = list_sedes()
        if not sedes:
            print("No hay sedes (clientes) disponibles actualmente.")
            if prompt_yes_no("¿Deseas crear una nueva sede? (s/n): "):
                sede = create_sede()
                if sede is None:
                    print("No se pudo crear la sede. Inténtalo de nuevo.")
                    continue
                return sede
            else:
                return None
        else:
            print("\nSelecciona una sede existente o crea una nueva:")
            for i, s in enumerate(sedes, start=1):
                print(f"{i}. {s}")
            print(f"{len(sedes)+1}. Crear nueva sede")

            sede_input = input("Elige un número o escribe el nombre de la sede: ").strip()
            if sede_input.isdigit():
                idx = int(sede_input)
                if 1 <= idx <= len(sedes):
                    return sedes[idx-1]
                elif idx == len(sedes)+1:
                    return create_sede()
                else:
                    print("Opción inválida, intenta nuevamente.")
            else:
                sede_lower = sede_input.lower()
                sedes_lower = [s.lower() for s in sedes]
                if sede_lower in sedes_lower:
                    return sedes[sedes_lower.index(sede_lower)]
                else:
                    print(f"La sede '{sede_input}' no existe.")
                    if prompt_yes_no("¿Deseas crear esta sede? (s/n): "):
                        return create_sede(sede_input)
    return None


def add_agent():
    """
    Añade un nuevo agente (dispositivo) a una sede específica.
    Permite configurar SNMP (todas o algunas interfaces) e ICMP.
    """
    print("\n--- Añadir Agente ---")
    sede = select_sede()
    if not sede:
        print("No se pudo seleccionar o crear una sede. Abortando la operación.")
        return

    ips_input = input("Introduce las IPs de los agentes SNMP, separadas por comas: ").strip()
    agent_ips = [ip.strip() for ip in ips_input.split(',') if ip.strip()]

    if not agent_ips:
        print("No se introdujeron IPs válidas. Abortando operación.")
        return

    for agent_ip in agent_ips:
        if not is_valid_ip(agent_ip):
            print(f"La IP '{agent_ip}' no es válida, se omitirá.")
            continue

        # Sugerir alias a partir del hostname SNMP (si existe)
        hostname = get_hostname_snmp(agent_ip)
        if not hostname:
            hostname = "sin_hostname"
            print(f"No se pudo obtener el hostname vía SNMP para {agent_ip}. Se sugiere alias '{hostname}'.")
        else:
            print(f"Hostname SNMP capturado para {agent_ip}: {hostname}")

        device_alias = input(f"Introduce el alias del dispositivo (ENTER para usar '{hostname}'): ").strip()
        if not device_alias:
            device_alias = hostname

        # Generar device_id único
        device_id = make_device_id(device_alias, agent_ip, sede)
        base_device_id = device_id
        counter = 1

        # Resolver conflictos de device_id
        while check_device_id_exists(sede, device_id):
            print(f"El device_id '{device_id}' ya existe en la sede '{sede}'.")
            if prompt_yes_no("¿Deseas cambiar el alias? (s/n): "):
                device_alias = input("Introduce un alias único: ").strip()
                if not device_alias:
                    device_alias = hostname
                device_id = make_device_id(device_alias, agent_ip, sede)
                base_device_id = device_id
            else:
                device_id = f"{base_device_id}_{counter}"
                counter += 1

        # Elegir monitoreo SNMP (todas las interfaces o seleccionadas)
        while True:
            print("\nOpciones de monitoreo SNMP:")
            print("1. Monitorizar todas las interfaces del dispositivo")
            print("2. Seleccionar interfaces específicas")
            opt = input("Elige una opción (1 o 2): ").strip()
            if opt == '1':
                snmp_config_content = generate_snmp_config_all_interfaces(agent_ip, sede, device_id)
                break
            elif opt == '2':
                interfaces = get_interfaces_snmp(agent_ip)
                if not interfaces:
                    print("No se pudieron obtener interfaces. Se usará monitoreo de todas las interfaces.")
                    snmp_config_content = generate_snmp_config_all_interfaces(agent_ip, sede, device_id)
                    break
                else:
                    print("\nInterfaces disponibles para su selección:")
                    for i, (if_index, if_descr) in enumerate(interfaces, start=1):
                        print(f"{i}. {if_descr} (Index: {if_index})")

                    selected_indices_input = input("Ingresa los números de las interfaces a monitorizar (separados por espacio): ").strip()
                    selected_indices = [x for x in selected_indices_input.split() if x.isdigit()]
                    selected_indices = [int(x) for x in selected_indices]
                    selected_interfaces = []
                    for idx in selected_indices:
                        if 1 <= idx <= len(interfaces):
                            if_index, if_descr = interfaces[idx-1]
                            selected_interfaces.append((if_index, if_descr))
                        else:
                            print(f"Índice {idx} inválido, se ignora.")

                    if not selected_interfaces:
                        print("No se seleccionaron interfaces válidas, intenta nuevamente o elige la opción de todas las interfaces.")
                        continue
                    snmp_config_content = generate_snmp_config_selected_interfaces(agent_ip, sede, device_id, selected_interfaces)
                    break
            else:
                print("Opción inválida. Por favor elige 1 o 2.")

        # Generar configuración ICMP (latencia, pérdida de paquetes)
        icmp_config_content = generate_icmp_config(agent_ip, sede, device_id)

        # Guardar los archivos en la sede correspondiente
        sede_path = os.path.join(TELEGRAF_DIR, sede)
        snmp_filename = f"snmp_{device_id}.conf"
        icmp_filename = f"icmp_{device_id}.conf"
        snmp_path = os.path.join(sede_path, snmp_filename)
        icmp_path = os.path.join(sede_path, icmp_filename)

        print(f"\nCreando archivos de configuración para el dispositivo con device_id '{device_id}'...")
        if not write_config_file(snmp_path, snmp_config_content):
            continue
        if not write_config_file(icmp_path, icmp_config_content):
            # Si falla escritura de ICMP, revertimos el SNMP
            if os.path.exists(snmp_path):
                os.remove(snmp_path)
            continue

        print(f"Agente añadido exitosamente: IP={agent_ip}, alias='{device_alias}', device_id='{device_id}'.")
        print("Este dispositivo ahora se reflejará en las variables de Grafana, permitiendo dashboards dinámicos.")

    # Recargar Telegraf para que tome los nuevos archivos de configuración
    reload_telegraf()


def delete_agent():
    """
    Elimina un agente (dispositivo) existente. Busca por sede y IP.
    Pide confirmación antes de borrar archivos, y luego recarga Telegraf.
    """
    print("\n--- Eliminar Agente ---")
    sedes = list_sedes()
    if not sedes:
        print("No hay sedes disponibles. No se puede eliminar ningún agente.")
        return

    print("\nSelecciona la sede del agente que deseas eliminar:")
    for i, s in enumerate(sedes, start=1):
        print(f"{i}. {s}")
    sede_input = input("Elige un número o escribe el nombre de la sede: ").strip()

    if sede_input.isdigit():
        idx = int(sede_input)
        if 1 <= idx <= len(sedes):
            sede = sedes[idx-1]
        else:
            print("Opción inválida.")
            return
    else:
        sede_lower = sede_input.lower()
        sedes_lower = [s.lower() for s in sedes]
        if sede_lower in sedes_lower:
            sede = sedes[sedes_lower.index(sede_lower)]
        else:
            print("La sede especificada no existe. Abortando.")
            return

    agent_ip = input("Introduce la IP del agente a eliminar: ").strip()
    if not is_valid_ip(agent_ip):
        print("IP inválida. Abortando eliminación.")
        return

    # Buscar device_ids que correspondan a esa IP
    sede_path = os.path.join(TELEGRAF_DIR, sede)
    if not os.path.isdir(sede_path):
        print(f"La sede {sede} no existe en el sistema de ficheros. Abortando.")
        return

    posibles = []
    for fname in os.listdir(sede_path):
        if fname.endswith(".conf"):
            path = os.path.join(sede_path, fname)
            try:
                with open(path, 'r') as f:
                    content = f.read()
                if f"= \"{agent_ip}\"" in content:
                    match = re.search(r'device_id\s*=\s*"([^"]+)"', content)
                    if match:
                        dev_id = match.group(1)
                        if dev_id not in posibles:
                            posibles.append(dev_id)
            except:
                continue

    if not posibles:
        print(f"No se encontró ningún dispositivo con IP {agent_ip} en la sede {sede}.")
        return

    if len(posibles) > 1:
        print("Se encontraron múltiples device_id para esa IP:")
        for i, pid in enumerate(posibles, start=1):
            print(f"{i}. {pid}")
        sel = input("Selecciona el número del device_id a eliminar: ").strip()
        if sel.isdigit():
            idx = int(sel)
            if 1 <= idx <= len(posibles):
                device_id = posibles[idx-1]
            else:
                print("Opción inválida.")
                return
        else:
            print("Opción inválida.")
            return
    else:
        device_id = posibles[0]

    # Eliminar todos los .conf asociados a ese device_id
    deleted_any = False
    for fname in os.listdir(sede_path):
        if fname.endswith(".conf"):
            path = os.path.join(sede_path, fname)
            with open(path, 'r') as f:
                content = f.read()
            if f"device_id = \"{device_id}\"" in content:
                # Confirmar con el usuario
                if prompt_yes_no(f"¿Seguro que deseas eliminar {path}? (s/n): "):
                    try:
                        os.remove(path)
                        print(f"Archivo eliminado: {path}")
                        deleted_any = True
                    except Exception as e:
                        print(f"Error al eliminar {path}: {e}")

    if deleted_any:
        reload_telegraf()
        print(f"Agente con device_id {device_id} eliminado exitosamente.")
    else:
        print("No se eliminó ningún archivo, es posible que el agente ya no exista.")


def main():
    """
    Menú principal del script.
    Requiere ejecutar con privilegios, ya que escribe en /etc/telegraf/telegraf.d/
    """
    # Verificar permisos (se asume que es necesario root o sudo)
    if os.geteuid() != 0:
        print("Este script debe ejecutarse con permisos de superusuario (sudo).")
        sys.exit(1)

    # Verificar directorio principal de Telegraf
    if not os.path.isdir(TELEGRAF_DIR):
        print(f"El directorio {TELEGRAF_DIR} no existe. Por favor créalo antes de continuar.")
        sys.exit(1)

    print("Bienvenido al sistema de gestión de agentes SNMP/ICMP para Telegraf.")
    print("Este script te ayudará a añadir o eliminar configuraciones SNMP/ICMP en telegraf.d,")
    print("permitiendo a Grafana construir dashboards dinámicos y profesionales.")

    while True:
        print("\n--- MENÚ PRINCIPAL ---")
        print("1. Añadir agente")
        print("2. Eliminar agente")
        print("3. Salir")

        choice = input("Elige una opción: ").strip()
        if choice == '1':
            add_agent()
        elif choice == '2':
            delete_agent()
        elif choice == '3':
            print("Saliendo del script. ¡Hasta luego!")
            sys.exit(0)
        else:
            print("Opción inválida. Por favor elige 1, 2 o 3.")


if __name__ == "__main__":
    # Verificar si pysnmp está instalado
    try:
        import pysnmp
    except ImportError:
        print("La librería 'pysnmp' no está instalada. Por favor ejecuta: pip install pysnmp.")
        sys.exit(1)

    # Ejecutar el menú principal
    main()
