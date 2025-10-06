#!/usr/bin/python3
import subprocess
import csv
from concurrent.futures import ThreadPoolExecutor
from os import system
import sys
from prettytable import PrettyTable

# Colores para la impresión en consola
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
END = "\033[0m"

def cleaner():
    system('clear')

def read_ips(filename="ip.txt"):
    try:
        with open(filename, "r") as file:
            return file.read().splitlines()
    except FileNotFoundError:
        print("Error: No se encontró el archivo '{}'".format(filename))
        return []

def ping_health(ip, count=15):
    """
    Realiza múltiples pings y analiza la salud de la conexión
    Retorna: (disponible, paquetes_perdidos, latencia_promedio)
    """
    result = subprocess.run(
        ['ping', '-c', str(count), '-W', '1', ip],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    if result.returncode != 0:
        return False, 100, 0

    # Parsear la salida del ping
    output = result.stdout

    # Extraer pérdida de paquetes
    packet_loss = 0
    for line in output.split('\n'):
        if 'packet loss' in line:
            try:
                packet_loss = int(line.split('%')[0].split()[-1])
            except:
                packet_loss = 0
            break

    # Extraer latencia promedio
    avg_latency = 0
    for line in output.split('\n'):
        if 'rtt min/avg/max/mdev' in line or 'round-trip' in line:
            try:
                parts = line.split('=')[1].strip().split('/')
                avg_latency = float(parts[1])
            except:
                avg_latency = 0
            break

    return True, packet_loss, avg_latency

def get_ping_status(available, packet_loss, latency):
    """
    Determina el estado de salud del ping
    """
    if not available:
        return f"{RED}DOWN{END}", RED
    elif packet_loss == 0 and latency < 50:
        return f"{GREEN}Excelente (0% loss, {latency:.1f}ms){END}", GREEN
    elif packet_loss == 0 and latency < 100:
        return f"{GREEN}Buena (0% loss, {latency:.1f}ms){END}", GREEN
    elif packet_loss > 0 and packet_loss < 20:
        return f"{YELLOW}Regular ({packet_loss}% loss, {latency:.1f}ms){END}", YELLOW
    elif packet_loss >= 20 and packet_loss < 50:
        return f"{YELLOW}Mala ({packet_loss}% loss, {latency:.1f}ms){END}", YELLOW
    else:
        return f"{RED}Crítica ({packet_loss}% loss, {latency:.1f}ms){END}", RED

def snmp_get(community, ip):
    command = ["timeout", "0.9", "snmpget", "-v2c", "-c", community, ip, "SNMPv2-MIB::sysName.0"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def write_results_to_csv(results):
    with open('resultados.csv', 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["IP", "ICMP Estado", "Pérdida Paquetes (%)", "Latencia (ms)", "SNMP public", "SNMP GestionGrp"])
        for result in results:
            writer.writerow(result)

def test_ip(ip):
    # Test de salud ICMP con 5 pings
    icmp_available, packet_loss, latency = ping_health(ip, count=5)
    ping_status, _ = get_ping_status(icmp_available, packet_loss, latency)

    # Tests SNMP (solo si el host responde a ping)
    if icmp_available:
        snmp_public_result = snmp_get("public", ip)
        snmp_gestiongrp_result = snmp_get("GestionGrp", ip)
    else:
        snmp_public_result = False
        snmp_gestiongrp_result = False

    snmp_public_color = GREEN if snmp_public_result else RED
    snmp_gestiongrp_color = GREEN if snmp_gestiongrp_result else RED

    # Para la tabla con colores
    table_row = [
        ip,
        ping_status,
        f"{snmp_public_color}{snmp_public_result}{END}",
        f"{snmp_gestiongrp_color}{snmp_gestiongrp_result}{END}"
    ]

    # Para el CSV sin colores
    csv_row = [
        ip,
        "UP" if icmp_available else "DOWN",
        packet_loss,
        round(latency, 2) if icmp_available else 0,
        snmp_public_result,
        snmp_gestiongrp_result
    ]

    return table_row, csv_row

def main():
    cleaner()
    ips = read_ips()

    if not ips:
        print("No se encontraron IPs para probar.")
        return

    print(f"Iniciando pruebas para {len(ips)} IPs...")
    print("(Realizando 5 pings por IP para evaluar salud de conexión)\n")

    table = PrettyTable(["IP", "Estado ICMP", "SNMP public", "SNMP GestionGrp"])
    table.align["IP"] = "l"
    table.align["Estado ICMP"] = "l"

    csv_results = []

    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(test_ip, ips))

    for table_row, csv_row in results:
        table.add_row(table_row)
        csv_results.append(csv_row)

    print(table)
    write_results_to_csv(csv_results)

    print("\n✓ Pruebas completadas y resultados guardados en 'resultados.csv'.")

    # Estadísticas resumidas
    total = len(ips)
    up = sum(1 for _, csv in results if csv[1] == "UP")
    print(f"\nResumen: {up}/{total} hosts alcanzables ({(up/total*100):.1f}%)")

if __name__ == "__main__":
    main()
