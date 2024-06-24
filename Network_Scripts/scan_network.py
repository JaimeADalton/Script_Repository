import os
import sys
import asyncio
import ipaddress
import socket
import logging
import argparse
from concurrent.futures import ThreadPoolExecutor
from colorama import init, Fore, Style
import ctypes
from scapy.all import ARP, Ether, srp
from tqdm.asyncio import tqdm as tqdm_asyncio

# Inicializar colorama para colores en Windows
init()

# Configuración del log
logging.basicConfig(filename='network_scan.log', level=logging.INFO,
                    format='%(asctime)s:%(levelname)s:%(message)s')

def print_banner():
    banner = """
    ███████╗███████╗██╗  ██╗    ███████╗ ██████╗ █████╗ ███╗   ██╗
    ██╔════╝██╔════╝██║  ██║    ██╔════╝██╔════╝██╔══██╗████╗  ██║
    ███████╗███████╗███████║    ███████╗██║     ███████║██╔██╗ ██║
    ╚════██║╚════██║██╔══██║    ╚════██║██║     ██╔══██║██║╚██╗██║
    ███████║███████║██║  ██║    ███████║╚██████╗██║  ██║██║ ╚████║
    ╚══════╝╚══════╝╚═╝  ╚═╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝
    """
    print(f"{Fore.CYAN}{banner}{Style.RESET_ALL}")

def check_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except AttributeError:
        return os.geteuid() == 0

def check_root():
    if not check_admin():
        print(f"{Fore.RED}Este script requiere privilegios de administrador para funcionar correctamente.{Style.RESET_ALL}")
        sys.exit(1)

async def check_port(ip, port, timeout=1):
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=timeout)
        writer.close()
        await writer.wait_closed()
        return f"{ip}: {Fore.GREEN}Puerto {port} abierto{Style.RESET_ALL}"
    except (asyncio.TimeoutError, ConnectionRefusedError, OSError):
        return f"{ip}: {Fore.RED}Puerto {port} cerrado o filtrado{Style.RESET_ALL}"

def tcp_connect_scan(ip, port, timeout=1):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return f"{ip}: {Fore.GREEN}Puerto {port} abierto{Style.RESET_ALL}"
    except (socket.timeout, ConnectionRefusedError, OSError):
        return f"{ip}: {Fore.RED}Puerto {port} cerrado o filtrado{Style.RESET_ALL}"

async def multi_scan(ip, port, num_scans=3):
    results = await asyncio.gather(*[check_port(ip, port, timeout=1) for _ in range(num_scans)])
    open_count = sum("abierto" in result for result in results)
    closed_count = sum("cerrado" in result for result in results)
    
    if open_count > num_scans // 2:
        return f"{ip}: {Fore.GREEN}Puerto {port} abierto{Style.RESET_ALL}"
    elif closed_count > num_scans // 2:
        return f"{ip}: {Fore.RED}Puerto {port} cerrado{Style.RESET_ALL}"
    else:
        return f"{ip}: {Fore.YELLOW}Puerto {port} filtrado o no responde{Style.RESET_ALL}"

async def discover_devices(network, timeout=5, retries=2):
    devices = set()
    for _ in range(retries):
        arp_results = arp_scan(network)
        ping_results = await asyncio.gather(*[ping_host(ip) for ip in network.hosts()])
        devices.update(arp_results)
        devices.update([ip for ip in ping_results if ip])
    return list(devices)

