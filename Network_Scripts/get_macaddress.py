from scapy.all import ARP, Ether, srp
import ipaddress

def scan_network(network):
    """ Escanea la red en busca de puertas de enlace posibles usando ARP requests """
    ip_range = ipaddress.ip_network(network)
    arp_request = Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=str(ip_range))
    result, _ = srp(arp_request, timeout=2, verbose=False)

    gateways = []
    for sent, received in result:
        gateways.append({'IP': received.psrc, 'MAC': received.hwsrc})

    return gateways

# Configura aquí la dirección de la red y la máscara, por ejemplo '192.168.1.0/24'
network = "192.168.252.0/24"
devices = scan_network(network)

print("Posibles puertas de enlace encontradas:")
for device in devices:
    print(f"IP: {device['IP']}, MAC: {device['MAC']}")
