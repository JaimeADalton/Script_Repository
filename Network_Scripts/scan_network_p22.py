import os
import sys
from scapy.all import ARP, Ether, srp
import asyncio
import ipaddress
import re
from tqdm.asyncio import tqdm as tqdm_asyncio
import argparse
from concurrent.futures import ThreadPoolExecutor
import logging
from colorama import init, Fore, Style
import ctypes

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
        # Para Windows
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except AttributeError:
        # Para sistemas Unix-like
        return os.geteuid() == 0

def check_root():
    if not check_admin():
        print(f"{Fore.RED}Este script requiere privilegios de administrador para funcionar correctamente.{Style.RESET_ALL}")
        sys.exit(1)

async def check_ssh(ip, timeout=2):
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(ip, 22), timeout=timeout)
        try:
            writer.write(b"SSH-2.0-OpenSSH_8.2p1\r\n")
            await writer.drain()
            banner = await asyncio.wait_for(reader.readline(), timeout=timeout)
            version = re.search(r'SSH-\d+\.\d+-(.+)', banner.decode().strip())
            if version:
                return f"{ip}: {Fore.GREEN}Puerto 22 abierto{Style.RESET_ALL} - Versión SSH: {version.group(1)}"
            else:
                return f"{ip}: {Fore.GREEN}Puerto 22 abierto{Style.RESET_ALL} - No se pudo determinar la versión"
        finally:
            writer.close()
            await writer.wait_closed()
    except asyncio.TimeoutError:
        return f"{ip}: {Fore.YELLOW}Puerto 22 cerrado o filtrado{Style.RESET_ALL}"
    except ConnectionRefusedError:
        return f"{ip}: {Fore.RED}Puerto 22 cerrado{Style.RESET_ALL}"
    except Exception as e:
        logging.error(f"Error al comprobar SSH en {ip}: {str(e)}")
        return f"{ip}: {Fore.RED}Error al comprobar SSH: {str(e)}{Style.RESET_ALL}"

def arp_scan(network):
    arp = ARP(pdst=network)
    ether = Ether(dst="ff:ff:ff:ff:ff:ff")
    packet = ether/arp
    logging.debug(f"Enviando solicitud ARP a {network}")
    result = srp(packet, timeout=5, verbose=0)[0]
    logging.debug(f"Recibidas {len(result)} respuestas")
    return [received.psrc for sent, received in result]

async def scan_network(network, max_concurrent=50, timeout=2, executor=None):
    loop = asyncio.get_running_loop()
    devices = await loop.run_in_executor(executor, arp_scan, network)
    
    logging.info(f"Se encontraron {len(devices)} dispositivos en la red.")
    print(f"\n{Fore.CYAN}Se encontraron {len(devices)} dispositivos en la red.{Style.RESET_ALL}")
    
    if not devices:
        return []

    semaphore = asyncio.Semaphore(max_concurrent)
    async def check_with_semaphore(ip):
        async with semaphore:
            return await check_ssh(ip, timeout)
    
    tasks = [check_with_semaphore(ip) for ip in devices]
    return await tqdm_asyncio.gather(*tasks, desc="Comprobando SSH en dispositivos")

async def main():
    print_banner()
    check_root()
    
    parser = argparse.ArgumentParser(description="Escanea una red en busca de dispositivos con SSH.")
    parser.add_argument("network", help="Red a escanear (formato: 192.168.1.0/24)")
    parser.add_argument("-c", "--concurrent", type=int, default=50, help="Número máximo de conexiones simultáneas")
    parser.add_argument("-t", "--timeout", type=int, default=2, help="Tiempo de espera para conexiones SSH (en segundos)")
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
        results = await scan_network(str(network), args.concurrent, args.timeout, executor)
    
    print(f"\n{Fore.CYAN}Resultados del escaneo:{Style.RESET_ALL}")
    print("=" * 40)
    
    open_ports = [r for r in results if "abierto" in r]
    closed_ports = [r for r in results if "cerrado" in r and "filtrado" not in r]
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
    print(f"  Total de dispositivos escaneados: {len(results)}")
    print(f"  Puertos abiertos: {len(open_ports)}")
    print(f"  Puertos cerrados: {len(closed_ports)}")
    print(f"  Puertos filtrados: {len(filtered_ports)}")
    print(f"  Errores: {len(errors)}")

if __name__ == "__main__":
    asyncio.run(main())

