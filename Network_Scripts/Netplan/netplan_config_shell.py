#!/usr/bin/env python3
# Filename: /etc/netplan-wizard.py
# Descripción: Wizard de configuración de red profesional para plantillas de VM
# -*- coding: utf-8 -*-
import os
import re
import subprocess
from pathlib import Path
import sys
import socket
import struct
import fcntl
import select
import time
import ipaddress
from ipaddress import IPv4Network, IPv4Interface, IPv4Address
import yaml
from typing import List, Dict, Any, Optional

# Configuración de archivos con rutas completas
NETPLAN_DIR = Path("/etc/netplan")
NETPLAN_FILE = NETPLAN_DIR / "00-installer-config.yaml"
BACKUP_FILE = NETPLAN_FILE.with_suffix(".yaml.bak")

# Configuración de colores
class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    END = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"

def print_header():
    print(f"{Colors.BLUE}{'=' * 50}")
    print("  NETPLAN CONFIGURATION WIZARD - ENKRYPTED.AI")
    print(f"{'=' * 50}{Colors.END}\n")

def get_user_input(prompt: str, validator: Optional[callable] = None, error_message: str = "Entrada inválida. Intente de nuevo.", max_attempts: int = 3) -> Optional[str]:
    """Solicita entrada del usuario con validación opcional y número máximo de intentos."""
    for _ in range(max_attempts):
        user_input = input(prompt).strip()
        if validator is None or validator(user_input):
            return user_input
        print(f"{Colors.RED}{error_message}{Colors.END}")
    print(f"{Colors.YELLOW}Máximo de intentos alcanzado.{Colors.END}")
    return None

def validate_ip(ip: str) -> bool:
    cidr_regex = r"^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\/([0-9]|[1-2][0-9]|3[0-2])$"
    return bool(re.match(cidr_regex, ip))

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

def get_network_interfaces() -> list:
    interfaces = []
    for iface in os.listdir("/sys/class/net"):
        if iface == "lo":
            continue
        mac_path = Path(f"/sys/class/net/{iface}/address")
        mac = mac_path.read_text().strip() if mac_path.exists() else "Desconocida"
        ip_output = subprocess.getoutput(f"ip -4 addr show {iface}")
        ips = re.findall(r"inet (\d+\.\d+\.\d+\.\d+\/\d+)", ip_output)
        interfaces.append({
            "name": iface,
            "mac": mac,
            "ips": ips if ips else ["Sin IP"]
        })
    return interfaces

def select_interfaces(interfaces: List[dict]) -> Optional[List[str]]:
    """Permite al usuario seleccionar interfaces de red para configurar."""
    while True:
        print(f"\n{Colors.CYAN}Interfaces de red disponibles:{Colors.END}")
        for i, iface in enumerate(interfaces, 1):
            ip_info = ", ".join(iface['ips'])
            print(f"{i}. {iface['name']} ({iface['mac']}) - IPs: {ip_info}")

        selected = get_user_input(
            "Ingrese los números de las interfaces a configurar (separados por espacios) o 'q' para salir: ",
            lambda x: x.lower() == 'q' or all(s.isdigit() and 1 <= int(s) <= len(interfaces) for s in x.split()),
            "Selección inválida. Ingrese números válidos separados por espacios."
        )

        if selected is None or selected.lower() == 'q':
            return None

        selected_interfaces = [interfaces[int(s) - 1]["name"] for s in selected.split()]
        if not selected_interfaces:
            print(f"{Colors.RED}No se seleccionaron interfaces. Por favor, intente de nuevo.{Colors.END}")
            continue

        confirm = get_user_input(f"Ha seleccionado: {', '.join(selected_interfaces)}. ¿Es correcto? (s/n): ",
                                lambda x: x.lower() in ['s', 'n'])
        if confirm and confirm.lower() == 's':
            return selected_interfaces

