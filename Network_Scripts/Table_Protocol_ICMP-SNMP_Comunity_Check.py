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

def ping(ip):
    result = subprocess.run(['ping', '-c', '1', '-W', '1', ip], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def snmp_get(community, ip):
    command = ["timeout", "0.1", "snmpget", "-v2c", "-c", community, ip, "SNMPv2-MIB::sysName.0"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def write_results_to_csv(results):
    with open('resultados.csv', 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["IP", "ICMP", "SNMP public", "SNMP GestionGrp"])
        for result in results:
            writer.writerow(result)

def test_ip(ip):
    icmp_result = ping(ip)
    snmp_public_result = snmp_get("public", ip)
    snmp_gestiongrp_result = snmp_get("GestionGrp", ip)
    icmp_color = GREEN if icmp_result else RED
    snmp_public_color = GREEN if snmp_public_result else RED
    snmp_gestiongrp_color = GREEN if snmp_gestiongrp_result else RED
    return [ip, f"{icmp_color}{icmp_result}{END}", f"{snmp_public_color}{snmp_public_result}{END}", f"{snmp_gestiongrp_color}{snmp_gestiongrp_result}{END}"]

def main():
    cleaner()
    ips = read_ips()
    if not ips:
        print("No se encontraron IPs para probar.")
        return

    table = PrettyTable(["IP", "ICMP", "SNMP public", "SNMP GestionGrp"])
    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(test_ip, ips))

    for result in results:
        table.add_row(result)

    print(table)

    write_results_to_csv(results)
    print("Pruebas completadas y resultados guardados en 'resultados.csv'.")

if __name__ == "__main__":
    main()
