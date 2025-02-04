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
from ipaddress import IPv4Network, IPv4Interface
import yaml

# Configuración de archivos
NETPLAN_FILE = Path("00-installer-config.yaml")
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

def validate_ip(ip: str) -> bool:
    cidr_regex = r"^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\/([0-9]|[1-2][0-9]|3[0-2])$"
    return bool(re.match(cidr_regex, ip))

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

def configure_interface(interface: dict) -> dict:
    print(f"\n{Colors.YELLOW}Configurando {interface['name']}{Colors.END}")
    print(f"MAC: {interface['mac']}")
    print("IPs asignadas:", ", ".join(interface['ips']))
    print("\n1. DHCP\n2. IP Estática")
    while True:
        choice = input("Seleccione el modo (1/2): ").strip()
        if choice in ("1", "2"):
            break
        print(f"{Colors.RED}Opción inválida!{Colors.END}")
    config = {"dhcp4": choice == "1"}
    if choice == "2":
        while True:
            ip_addr = input("\nIngrese IP/Máscara (ej. 192.168.1.10/24): ").strip()
            if validate_ip(ip_addr):
                break
            print(f"{Colors.RED}Formato inválido! Use CIDR (ej. 192.168.1.10/24){Colors.END}")
        gateway = input("Gateway (dejar vacío para omitir): ").strip()
        dns = input("DNS (separados por espacios, vacío para omitir): ").strip()
        config["addresses"] = [ip_addr]
        if gateway:
            config["routes"] = [{"to": "default", "via": gateway}]
        if dns:
            config["nameservers"] = {"addresses": dns.split()}
    return config

# --- Funciones de verificación de conectividad (script proporcionado) ---

def get_interface_mac(interface):
    """Obtiene la dirección MAC de la interfaz"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ifconf = fcntl.ioctl(
            sock.fileno(),
            0x8927,  # SIOCGIFHWADDR
            struct.pack('256s', interface.encode()[:15])
        )
        return ifconf[18:24]
    except Exception as e:
        print(f"Error obteniendo MAC: {e}")
        return None

def get_interface_ip(interface):
    """Obtiene la dirección IP de la interfaz"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ip = fcntl.ioctl(
            sock.fileno(),
            0x8915,  # SIOCGIFADDR
            struct.pack('256s', interface.encode()[:15])
        )[20:24]
        return socket.inet_ntoa(ip)
    except Exception as e:
        print(f"Error obteniendo IP: {e}")
        return None

def build_arp_packet(src_mac, src_ip, target_ip):
    """Construye un paquete ARP Request válido"""
    eth_header = struct.pack('!6s6sH',
        b'\xff\xff\xff\xff\xff\xff',  # MAC destino (broadcast)
        src_mac,                      # MAC origen
        0x0806                       # Tipo ARP
    )

    arp_payload = struct.pack('!HHBBH6s4s6s4s',
        1,                          # Hardware type (Ethernet)
        0x0800,                     # Protocol type (IPv4)
        6,                          # MAC length
        4,                          # IP length
        1,                          # Operación (ARP Request)
        src_mac,                    # Sender MAC
        socket.inet_aton(src_ip),   # Sender IP
        b'\x00'*6,                  # Target MAC (vacía)
        socket.inet_aton(target_ip) # Target IP
    )

    return eth_header + arp_payload

def test_layer2(interface, network, responses_needed=2):
    """Test de conectividad de capa 2"""
    print(f"\nEscaneando {network} en {interface}...")

    # Crear socket de capa 2 para capturar TODOS los paquetes (ETH_P_ALL)
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
    sock.bind((interface, 0))

    src_mac = get_interface_mac(interface)
    src_ip = get_interface_ip(interface)
    if not src_mac or not src_ip:
        print("Error obteniendo datos de la interfaz")
        return False

    responses = set()
    last_sent = 0
    timeout = 5  # segundos

    # Seleccionar los primeros 10 hosts válidos
    targets = [str(host) for host in network.hosts()][:10]

    start_time = time.time()
    while (time.time() - start_time) < timeout and len(responses) < responses_needed:
        # Enviar ARP cada 0.5 seg.
        if time.time() - last_sent > 0.5:
            for target in targets:
                packet = build_arp_packet(src_mac, src_ip, target)
                sock.send(packet)
            last_sent = time.time()

        # Leer paquetes recibidos
        while True:
            ready, _, _ = select.select([sock], [], [], 0.1)
            if not ready:
                break
            packet = sock.recvfrom(65535)[0]
            if len(packet) >= 42:
                # Verificar que sea ARP reply (opcode 2)
                if packet[12:14] == b'\x08\x06' and packet[20:22] == b'\x00\x02':
                    sender_ip = socket.inet_ntoa(packet[28:32])
                    if sender_ip not in responses:
                        print(f"Respuesta ARP de {sender_ip}")
                        responses.add(sender_ip)
    sock.close()
    return len(responses) >= responses_needed