def configure_interface(interface: dict) -> dict:
    """Configura una interfaz de red específica."""
    print(f"\n{Colors.YELLOW}Configurando {interface['name']}{Colors.END}")
    print(f"MAC: {interface['mac']}")
    print("IPs asignadas:", ", ".join(interface['ips']))
    config = {}

    use_dhcp = get_user_input("¿Usar DHCP? (s/n): ", lambda x: x.lower() in ['s', 'n'])
    if use_dhcp and use_dhcp.lower() == 's':
        config["dhcp4"] = True
    else:
        while True:
            ip_addr = get_user_input("Ingrese la dirección IP con máscara (ej. 192.168.1.10/24): ",
                                    validate_ip,
                                    "Formato de IP/máscara inválido. Debe ser una dirección IP válida seguida de /XX.")
            gateway = get_user_input("Ingrese la puerta de enlace predeterminada: ",
                                    is_valid_ip,
                                    "IP de puerta de enlace inválida.")

            if ip_addr is None or gateway is None:
                print(f"{Colors.RED}Configuración cancelada debido a entradas inválidas.{Colors.END}")
                return {}

            confirm = get_user_input(f"IP: {ip_addr}, Gateway: {gateway}. ¿Es correcto? (s/n): ",
                                    lambda x: x.lower() in ['s', 'n'])
            if confirm and confirm.lower() == 's':
                break

        config["addresses"] = [ip_addr]
        config["routes"] = [{"to": "default", "via": gateway}]

        if get_user_input("¿Desea añadir rutas estáticas adicionales? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
            added_routes = []
            while True:
                to = get_user_input("Ingrese la red de destino (ej. 192.168.2.0/24) o 'q' para terminar: ",
                                   lambda x: x.lower() == 'q' or is_valid_cidr(x))
                if to is None or to.lower() == 'q':
                    break
                    
                via = get_user_input("Ingrese la puerta de enlace para esta ruta: ", is_valid_ip)
                if via is None:
                    continue
                    
                # Añadir la ruta
                new_route = {"to": to, "via": via}
                config["routes"].append(new_route)
                added_routes.append(new_route)
                
                print(f"{Colors.GREEN}Ruta añadida: Destino {to} vía {via}{Colors.END}")
                
                # Preguntar si quiere añadir más rutas
                if get_user_input("¿Desea añadir otra ruta estática? (s/n): ", lambda x: x.lower() in ['s', 'n']) != 's':
                    break
                    
            # Si se añadieron rutas, mostrar un resumen y preguntar si quiere eliminar alguna
            if added_routes:
                print(f"\n{Colors.CYAN}Rutas estáticas configuradas:{Colors.END}")
                # Mostrar solo las rutas adicionales (no la ruta default)
                routes_to_show = [r for r in config["routes"] if r.get("to") != "default"]
                for i, route in enumerate(routes_to_show, 1):
                    print(f"{i}. Destino: {route['to']}, vía: {route['via']}")
                    
                if get_user_input("\n¿Desea eliminar alguna ruta? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                    while True:
                        route_index = get_user_input(
                            "Ingrese el número de la ruta a eliminar (0 para terminar): ",
                            lambda x: x.isdigit() and 0 <= int(x) <= len(routes_to_show)
                        )
                        
                        if route_index is None or route_index == '0':
                            break
                            
                        idx = int(route_index) - 1
                        deleted_route = routes_to_show[idx]
                        
                        # Buscar y eliminar la ruta del config
                        for i, r in enumerate(config["routes"]):
                            if r == deleted_route:
                                config["routes"].pop(i)
                                routes_to_show.pop(idx)
                                break
                                
                        print(f"{Colors.YELLOW}Ruta eliminada: Destino {deleted_route['to']} vía {deleted_route['via']}{Colors.END}")
                        
                        if not routes_to_show or get_user_input("¿Desea eliminar otra ruta? (s/n): ", lambda x: x.lower() in ['s', 'n']) != 's':
                            break

    if get_user_input("¿Desea configurar nameservers? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
        while True:
            nameservers = get_user_input("Ingrese los nameservers separados por espacios: ").split()
            if all(is_valid_ip(ns) for ns in nameservers):
                config["nameservers"] = {"addresses": nameservers}
                break
            print(f"{Colors.RED}Uno o más nameservers son inválidos. Intente de nuevo.{Colors.END}")

    mtu = get_user_input("Ingrese el MTU (deje en blanco para usar el valor predeterminado): ")
    if mtu:
        if mtu.isdigit() and 500 <= int(mtu) <= 9000:
            config["mtu"] = int(mtu)
        else:
            print(f"{Colors.RED}Valor de MTU inválido. Debe ser un número entre 500 y 9000.{Colors.END}")

    return config

def get_interface_mac(interface):
    """Obtiene la dirección MAC de la interfaz como string"""
    try:
        with open(f"/sys/class/net/{interface}/address", "r") as f:
            return f.read().strip()
    except Exception as e:
        print(f"Error obteniendo MAC: {e}")
        return None

def get_interface_ip(interface):
    """Obtiene la dirección IP de la interfaz"""
    try:
        output = subprocess.check_output(["ip", "-4", "addr", "show", interface]).decode()
        match = re.search(r"inet\s+([0-9.]+)", output)
        if match:
            return match.group(1)
        return None
    except Exception as e:
        print(f"Error obteniendo IP: {e}")
        return None

def check_duplicate_ip(interface, ip_addr):
    """
    Verifica si la IP está duplicada en la red usando solo Python y ping.
    Retorna: (True si hay duplicado, mensaje de estado)
    """
    print(f"\n{Colors.YELLOW}Verificando si la IP {ip_addr} está en uso...{Colors.END}")

    # Obtener dirección IP sin CIDR si está presente
    ip_clean = ip_addr.split('/')[0] if '/' in ip_addr else ip_addr

    try:
        # Método 1: Intentar hacer un bind a la IP para verificar
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)

        try:
            s.bind((ip_clean, 0))
            s.close()
            # Si hacemos bind sin error, la IP podría estar libre, pero aún necesitamos verificar si responde externamente
        except socket.error as e:
            if e.errno == 98:  # Address already in use
                s.close()
                return True, f"La IP {ip_clean} ya está en uso (comprobación de socket)"
            s.close()

        # Método 2: Ping simple como complemento
        ping_cmd = ["ping", "-c", "1", "-W", "1", ip_clean]
        ping_result = subprocess.run(ping_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        if ping_result.returncode == 0:
            return True, f"La IP {ip_clean} responde a ping, posiblemente en uso"
        
        # Si llegamos aquí, la IP parece estar libre
        return False, f"La IP {ip_clean} está libre para usar"

    except Exception as e:
        return False, f"Error verificando IP duplicada: {str(e)}"

def test_connectivity_icmp(target_ip, count=2, timeout=2):
    """
    Prueba conectividad ICMP (ping) con un host específico.
    """
    print(f"\n{Colors.YELLOW}Probando conectividad ICMP con {target_ip}...{Colors.END}")

    try:
        # Usar el comando ping estándar
        ping_cmd = ["ping", "-c", str(count), "-W", str(timeout), target_ip]
        ping_process = subprocess.run(ping_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        if ping_process.returncode == 0:
            # Extraer estadísticas
            stats_match = re.search(r"(\d+) packets transmitted, (\d+) received", ping_process.stdout)
            if stats_match:
                sent, received = stats_match.groups()
                time_match = re.search(r"min/avg/max.*?= ([0-9.]+)/([0-9.]+)/([0-9.]+)", ping_process.stdout)
                if time_match:
                    min_time, avg_time, max_time = time_match.groups()
                    return True, f"Conectividad ICMP confirmada. {received}/{sent} respuestas, tiempo promedio: {avg_time}ms"
                else:
                    return True, f"Conectividad ICMP confirmada. {received}/{sent} respuestas recibidas."
            else:
                return True, "Conectividad ICMP confirmada."
        else:
            # Verificar si hay alguna respuesta parcial
            stats_match = re.search(r"(\d+) packets transmitted, (\d+) received", ping_process.stdout)
            if stats_match and int(stats_match.group(2)) > 0:
                return True, f"Conectividad ICMP parcial. {stats_match.group(2)}/{stats_match.group(1)} respuestas recibidas."
            else:
                return False, f"No se recibió ninguna respuesta ICMP de {target_ip}."

    except Exception as e:
        return False, f"Error en prueba ICMP: {str(e)}"

def test_connectivity(config: dict, configured_interface=None, static_ip=None, gateway=None) -> tuple:
    """
    Verifica la conectividad usando la configuración proporcionada.
    """
    # Pruebas de conectividad según modo
    if configured_interface and static_ip:
        # Modo especial de prueba para IP estática antes de aplicar
        try:
            # Extraer CIDR de la IP estática
            ip_obj = IPv4Interface(static_ip)
            network = ip_obj.network
            ip_addr = str(ip_obj.ip)

            print(f"\n{Colors.CYAN}Realizando verificación de IP duplicada (esto puede tomar unos segundos)...{Colors.END}")
            
            # 1. Verificar si la IP está duplicada - omitir si es una red de prueba o inusual
            is_duplicate = False
            duplicate_msg = "No se pudo determinar si la IP está duplicada"
            
            # Verificar si es una red privada normal - solo hacer la prueba en redes comunes
            common_networks = [
                IPv4Network("10.0.0.0/8"),
                IPv4Network("172.16.0.0/12"),
                IPv4Network("192.168.0.0/16")
            ]
            
            is_common_network = any(network.overlaps(net) for net in common_networks)
            
            if is_common_network:
                is_duplicate, duplicate_msg = check_duplicate_ip(configured_interface, ip_addr)
                
                # Si detectamos que está en uso en una red inusual,
                # podría ser un falso positivo
                if is_duplicate and not any(ip_addr.startswith(prefix) for prefix in ["10.", "172.16.", "192.168.0.", "192.168.1."]):
                    print(f"{Colors.YELLOW}Posible falso positivo en la detección de IP duplicada. Se recomienda verificar manualmente.{Colors.END}")
                    # Ofrecer al usuario la opción de ignorar el resultado
                    if get_user_input("¿Desea ignorar esta advertencia y continuar? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                        is_duplicate = False
                        duplicate_msg += " (ignorado por el usuario)"
                    else:
                        # Usuario no quiere continuar, retornar un código especial
                        return -1, "El usuario decidió no continuar con la IP debido a posible duplicación"
            else:
                duplicate_msg = "Verificación omitida en red no estándar"

            if is_duplicate:
                return False, f"Problema detectado: {duplicate_msg}"

            # 2. Si hay gateway, hacer ping para verificar conectividad
            icmp_success, icmp_msg = False, "No se especificó gateway para pruebas ICMP"
            if gateway:
                # Verificar si el gateway está en la misma red que la IP
                gateway_ip = ipaddress.IPv4Address(gateway)
                if gateway_ip in network:
                    icmp_success, icmp_msg = test_connectivity_icmp(gateway)
                else:
                    icmp_msg = f"Gateway {gateway} no está en la misma red que {static_ip}"

            # Generar mensaje de resultado
            messages = [
                f"Verificación IP duplicada: {duplicate_msg}",
            ]

            if gateway:
                messages.append(f"Prueba ICMP a gateway: {'✅ ' if icmp_success else '❌ '}{icmp_msg}")

            # Consideramos exitosa la prueba si no hay IP duplicada
            # Si hay gateway y está en la misma red, requerimos que ICMP pase
            success = not is_duplicate
            if gateway and ipaddress.IPv4Address(gateway) in network:
                success = success and icmp_success

            return success, "\n".join(messages)

        except Exception as e:
            return False, f"Error en las pruebas de conectividad: {str(e)}"

    else:
        # Modo normal (después de aplicar)
        test_results = []

        # Recorrer todas las interfaces configuradas
        for iface, iface_conf in config["network"]["ethernets"].items():
            # Si es DHCP, simple verificación del estado
            if iface_conf.get("dhcp4", False):
                test_results.append(f"Interfaz {iface}: Configurada en modo DHCP")
                continue

            # Si es estática, pruebas completas
            elif "addresses" in iface_conf:
                try:
                    # Extraer dirección y red
                    address = iface_conf["addresses"][0]
                    ip_obj = IPv4Interface(address)
                    network = ip_obj.network

                    # Prueba ICMP si hay gateway
                    if "routes" in iface_conf:
                        for route in iface_conf["routes"]:
                            if route.get("to") == "default" and "via" in route:
                                gateway = route["via"]
                                icmp_success, icmp_msg = test_connectivity_icmp(gateway)
                                test_results.append(f"ICMP a gateway {gateway}: {'✅ ' if icmp_success else '❌ '}{icmp_msg}")

                                if icmp_success:
                                    # Si el gateway responde, intentar ping a 8.8.8.8 para verificar conectividad externa
                                    external_success, external_msg = test_connectivity_icmp("8.8.8.8", count=1)
                                    test_results.append(f"Conectividad externa: {'✅ ' if external_success else '❌ '}{external_msg}")

                except Exception as e:
                    test_results.append(f"Error en pruebas para {iface}: {e}")

        # Generar mensaje completo
        if test_results:
            return True, "\n".join(test_results)
        else:
            return False, "No se realizaron pruebas de conectividad (sin interfaces estáticas)"

def simulate_config(config: Dict[str, Any]):
    """Simula la aplicación de la configuración."""
    print(f"\n{Colors.CYAN}Simulación de la configuración:{Colors.END}")
    for iface, settings in config["network"]["ethernets"].items():
        print(f"\nInterfaz: {iface}")
        if settings.get("dhcp4"):
            print("  Configuración: DHCP")
        else:
            print(f"  IP: {settings.get('addresses', ['No configurada'])[0]}")
            if "routes" in settings:
                for route in settings["routes"]:
                    if route.get("to") == "default":
                        print(f"  Gateway: {route.get('via', 'No configurado')}")
                        break
        if "nameservers" in settings:
            print(f"  DNS: {', '.join(settings['nameservers'].get('addresses', []))}")
        if "routes" in settings:
            print("  Rutas estáticas:")
            for route in settings["routes"]:
                if route.get("to") != "default":
                    print(f"    Destino: {route['to']}, Vía: {route['via']}")

def show_current_config():
    """Muestra la configuración actual de Netplan."""
    if NETPLAN_FILE.exists():
        print(f"{Colors.CYAN}Configuración actual:{Colors.END}")
        print(NETPLAN_FILE.read_text())
    else:
        print(f"{Colors.YELLOW}No se encontró el archivo de configuración de Netplan.{Colors.END}")

def is_command_available(command):
    """Comprueba si un comando está disponible en el sistema."""
    try:
        subprocess.run(["which", command], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return True
    except subprocess.SubprocessError:
        return False

def restore_backup_config() -> bool:
    """Restaura la configuración de respaldo."""
    try:
        if BACKUP_FILE.exists():
            print("Restaurando configuración anterior...")
            NETPLAN_FILE.write_text(BACKUP_FILE.read_text())
            
            # Intentar aplicar la configuración
            netplan_cmd = "/usr/sbin/netplan"
            if os.path.exists(netplan_cmd):
                subprocess.run([netplan_cmd, "apply"], check=True)
            elif is_command_available("netplan"):
                subprocess.run(["netplan", "apply"], check=True)
            else:
                print(f"{Colors.YELLOW}No se pudo encontrar el comando netplan. La configuración se ha restaurado pero no se ha aplicado.{Colors.END}")
                return False
                
            print(f"{Colors.GREEN}Configuración anterior restaurada con éxito.{Colors.END}")
            return True
        else:
            print(f"{Colors.RED}No se encontró archivo de respaldo.{Colors.END}")
            return False
    except Exception as e:
        print(f"{Colors.RED}Error al restaurar la configuración: {e}{Colors.END}")
        return False

def apply_netplan_config():
    """Aplica la configuración de netplan usando el comando disponible."""
    netplan_cmd = "/usr/sbin/netplan"
    if os.path.exists(netplan_cmd):
        subprocess.run([netplan_cmd, "apply"], check=True)
    elif is_command_available("netplan"):
        subprocess.run(["netplan", "apply"], check=True)
    else:
        raise FileNotFoundError("No se pudo encontrar el comando netplan")

def configure_network():
    print_header()
    print(f"{Colors.YELLOW}Configuración de Red{Colors.END}\n")

    if os.geteuid() != 0:
        print(f"{Colors.RED}Este script debe ejecutarse con privilegios de superusuario (root).{Colors.END}")
        sys.exit(1)

    # Crear directorio netplan si no existe
    os.makedirs(NETPLAN_DIR, exist_ok=True)

    if get_user_input("¿Desea ver la configuración actual? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
        show_current_config()

    test_mode = get_user_input("¿Desea ejecutar en modo de prueba? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's'

    while True:
        interfaces_list = get_network_interfaces()
        if not interfaces_list:
            print(f"{Colors.RED}No se encontraron interfaces de red. Saliendo...{Colors.END}")
            sys.exit(1)

        selected_interfaces = select_interfaces(interfaces_list)
        if selected_interfaces is None:
            print(f"{Colors.YELLOW}Configuración cancelada. Saliendo...{Colors.END}")
            sys.exit(0)

        config = {
            "network": {
                "version": 2,
                "renderer": "networkd",
                "ethernets": {}
            }
        }

        for iface_name in selected_interfaces:
            iface_dict = next((i for i in interfaces_list if i["name"] == iface_name), None)
            if iface_dict:
                iface_config = configure_interface(iface_dict)
                if iface_config:
                    config["network"]["ethernets"][iface_name] = iface_config

        if not config["network"]["ethernets"]:
            print(f"{Colors.RED}No se configuró ninguna interfaz. Volviendo al menú principal.{Colors.END}")
            continue

        # Prueba de conectividad para cada interfaz con IP estática
        interfaces_to_remove = []  # Lista para almacenar interfaces a eliminar
        interfaces_to_reconfigure = []  # Lista para almacenar interfaces a reconfigurar
        
        for iface_name, iface_config in config["network"]["ethernets"].items():
            if not iface_config.get("dhcp4", False) and "addresses" in iface_config:
                static_ip = iface_config["addresses"][0]
                gateway = None
                if "routes" in iface_config:
                    for route in iface_config["routes"]:
                        if route.get("to") == "default" and "via" in route:
                            gateway = route["via"]
                            break

                print(f"\n{Colors.YELLOW}Realizando pruebas de conectividad para {iface_name}...{Colors.END}")
                conn_result, conn_msg = test_connectivity(config, iface_name, static_ip, gateway)

                # Código especial -1 indica que el usuario quiere reconfigurar debido a IP duplicada
                if conn_result == -1:
                    print(f"{Colors.YELLOW}Se necesita reconfigurar la IP para {iface_name}...{Colors.END}")
                    interfaces_to_reconfigure.append(iface_name)
                    continue

                print(f"\n{Colors.CYAN}Resultado de las pruebas para {iface_name}:{Colors.END}")
                print(conn_msg)

                if not conn_result:
                    print(f"\n{Colors.YELLOW}Advertencia: Las pruebas de conectividad indican posibles problemas.{Colors.END}")
                    action = get_user_input("¿Qué desea hacer? (c=continuar, r=reconfigurar, d=descartar): ", lambda x: x.lower() in ['c', 'r', 'd'])
                    if action == 'd':
                        interfaces_to_remove.append(iface_name)
                    elif action == 'r':
                        interfaces_to_reconfigure.append(iface_name)

        # Eliminar interfaces marcadas
        for iface_name in interfaces_to_remove:
            del config["network"]["ethernets"][iface_name]
            print(f"{Colors.YELLOW}Configuración para {iface_name} descartada.{Colors.END}")
        
        # Reconfigurar interfaces marcadas
        for iface_name in interfaces_to_reconfigure:
            print(f"{Colors.CYAN}Reconfigurando interfaz {iface_name}...{Colors.END}")
            iface_dict = next((i for i in interfaces_list if i["name"] == iface_name), None)
            if iface_dict:
                # Eliminar configuración actual
                if iface_name in config["network"]["ethernets"]:
                    del config["network"]["ethernets"][iface_name]
                
                # Solicitar nueva configuración
                iface_config = configure_interface(iface_dict)
                if iface_config:
                    config["network"]["ethernets"][iface_name] = iface_config
                    print(f"{Colors.GREEN}Interfaz {iface_name} reconfigurada correctamente.{Colors.END}")
        
        # Si hay interfaces para reconfigurar, volvemos al loop de verificación
        if interfaces_to_reconfigure:
            continue
        
        # Si se eliminaron todas las interfaces, volver al inicio
        if not config["network"]["ethernets"]:
            print(f"{Colors.RED}Todas las configuraciones fueron descartadas. Volviendo al menú principal.{Colors.END}")
            continue

        # Mostrar configuración generada
        print(f"\n{Colors.CYAN}Configuración de Netplan generada:{Colors.END}")
        yaml_config = yaml.dump(config, default_flow_style=False)
        print(yaml_config)

        # Configuración de hostname
        print(f"\n{Colors.YELLOW}Configuración de Hostname{Colors.END}")
        current_hostname = subprocess.getoutput("hostname")
        print(f"Actual: {Colors.GREEN}{current_hostname}{Colors.END}")
        if get_user_input("¿Cambiar hostname? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
            new_hostname = get_user_input("Nuevo hostname: ")
            if new_hostname:
                confirm = get_user_input(f"Hostname: {new_hostname}. ¿Es correcto? (s/n): ", lambda x: x.lower() in ['s', 'n'])
                if confirm and confirm.lower() == 's':
                    try:
                        subprocess.run(["hostnamectl", "set-hostname", new_hostname], check=True)
                        with open("/etc/hosts", "r+") as f:
                            content = re.sub(
                                r"^127\.0\.1\.1\s.*",
                                f"127.0.1.1\t{new_hostname}",
                                f.read(),
                                flags=re.MULTILINE
                            )
                            f.seek(0)
                            f.write(content)
                            f.truncate()
                        print(f"{Colors.GREEN}Hostname actualizado correctamente.{Colors.END}")
                    except Exception as e:
                        print(f"{Colors.RED}Error al cambiar el hostname: {e}{Colors.END}")

        if test_mode:
            print(f"\n{Colors.CYAN}Modo de prueba: La configuración no se ha aplicado.{Colors.END}")
            simulate_config(config)
            break

        if get_user_input("¿Desea guardar y aplicar esta configuración? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
            print(f"\n{Colors.YELLOW}Preparando configuración...{Colors.END}")
            try:
                # Crear backup
                if NETPLAN_FILE.exists():
                    BACKUP_FILE.write_text(NETPLAN_FILE.read_text())
                    print(f"{Colors.GREEN}Backup de la configuración creado.{Colors.END}")

                # Escribir configuración YAML
                with open(NETPLAN_FILE, "w") as f:
                    yaml.dump(config, f, default_flow_style=False)

                # Aplicar cambios
                print(f"\n{Colors.CYAN}Aplicando nueva configuración...{Colors.END}")
                apply_netplan_config()

                # Verificación de conectividad después de aplicar
                print(f"\n{Colors.YELLOW}Verificando conectividad con la configuración aplicada...{Colors.END}")
                conn_success, conn_msg = test_connectivity(config)

                print(f"\n{Colors.CYAN}Resultado de las pruebas:{Colors.END}")
                print(conn_msg)

                if not conn_success:
                    print(f"\n{Colors.YELLOW}Advertencia: Posibles problemas de conectividad detectados.{Colors.END}")
                    if get_user_input("¿Desea restaurar la configuración anterior? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                        restore_backup_config()
            except Exception as e:
                print(f"{Colors.RED}Error: {e}{Colors.END}")
                if get_user_input("¿Desea restaurar la configuración anterior? (s/n): ", lambda x: x.lower() in ['s', 'n']) == 's':
                    restore_backup_config()
            break
        elif get_user_input("¿Desea volver a configurar? (s/n): ", lambda x: x.lower() in ['s', 'n']) != 's':
            print(f"{Colors.YELLOW}Configuración cancelada. Saliendo...{Colors.END}")
            break

    print(f"\n{Colors.GREEN}Script de configuración de Netplan finalizado{Colors.END}")

def main():
    try:
        configure_network()
    except KeyboardInterrupt:
        print(f"\n{Colors.RED}Operación cancelada por el usuario{Colors.END}")
        sys.exit(1)

if __name__ == "__main__":
    main()