async def ping_host(ip):
    try:
        ip_str = str(ip)
        await asyncio.create_subprocess_shell(f"ping -c 1 -W 1 {ip_str}", stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        return ip_str
    except:
        return None

def arp_scan(network, timeout=2, retries=1):
    network_str = str(network)
    for _ in range(retries):
        arp = ARP(pdst=network_str)
        ether = Ether(dst="ff:ff:ff:ff:ff:ff")
        packet = ether/arp
        logging.debug(f"Enviando solicitud ARP a {network_str}")
        result = srp(packet, timeout=timeout, verbose=0)[0]
        logging.debug(f"Recibidas {len(result)} respuestas")
        if result:
            return [received.psrc for sent, received in result]
    return []

async def scan_network(network, max_concurrent=50, timeout=1, executor=None):
    loop = asyncio.get_running_loop()
    devices = await discover_devices(network)
    
    logging.info(f"Se encontraron {len(devices)} dispositivos en la red.")
    print(f"\n{Fore.CYAN}Se encontraron {len(devices)} dispositivos en la red.{Style.RESET_ALL}")
    
    if not devices:
        return []

    semaphore = asyncio.Semaphore(max_concurrent)
    async def scan_with_semaphore(ip, port):
        async with semaphore:
            return await multi_scan(ip, port)
    
    tasks = []
    for ip in devices:
        tasks.extend([scan_with_semaphore(ip, 22), scan_with_semaphore(ip, 3389)])
    
    return await tqdm_asyncio.gather(*tasks, desc="Comprobando puertos en dispositivos")

async def main():
    print_banner()
    check_root()
    
    parser = argparse.ArgumentParser(description="Escanea una red en busca de dispositivos con SSH, HTTP, HTTPS y RDP.")
    parser.add_argument("network", help="Red a escanear (formato: 192.168.1.0/24)")
    parser.add_argument("-c", "--concurrent", type=int, default=50, help="Número máximo de conexiones simultáneas")
    parser.add_argument("-t", "--timeout", type=float, default=0.5, help="Tiempo de espera para conexiones (en segundos)")
    parser.add_argument("-r", "--retries", type=int, default=2, help="Número de reintentos por escaneo")
    args = parser.parse_args()

    print(f"{Fore.YELLOW}Configuración:{Style.RESET_ALL}")
    print(f"  Red: {args.network}")
    print(f"  Conexiones simultáneas: {args.concurrent}")
    print(f"  Timeout: {args.timeout} segundos")
    print()

    try:
        network = ipaddress.ip_network(args.network, strict=False)
    except ValueError:
        logging.error(f"Red inválida: {args.network}")
        print(f"{Fore.RED}Red inválida. Por favor, use el formato correcto.{Style.RESET_ALL}")
        return

    logging.info(f"Iniciando escaneo de la red {network}...")
    print(f"{Fore.CYAN}Iniciando escaneo de la red {network}...{Style.RESET_ALL}")
    
    with ThreadPoolExecutor(max_workers=args.concurrent) as executor:
        results = await scan_network(network, args.concurrent, args.timeout, executor)
    
    print(f"\n{Fore.CYAN}Resultados del escaneo:{Style.RESET_ALL}")
    print("=" * 40)
    
    open_ports = [r for r in results if "abierto" in r]
    closed_ports = [r for r in results if "cerrado" in r]
    filtered_ports = [r for r in results if "filtrado" in r]
    errors = [r for r in results if "Error" in r]
    
    print(f"\n{Fore.GREEN}Puertos abiertos ({len(open_ports)}):{Style.RESET_ALL}")
    for result in open_ports:
        print(result)
        logging.info(result)
    
    print(f"\n{Fore.RED}Puertos cerrados ({len(closed_ports)}):{Style.RESET_ALL}")
    for result in closed_ports:
        print(result)
        logging.info(result)
    
    print(f"\n{Fore.YELLOW}Puertos filtrados ({len(filtered_ports)}):{Style.RESET_ALL}")
    for result in filtered_ports:
        print(result)
        logging.info(result)
    
    print(f"\n{Fore.RED}Errores ({len(errors)}):{Style.RESET_ALL}")
    for result in errors:
        print(result)
        logging.info(result)

    print(f"\n{Fore.CYAN}Resumen del escaneo:{Style.RESET_ALL}")
    print(f"  Total de dispositivos escaneados: {len(results) // 2}")
    print(f"  Puertos abiertos: {len(open_ports)}")
    print(f"  Puertos cerrados: {len(closed_ports)}")
    print(f"  Puertos filtrados: {len(filtered_ports)}")
    print(f"  Errores: {len(errors)}")

if __name__ == "__main__":
    asyncio.run(main())

