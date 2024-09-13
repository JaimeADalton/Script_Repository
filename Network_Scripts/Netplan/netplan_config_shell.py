#!/usr/bin/env python3

import os
import subprocess
import ipaddress
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
from datetime import datetime
import yaml
import netifaces
import socket
import struct
import fcntl

# Configuración de logging
logging.basicConfig(
    filename='netplan_config.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

NETPLAN_CONFIG_PATH = Path("/etc/netplan/00-installer-config.yaml")
BACKUP_CONFIG_PATH = NETPLAN_CONFIG_PATH.with_suffix('.yaml.bak')

def run_command(command: List[str], timeout: int = 60) -> Optional[subprocess.CompletedProcess]:
    """Ejecuta un comando de shell de forma segura y devuelve el resultado."""
    try:
        return subprocess.run(command, check=True, text=True, capture_output=True, timeout=timeout)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error al ejecutar el comando: {' '.join(command)}")
        logging.error(f"Salida de error: {e.stderr}")
        return None
    except subprocess.TimeoutExpired:
        logging.error(f"Tiempo de espera agotado al ejecutar el comando: {' '.join(command)}")
        return None

def get_network_interfaces() -> List[str]:
    """Obtiene una lista de interfaces de red disponibles."""
    try:
        return netifaces.interfaces()
    except Exception as e:
        logging.error(f"Error al obtener interfaces de red: {e}")
        return []

def get_current_ip(interface: str) -> str:
    """Obtiene la dirección IP actual de una interfaz."""
    try:
        addrs = netifaces.ifaddresses(interface)
        if netifaces.AF_INET in addrs:
            return addrs[netifaces.AF_INET][0]['addr']
        return "No configurada"
    except Exception as e:
        logging.error(f"Error al obtener IP de {interface}: {e}")
        return "Error"

def is_valid_ip(ip: str) -> bool:
    """Valida si una cadena es una dirección IP válida."""
    try:
        ipaddress.ip_address(ip)
        return True
    except ValueError:
        return False

def is_valid_cidr(cidr: str) -> bool:
    """Valida si una cadena es una dirección CIDR válida."""
    try:
        ipaddress.ip_network(cidr, strict=False)
        return True
    except ValueError:
        return False

def get_user_input(prompt: str, validator: Optional[callable] = None, error_message: str = "Entrada inválida. Intente de nuevo.", max_attempts: int = 3) -> Optional[str]:
    """Solicita entrada del usuario con validación opcional y número máximo de intentos."""
    for _ in range(max_attempts):
        user_input = input(prompt).strip()
        if validator is None or validator(user_input):
            return user_input
        print(error_message)
    logging.warning(f"Máximo de intentos alcanzado para la entrada: {prompt}")
    return None

def select_interfaces(interfaces: List[str]) -> Optional[List[str]]:
    """Permite al usuario seleccionar interfaces de red para configurar."""
    while True:
        print("\nInterfaces de red disponibles:")
        for i, iface in enumerate(interfaces, 1):
            current_ip = get_current_ip(iface)
            print(f"{i}. {iface} - IP actual: {current_ip}")

        selected = get_user_input(
            "Ingrese los números de las interfaces a configurar (separados por espacios) o 'q' para salir: ",
            lambda x: x.lower() == 'q' or all(s.isdigit() and 1 <= int(s) <= len(interfaces) for s in x.split()),
            "Selección inválida. Ingrese números válidos separados por espacios."
        )

        if selected is None or selected.lower() == 'q':
            return None

        selected_interfaces = [interfaces[int(s) - 1] for s in selected.split()]
        if not selected_interfaces:
            print("No se seleccionaron interfaces. Por favor, intente de nuevo.")
            continue

        confirm = get_user_input(f"Ha seleccionado: {', '.join(selected_interfaces)}. ¿Es correcto? (s/n): ",
                                 lambda x: x.lower() in ['s', 'n'])
        if confirm and confirm.lower() == 's':
            return selected_interfaces

def configure_interface(iface: str) -> Dict[str, Any]:
    """Configura una interfaz de red específica."""
    print(f"\nConfigurando {iface}")
    config = {}

    use_dhcp = get_user_input("¿Usar DHCP? (s/n): ", lambda x: x.lower() in ['s', 'n'])
    if use_dhcp and use_dhcp.lower() == 's':
        config["dhcp4"] = True
    else:
        while True:
            ip = get_user_input("Ingrese la dirección IP con máscara (ej. 192.168.1.100/24): ",
                                is_valid_cidr,
                                "Formato de IP/máscara inválido. Debe ser una dirección IP válida seguida de /XX.")
            gateway = get_user_input("Ingrese la puerta de enlace predeterminada: ",
                                     is_valid_ip,
                                     "IP de puerta de enlace inválida.")

            if ip is None or gateway is None:
                print("Configuración cancelada debido a entradas inválidas.")
                return {}

            confirm = get_user_input(f"IP: {ip}, Gateway: {gateway}. ¿Es correcto? (s/n): ",
                                     lambda x: x.lower() in ['s', 'n'])
            if confirm and confirm.lower() == 's':
                break

        config["addresses"] = [ip]
        config["gateway4"] = gateway

        if get_user_input("¿Desea añadir rutas estáticas? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
            config["routes"] = []
            while True:
                to = get_user_input("Ingrese la red de destino (ej. 192.168.2.0/24) o 'q' para terminar: ",
                                    lambda x: x.lower() == 'q' or is_valid_cidr(x))
                if to is None or to.lower() == 'q':
                    break
                via = get_user_input("Ingrese la puerta de enlace para esta ruta: ", is_valid_ip)
                if via is None:
                    continue
                config["routes"].append({"to": to, "via": via})

                if get_user_input("¿Desea eliminar esta ruta? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                    config["routes"].pop()

    if get_user_input("¿Desea configurar nameservers? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
        while True:
            nameservers = get_user_input("Ingrese los nameservers separados por espacios: ").split()
            if all(is_valid_ip(ns) for ns in nameservers):
                config["nameservers"] = {"addresses": nameservers}
                break
            print("Uno o más nameservers son inválidos. Intente de nuevo.")

    while True:
        mtu = get_user_input("Ingrese el MTU (deje en blanco para usar el valor predeterminado): ")
        if not mtu:
            break
        if mtu.isdigit() and 500 <= int(mtu) <= 9000:
            config["mtu"] = int(mtu)
            break
        else:
            print("Valor de MTU inválido. Debe ser un número entre 500 y 9000.")

    return config

def generate_netplan_config(interfaces_config: Dict[str, Dict[str, Any]]) -> str:
    """Genera la configuración de Netplan en formato YAML."""
    config = {
        "network": {
            "version": 2,
            "renderer": "networkd",
            "ethernets": interfaces_config
        }
    }
    return yaml.safe_dump(config, default_flow_style=False, sort_keys=False)

def validate_yaml(config: str) -> bool:
    """Valida que el YAML generado sea correcto y cumpla con la estructura de Netplan."""
    try:
        parsed_config = yaml.safe_load(config)
        if not isinstance(parsed_config, dict) or 'network' not in parsed_config:
            raise ValueError("La configuración no tiene la estructura correcta de Netplan")
        if 'version' not in parsed_config['network'] or parsed_config['network']['version'] != 2:
            raise ValueError("La versión de la configuración de red debe ser 2")
        if 'renderer' not in parsed_config['network']:
            raise ValueError("Falta el campo 'renderer' en la configuración")
        if 'ethernets' not in parsed_config['network']:
            raise ValueError("Falta la configuración de interfaces Ethernet")
        return True
    except (yaml.YAMLError, ValueError) as e:
        logging.error(f"Error en la validación del YAML: {e}")
        print(f"Error en la configuración YAML: {e}")
        return False

def check_ip_conflict(ip: str) -> bool:
    """Verifica si hay conflictos de IP en la red usando sockets en lugar de arping."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind((ip, 0))
        s.close()
        return False
    except socket.error:
        return True

def save_and_apply_config(config: str) -> bool:
    """Guarda y aplica la configuración de Netplan."""
    try:
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        backup_path = NETPLAN_CONFIG_PATH.with_name(f"{NETPLAN_CONFIG_PATH.stem}_{timestamp}{NETPLAN_CONFIG_PATH.suffix}.bak")
        NETPLAN_CONFIG_PATH.rename(backup_path)
        logging.info(f"Backup de la configuración creado: {backup_path}")

        NETPLAN_CONFIG_PATH.write_text(config)
        logging.info("Configuración guardada. Validando configuración...")

        # Validar la configuración
        result = run_command(["netplan", "generate"])
        if result is None:
            logging.error("La validación de la configuración de Netplan falló.")
            print("Error: La configuración de Netplan no es válida. Restaurando configuración anterior...")
            restore_backup_config()
            return False

        # Aplicar la configuración
        print("Aplicando la configuración de red...")
        result = run_command(["netplan", "apply"])
        if result is None:
            logging.error("La aplicación de la configuración de Netplan falló.")
            print("Error: La aplicación de Netplan falló. Restaurando configuración anterior...")
            restore_backup_config()
            return False

        logging.info("Configuración aplicada exitosamente.")
        print("Configuración aplicada exitosamente.")
        return True
    except Exception as e:
        logging.exception("Error al guardar o aplicar la configuración")
        print(f"Error al guardar o aplicar la configuración: {e}")
        restore_backup_config()
        return False

def restore_backup_config() -> bool:
    """Restaura la configuración de respaldo más reciente."""
    try:
        backups = sorted(NETPLAN_CONFIG_PATH.parent.glob(f"{NETPLAN_CONFIG_PATH.stem}_*.bak"), reverse=True)
        if not backups:
            logging.error("No se encontró ningún archivo de respaldo.")
            print("No se encontró ningún archivo de respaldo.")
            return False

        print("Archivos de respaldo disponibles:")
        for i, backup in enumerate(backups, 1):
            print(f"{i}. {backup.name}")

        selection = get_user_input("Seleccione el número del archivo de respaldo a restaurar: ",
                                   lambda x: x.isdigit() and 1 <= int(x) <= len(backups))
        if selection is None:
            print("Selección inválida. Cancelando restauración.")
            return False

        selected_backup = backups[int(selection) - 1]
        selected_backup.rename(NETPLAN_CONFIG_PATH)

        result = run_command(["netplan", "apply"])
        if result:
            logging.info("Configuración de respaldo restaurada y aplicada con éxito.")
            print("Configuración de respaldo restaurada y aplicada con éxito.")
            return True
        else:
            logging.error("Error al aplicar la configuración restaurada.")
            print("Error al aplicar la configuración restaurada.")
            return False
    except Exception as e:
        logging.exception("Error durante la restauración de la configuración")
        print(f"Error durante la restauración de la configuración: {e}")
        return False

def check_connectivity(host: str = "8.8.8.8") -> bool:
    """Verifica la conectividad de red."""
    try:
        socket.create_connection((host, 53), timeout=5)
        return True
    except OSError:
        return False

def show_current_config():
    """Muestra la configuración actual de Netplan."""
    if NETPLAN_CONFIG_PATH.exists():
        print("Configuración actual:")
        print(NETPLAN_CONFIG_PATH.read_text())
    else:
        print("No se encontró el archivo de configuración de Netplan.")

def simulate_config(config: Dict[str, Any]):
    """Simula la aplicación de la configuración."""
    print("\nSimulación de la configuración:")
    for iface, settings in config['network']['ethernets'].items():
        print(f"\nInterfaz: {iface}")
        if settings.get('dhcp4'):
            print("  Configuración: DHCP")
        else:
            print(f"  IP: {settings.get('addresses', ['No configurada'])[0]}")
            print(f"  Gateway: {settings.get('gateway4', 'No configurado')}")
        if 'nameservers' in settings:
            print(f"  DNS: {', '.join(settings['nameservers'].get('addresses', []))}")
        if 'routes' in settings:
            print("  Rutas estáticas:")
            for route in settings['routes']:
                print(f"    Destino: {route['to']}, Vía: {route['via']}")

def main():
    """Función principal del script."""
    logging.info("Iniciando el script de configuración de Netplan")
    print("Bienvenido al configurador de red Netplan")
    print("=" * 50)

    if os.geteuid() != 0:
        print("Este script debe ejecutarse con privilegios de superusuario (root).")
        logging.error("El script se ejecutó sin privilegios de root")
        return

    if get_user_input("¿Desea ver la configuración actual? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
        show_current_config()

    test_mode = get_user_input("¿Desea ejecutar en modo de prueba? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's'

    while True:
        interfaces = get_network_interfaces()
        if not interfaces:
            logging.error("No se encontraron interfaces de red.")
            print("No se encontraron interfaces de red. Saliendo...")
            return

        selected_interfaces = select_interfaces(interfaces)
        if selected_interfaces is None:
            logging.info("Configuración cancelada por el usuario.")
            print("Configuración cancelada. Saliendo...")
            return

        interfaces_config = {}
        for iface in selected_interfaces:
            config = configure_interface(iface)
            if config:
                interfaces_config[iface] = config

        if not interfaces_config:
            print("No se configuró ninguna interfaz. Volviendo al menú principal.")
            continue

        netplan_config = generate_netplan_config(interfaces_config)

        if not validate_yaml(netplan_config):
            continue

        print("\nConfiguración de Netplan generada:")
        print(netplan_config)

        for iface, config in interfaces_config.items():
            if "addresses" in config:
                ip = config["addresses"][0].split('/')[0]
                if check_ip_conflict(ip):
                    print(f"Advertencia: La IP {ip} puede estar en uso en la red.")

        if test_mode:
            print("Modo de prueba: La configuración no se ha aplicado.")
            simulate_config(yaml.safe_load(netplan_config))
            break

        if get_user_input("¿Desea guardar y aplicar esta configuración? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
            if save_and_apply_config(netplan_config):
                if check_connectivity():
                    logging.info("Conectividad verificada con éxito.")
                    print("Conectividad verificada con éxito.")
                else:
                    logging.warning("No se pudo verificar la conectividad.")
                    print("Advertencia: No se pudo verificar la conectividad.")

                if get_user_input("¿Desea restaurar la configuración anterior? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                    restore_backup_config()
            else:
                print("Hubo un error al aplicar la configuración.")
                if get_user_input("¿Desea restaurar la configuración anterior? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                    restore_backup_config()
            break
        elif get_user_input("¿Desea volver a configurar? (s/n): ", lambda x: x.lower() in ['s', 'n']) != 's':
            logging.info("Configuración cancelada por el usuario.")
            print("Configuración cancelada. Saliendo...")
            break

    logging.info("Script de configuración de Netplan finalizado")

if __name__ == "__main__":
    main()
