import nmap
import asyncio
import time
import os
from aiofiles import open as aio_open
from concurrent.futures import ProcessPoolExecutor
import multiprocessing
import logging
import argparse
import json
from tqdm import tqdm

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

async def read_ips(file_path):
    """Lee las IPs desde un archivo de texto."""
    try:
        async with aio_open(file_path, 'r') as file:
            return [line.strip() for line in await file.readlines() if line.strip()]
    except IOError as e:
        logging.error(f"Error reading IP file: {e}")
        return []

def scan_ip_sync(ip, port_range='1-65535', scan_args='-T5 -n -Pn --min-rate=5000 --max-retries=2', udp_scan=False):
    """Escanea puertos de una IP de forma síncrona utilizando nmap."""
    nm = nmap.PortScanner()
    try:
        nm.scan(ip, port_range, scan_args)
        if ip not in nm.all_hosts():
            return ip, "IP not reachable"
        if 'tcp' not in nm[ip]:
            return ip, "No TCP ports scanned"
        open_ports = [port for port, data in nm[ip]['tcp'].items() if data['state'] == 'open']
        
        if udp_scan:
            nm.scan(ip, port_range, scan_args + ' -sU')
            udp_open_ports = [port for port, data in nm[ip].get('udp', {}).items() if data['state'] == 'open']
            return ip, {'tcp': open_ports, 'udp': udp_open_ports}

        return ip, open_ports
    except nmap.PortScannerError as e:
        return ip, f"Nmap scan error: {str(e)}"
    except Exception as e:
        return ip, f"General error: {str(e)}"

async def scan_ip_pool(ip, pool, semaphore, port_range, scan_args, pbar, timeout=300, udp_scan=False):
    """Gestiona la concurrencia de los escaneos utilizando semáforos y un pool de procesos."""
    async with semaphore:
        try:
            result = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(pool, scan_ip_sync, ip, port_range, scan_args, udp_scan),
                timeout=timeout
            )
        except asyncio.TimeoutError:
            result = (ip, f"Scan timed out after {timeout} seconds")
        pbar.update(1)
        return result

async def process_results(results):
    """Procesa los resultados de los escaneos."""
    open_ports = [(ip, ports) for ip, ports in results if isinstance(ports, list) and ports]
    closed_ports = [ip for ip, ports in results if isinstance(ports, list) and not ports]
    errors = [(ip, error) for ip, error in results if isinstance(error, str)]
    return open_ports, closed_ports, errors

async def save_results(filename, open_ports, closed_ports, errors):
    """Guarda los resultados en un archivo JSON."""
    results = {
        "open_ports": {ip: ports for ip, ports in open_ports},
        "closed_ports": closed_ports,
        "errors": {ip: error for ip, error in errors}
    }
    async with aio_open(filename, 'w') as f:
        await f.write(json.dumps(results, indent=2))

def print_summary(open_ports, closed_ports, errors, total_time, total_ips):
    """Imprime un resumen estadístico del escaneo."""
    logging.info("\nScan Summary:")
    logging.info(f"Total IPs scanned: {total_ips}")
    logging.info(f"IPs with open ports: {len(open_ports)}")
    logging.info(f"IPs with no open ports: {len(closed_ports)}")
    logging.info(f"IPs with errors: {len(errors)}")
    logging.info(f"Total time: {total_time:.2f} seconds")
    logging.info(f"Average time per IP: {total_time/total_ips:.2f} seconds")

async def main(args):
    """Función principal que orquesta la lectura, escaneo y procesamiento de IPs."""
    start_time = time.time()
    
    if not os.path.isfile(args.input):
        logging.error(f"Input file {args.input} does not exist. Exiting.")
        return
    
    ips = await read_ips(args.input)
    if not ips:
        logging.error("No IPs to scan. Exiting.")
        return
    
    max_concurrent = min(multiprocessing.cpu_count() * 4, args.max_concurrent, len(ips))
    semaphore = asyncio.Semaphore(max_concurrent)
    
    logging.info(f"Starting scan of {len(ips)} IPs with max concurrency of {max_concurrent}")
    
    with ProcessPoolExecutor(max_workers=multiprocessing.cpu_count()) as pool:
        with tqdm(total=len(ips), desc="Scanning IPs") as pbar:
            tasks = [scan_ip_pool(ip, pool, semaphore, args.port_range, args.scan_args, pbar, timeout=300, udp_scan=args.udp) for ip in ips]
            results = await asyncio.gather(*tasks)
    
    open_ports, closed_ports, errors = await process_results(results)
    
    logging.info("\nResults:")
    for ip, ports in open_ports:
        logging.info(f"{ip}: Open ports - {', '.join(map(str, ports))}")
    
    logging.info(f"\nIPs with no open ports: {len(closed_ports)}")
    logging.info(f"IPs with errors: {len(errors)}")
    for ip, error in errors:
        logging.error(f"{ip}: {error}")
    
    if args.output:
        await save_results(args.output, open_ports, closed_ports, errors)
        logging.info(f"Results saved to {args.output}")
    
    total_time = time.time() - start_time
    print_summary(open_ports, closed_ports, errors, total_time, len(ips))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Asynchronous Nmap Port Scanner')
    parser.add_argument('-i', '--input', required=True, help='Input file containing IP addresses')
    parser.add_argument('-o', '--output', help='Output file for results (JSON format)')
    parser.add_argument('-p', '--port-range', default='1-65535', help='Port range to scan (default: 1-65535)')
    parser.add_argument('-a', '--scan-args', default='-T5 -n -Pn --min-rate=5000 --max-retries=2', help='Nmap scan arguments')
    parser.add_argument('-m', '--max-concurrent', type=int, default=1000, help='Maximum number of concurrent scans')
    parser.add_argument('-u', '--udp', action='store_true', help='Perform UDP scan in addition to TCP')
    args = parser.parse_args()

    if os.name == 'nt':  # Para Windows
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main(args))
