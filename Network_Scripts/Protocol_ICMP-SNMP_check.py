import subprocess
import concurrent.futures
from os import system
import sys

# Colores
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
    return (ip, result.returncode)

def snmp_get(community, ip):
    command = ["timeout", "0.1", "snmpget", "-v2c", "-c", community, ip, "SNMPv2-MIB::sysName.0"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return (ip, result.returncode)

def check_status(ip_status):
    ip, status = ip_status
    if status == 0:
        print("{}{}\tUp{}".format(GREEN, ip, END))
    else:
        print("{}{}\tDown{}".format(RED, ip, END))

def process_ips(protocol, ips, community=None):
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        if protocol == 'ICMP':
            futures = [executor.submit(ping, ip) for ip in ips]
        elif protocol == 'SNMP':
            futures = [executor.submit(snmp_get, community, ip) for ip in ips]

        for future in concurrent.futures.as_completed(futures):
            check_status(future.result())

def menu():
    cleaner()
    while True:
        print("1. ICMP")
        print("2. SNMP")
        print("3. Salir")
        choice = input("Seleccione un protocolo: ")
        if choice == '1':
            ips = read_ips()
            if not ips:
                continue
            process_ips('ICMP', ips)
        elif choice == '2':
            community = input("Ingrese la comunidad SNMP: ")
            if community.lower() == 'salir':
                continue
            ips = read_ips()
            if not ips:
                continue
            process_ips('SNMP', ips, community)
        elif choice == '3':
            sys.exit()
        else:
            print("Opción inválida. Intente nuevamente.")

if __name__ == "__main__":
    menu()
