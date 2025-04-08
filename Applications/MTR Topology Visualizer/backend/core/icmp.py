#!/usr/bin/env python3
"""
Módulo ICMP para mtr-topology.
Proporciona funcionalidad para enviar y recibir paquetes ICMP con TTL personalizable.
"""

import socket
import struct
import time
import random
import select
import logging
from typing import Tuple, Dict, Optional, Union, List

# Configuración del logger
logger = logging.getLogger(__name__)

# Constantes para ICMP
ICMP_ECHO_REQUEST = 8
ICMP_ECHO_REPLY = 0
ICMP_TIME_EXCEEDED = 11

class ICMPError(Exception):
    """Excepción base para errores de ICMP."""
    pass

class ICMPPermissionError(ICMPError):
    """Error de permisos al utilizar sockets raw."""
    pass

class ICMPNetworkError(ICMPError):
    """Error de red al enviar/recibir paquetes ICMP."""
    pass

class ICMPTimeoutError(ICMPError):
    """Timeout al esperar respuesta ICMP."""
    pass

def checksum(source_string: bytes) -> int:
    """
    Calcula el checksum de un paquete ICMP.
    
    Args:
        source_string: Datos para calcular el checksum.
        
    Returns:
        Valor del checksum.
    """
    sum = 0
    count_to = (len(source_string) // 2) * 2
    
    for count in range(0, count_to, 2):
        this_val = source_string[count + 1] * 256 + source_string[count]
        sum = sum + this_val
        sum = sum & 0xffffffff
    
    if count_to < len(source_string):
        sum = sum + source_string[len(source_string) - 1]
        sum = sum & 0xffffffff
    
    sum = (sum >> 16) + (sum & 0xffff)
    sum = sum + (sum >> 16)
    answer = ~sum
    answer = answer & 0xffff
    
    # Convertir de orden de red a orden de host
    answer = answer >> 8 | (answer << 8 & 0xff00)
    
    return answer

def create_packet(id_number: int = None) -> bytes:
    """
    Crea un paquete ICMP Echo Request.
    
    Args:
        id_number: ID para el paquete (se generará aleatoriamente si no se proporciona).
        
    Returns:
        Paquete ICMP como bytes.
    """
    # ID aleatorio para los paquetes si no se proporciona uno
    if id_number is None:
        id_number = random.randint(1, 65535)
    
    # Cabecera: tipo (8), código (0), checksum (0 inicial), id, sequence
    header = struct.pack('!BBHHH', ICMP_ECHO_REQUEST, 0, 0, id_number, 1)
    
    # Datos: timestamp para medir el tiempo transcurrido
    data = struct.pack('!d', time.time())
    
    # Calcular checksum
    my_checksum = checksum(header + data)
    
    # Reconstruir la cabecera con el checksum
    header = struct.pack('!BBHHH', ICMP_ECHO_REQUEST, 0, socket.htons(my_checksum), id_number, 1)
    
    return header + data

def parse_icmp_header(packet: bytes) -> Dict:
    """
    Parsea la cabecera ICMP de un paquete.
    
    Args:
        packet: Paquete ICMP completo.
        
    Returns:
        Diccionario con los campos de la cabecera.
    """
    icmp_header = packet[20:28]  # IP header is 20 bytes
    type, code, checksum, id_number, sequence = struct.unpack('!BBHHH', icmp_header)
    
    return {
        'type': type,
        'code': code,
        'checksum': checksum,
        'id_number': id_number,
        'sequence': sequence
    }

def parse_ip_header(packet: bytes) -> Dict:
    """
    Parsea la cabecera IP de un paquete.
    
    Args:
        packet: Paquete IP completo.
        
    Returns:
        Diccionario con los campos de la cabecera IP.
    """
    ip_header = packet[:20]
    ihl = (ip_header[0] & 0x0F) * 4  # Internet Header Length in bytes
    
    src_ip = socket.inet_ntoa(ip_header[12:16])
    dst_ip = socket.inet_ntoa(ip_header[16:20])
    
    return {
        'ihl': ihl,
        'src_ip': src_ip,
        'dst_ip': dst_ip
    }

def send_receive_icmp(
    destination_addr: str, 
    ttl: int = 64, 
    timeout: float = 1.0, 
    packet_size: int = 56
) -> Tuple[Optional[str], Optional[float], Optional[str]]:
    """
    Envía un paquete ICMP Echo Request y espera la respuesta.
    
    Args:
        destination_addr: Dirección IP de destino.
        ttl: Time To Live (TTL) para el paquete.
        timeout: Tiempo máximo de espera para la respuesta (en segundos).
        packet_size: Tamaño total del paquete en bytes.
        
    Returns:
        Tupla con (dirección del respondedor, tiempo de respuesta, tipo de respuesta)
        Los tipos de respuesta pueden ser: 'echo_reply', 'time_exceeded', 'unreachable', etc.
        
    Raises:
        ICMPPermissionError: Si no hay permisos suficientes para sockets raw.
        ICMPNetworkError: Si hay un error de red.
        ICMPTimeoutError: Si no hay respuesta dentro del timeout.
    """
    try:
        # Crear un socket raw para ICMP
        icmp_socket = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        
        # Establecer TTL
        icmp_socket.setsockopt(socket.IPPROTO_IP, socket.IP_TTL, ttl)
        
        # Establecer timeout
        icmp_socket.settimeout(timeout)
        
        # Crear ID para el paquete
        packet_id = random.randint(1, 65535)
        
        # Crear paquete
        packet = create_packet(packet_id)
        
        # Registrar tiempo de envío
        send_time = time.time()
        
        # Enviar paquete
        icmp_socket.sendto(packet, (destination_addr, 0))
        
        # Esperar respuesta
        ready = select.select([icmp_socket], [], [], timeout)
        
        if ready[0]:  # Si hay datos disponibles
            receive_time = time.time()
            packet_data, addr = icmp_socket.recvfrom(1024)
            response_time = (receive_time - send_time) * 1000  # Convertir a ms
            
            # Parsear cabeceras
            ip_header_dict = parse_ip_header(packet_data)
            icmp_header_dict = parse_icmp_header(packet_data)
            
            # Determinar tipo de respuesta
            icmp_type = icmp_header_dict['type']
            
            response_type = None
            if icmp_type == ICMP_ECHO_REPLY:
                response_type = 'echo_reply'
            elif icmp_type == ICMP_TIME_EXCEEDED:
                response_type = 'time_exceeded'
            else:
                response_type = f'icmp_type_{icmp_type}'
            
            return (addr[0], response_time, response_type)
        else:
            # Timeout - no se recibió respuesta
            raise ICMPTimeoutError("No se recibió respuesta dentro del timeout")
    
    except socket.error as e:
        if e.errno == 1:  # Operation not permitted
            raise ICMPPermissionError("No hay permisos suficientes para sockets raw. Ejecute con privilegios de root o use setcap.")
        else:
            raise ICMPNetworkError(f"Error de red: {str(e)}")
    
    finally:
        try:
            icmp_socket.close()
        except:
            pass

def multi_ping(
    destination_addr: str, 
    count: int = 3, 
    ttl: int = 64, 
    timeout: float = 1.0,
    interval: float = 0.2
) -> List[Dict]:
    """
    Envía múltiples pings a un destino y recopila estadísticas.
    
    Args:
        destination_addr: Dirección IP de destino.
        count: Número de pings a enviar.
        ttl: Time To Live (TTL) para los paquetes.
        timeout: Tiempo máximo de espera para cada respuesta (en segundos).
        interval: Intervalo entre pings consecutivos (en segundos).
        
    Returns:
        Lista de resultados para cada ping, con información de latencia y estado.
    """
    results = []
    
    for i in range(count):
        try:
            addr, rtt, response_type = send_receive_icmp(destination_addr, ttl, timeout)
            results.append({
                'seq': i + 1,
                'addr': addr,
                'rtt': rtt,
                'status': 'ok',
                'response_type': response_type
            })
        except ICMPTimeoutError:
            results.append({
                'seq': i + 1,
                'addr': None,
                'rtt': None,
                'status': 'timeout',
                'response_type': None
            })
        except (ICMPPermissionError, ICMPNetworkError) as e:
            results.append({
                'seq': i + 1,
                'addr': None,
                'rtt': None,
                'status': 'error',
                'error_msg': str(e),
                'response_type': None
            })
        
        # Esperar el intervalo especificado antes del siguiente ping (excepto el último)
        if i < count - 1:
            time.sleep(interval)
    
    return results

if __name__ == "__main__":
    # Ejemplo de uso
    import sys
    
    if len(sys.argv) != 2:
        print(f"Uso: {sys.argv[0]} <dirección_ip>")
        sys.exit(1)
    
    target = sys.argv[1]
    
    print(f"Enviando 3 pings a {target} con TTL=64:")
    results = multi_ping(target, count=3, ttl=64)
    
    for result in results:
        if result['status'] == 'ok':
            print(f"Secuencia {result['seq']}: {result['addr']} - {result['rtt']:.2f} ms ({result['response_type']})")
        else:
            print(f"Secuencia {result['seq']}: {result['status']}")