def test_layer3(gateway, responses_needed=2):
    """Test de conectividad de capa 3 (ICMP)"""
    print(f"\nProbando conectividad con gateway {gateway}...")

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        sock.settimeout(1)

        # Crear paquete ICMP (echo request)
        packet_id = os.getpid() & 0xFFFF
        packet = struct.pack("!BBHHH", 8, 0, 0, packet_id, 1) + b'ABCDEF'

        # Calcular checksum
        checksum = 0
        for i in range(0, len(packet), 2):
            word = (packet[i] << 8) + packet[i+1]
            checksum += word
        checksum = (checksum >> 16) + (checksum & 0xffff)
        checksum = ~checksum & 0xffff

        # Empaquetar con checksum correcto
        packet = struct.pack("!BBHHH", 8, 0, checksum, packet_id, 1) + b'ABCDEF'

        responses = 0
        for _ in range(3):  # 3 intentos
            sock.sendto(packet, (gateway, 0))
            try:
                data, addr = sock.recvfrom(1024)
                if addr[0] == gateway:
                    print(f"Respuesta de ping desde {gateway}")
                    responses += 1
                    if responses >= responses_needed:
                        break
            except socket.timeout:
                continue

        sock.close()
        return responses >= responses_needed
    except Exception as e:
        print(f"Error ICMP: {e}")
        return False

def test_connectivity(config: dict) -> bool:
    """
    Verifica la conectividad usando la configuración proporcionada.
    Si en alguna interfaz estática se definió gateway, utiliza test_layer3 (ICMP).
    Si no, utiliza test_layer2 (ARP) sobre la primera interfaz estática encontrada.
    """
    for iface, iface_conf in config["network"]["ethernets"].items():
        if not iface_conf.get("dhcp4", False) and "addresses" in iface_conf:
            # Si hay gateway definido, usar test_layer3.
            if "routes" in iface_conf:
                for route in iface_conf["routes"]:
                    if route.get("to") == "default" and route.get("via"):
                        gateway = route.get("via")
                        print(f"\nProbando conectividad de capa 3 (ICMP) con gateway {gateway} en la interfaz {iface}...")
                        success = test_layer3(gateway)
                        print("\n✅ Conectividad confirmada" if success else "\n❌ Sin conectividad")
                        return success
            # Si no hay gateway, usar test_layer2.
            address = iface_conf["addresses"][0]
            try:
                ip_intf = IPv4Interface(address)
            except Exception as e:
                print(f"Error al procesar la dirección {address}: {e}")
                continue
            network = ip_intf.network
            print(f"\nProbando conectividad de capa 2 en la interfaz {iface} con red {network}...")
            success = test_layer2(iface, network)
            print("\n✅ Conectividad confirmada" if success else "\n❌ Sin conectividad")
            return success
    print("No se encontró una interfaz estática adecuada para la prueba de conectividad.")
    return False

def configure_network():
    print_header()
    print(f"{Colors.YELLOW}Configuración de Red{Colors.END}\n")

    interfaces = get_network_interfaces()
    if not interfaces:
        print(f"{Colors.RED}No se encontraron interfaces de red!{Colors.END}")
        sys.exit(1)

    config = {
        "network": {
            "version": 2,
            "renderer": "networkd",
            "ethernets": {}
        }
    }

    while True:
        print(f"\n{Colors.CYAN}Interfaces disponibles:{Colors.END}")
        for i, iface in enumerate(interfaces, 1):
            ip_info = ", ".join(iface['ips'])
            print(f"{i}. {iface['name']} ({iface['mac']}) - IPs: {ip_info}")
        try:
            choice = int(input("\nSeleccione interfaz a configurar (número): "))
            if 1 <= choice <= len(interfaces):
                selected = interfaces[choice-1]
            else:
                raise ValueError
        except ValueError:
            print(f"{Colors.RED}Selección inválida!{Colors.END}")
            continue

        config["network"]["ethernets"][selected["name"]] = configure_interface(selected)

        if input("\n¿Configurar otra interfaz? (s/n): ").lower() != "s":
            break

    # Configuración de hostname
    print(f"\n{Colors.YELLOW}Configuración de Hostname{Colors.END}")
    current_hostname = subprocess.getoutput("hostname")
    print(f"Actual: {Colors.GREEN}{current_hostname}{Colors.END}")
    if input("¿Cambiar hostname? (s/n): ").lower() == "s":
        new_hostname = input("Nuevo hostname: ").strip()
        if new_hostname:
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

    print(f"\n{Colors.YELLOW}Preparando configuración...{Colors.END}")
    try:
        # Crear backup
        if NETPLAN_FILE.exists():
            BACKUP_FILE.write_text(NETPLAN_FILE.read_text())

        # Escribir configuración YAML
        with open(NETPLAN_FILE, "w") as f:
            yaml.dump(config, f, default_flow_style=False)

        # Verificación de conectividad antes de aplicar la configuración
        if not test_connectivity(config):
            while True:
                resp = input("¿Desea conservar la nueva configuración a pesar de la falta de conectividad? (m=mantener, r=restaurar): ").strip().lower()
                if resp in ("m", "r"):
                    break
            if resp == "r":
                if BACKUP_FILE.exists():
                    print("Restaurando configuración anterior...")
                    NETPLAN_FILE.write_text(BACKUP_FILE.read_text())
                    subprocess.run(["netplan", "apply"], check=True)
                sys.exit(1)

        # Aplicar cambios
        subprocess.run(["netplan", "apply"], check=True)

    except Exception as e:
        print(f"{Colors.RED}Error: {e}{Colors.END}")
        if BACKUP_FILE.exists():
            print("Restaurando configuración anterior...")
            NETPLAN_FILE.write_text(BACKUP_FILE.read_text())
            subprocess.run(["netplan", "apply"], check=True)
        sys.exit(1)

    print(f"\n{Colors.GREEN}Configuración completada exitosamente!{Colors.END}")
    subprocess.run(["bash"], check=True)

def main():
    try:
        configure_network()
    except KeyboardInterrupt:
        print(f"\n{Colors.RED}Operación cancelada por el usuario{Colors.END}")
        sys.exit(1)

if __name__ == "__main__":
    main()
