#!/usr/bin/env python3
import socket
import struct
import time
import select
import random
import os
import logging

# Configurar logging
logger = logging.getLogger(__name__)

class ICMPReturn:
    """Contiene información sobre una respuesta ICMP."""
    def __init__(self, success=False, addr="", elapsed=0):
        self.success = success
        self.addr = addr
        self.elapsed = elapsed

def calculate_checksum(data):
    """Calcula el checksum para un paquete ICMP."""
    sum = 0
    countTo = (len(data) // 2) * 2
    
    for count in range(0, countTo, 2):
        sum += (data[count + 1] * 256 + data[count])
    
    if countTo < len(data):
        sum += data[len(data) - 1]
    
    sum = (sum >> 16) + (sum & 0xffff)
    sum += (sum >> 16)
    
    return ~sum & 0xffff

def create_icmp_packet(id_num, seq_num):
    """Crea un paquete ICMP Echo Request."""
    # Tipo 8 para Echo Request
    header = struct.pack('!BBHHH', 8, 0, 0, id_num, seq_num)
    data = struct.pack('!d', time.time()) + b'x' * 36  # timestamp + padding
    
    # Calcular el checksum
    checksum = calculate_checksum(header + data)
    
    # Reconstruir el header con el checksum
    header = struct.pack('!BBHHH', 8, 0, checksum, id_num, seq_num)
    
    return header + data

def create_icmpv6_packet(id_num, seq_num):
    """Crea un paquete ICMPv6 Echo Request."""
    # Tipo 128 para ICMPv6 Echo Request
    header = struct.pack('!BBHHH', 128, 0, 0, id_num, seq_num)
    data = struct.pack('!d', time.time()) + b'x' * 36  # timestamp + padding
    
    # Calcular el checksum
    # En IPv6, el checksum incluye una pseudo-cabecera IPv6,
    # pero como estamos usando sockets crudos, el kernel lo calculará por nosotros
    checksum = 0
    
    # Reconstruir el header con el checksum
    header = struct.pack('!BBHHH', 128, 0, checksum, id_num, seq_num)
    
    return header + data

def parse_icmp_packet(packet, expected_id, expected_seq):
    """Parsea un paquete ICMP y verifica si coincide con el ID y secuencia."""
    try:
        if len(packet) < 28:
            return False, None
        
        icmp_type, icmp_code, _, packet_id, packet_seq = struct.unpack('!BBHHH', packet[20:28])
        
        # Verificar si es un Time Exceeded o un Echo Reply
        if icmp_type == 11:  # Time Exceeded
            if len(packet) < 48:  # Necesitamos más datos para verificar
                return False, None
            
            # Extraer el paquete original del cuerpo del mensaje Time Exceeded
            orig_packet = packet[28:]
            if len(orig_packet) < 28:
                return False, None
            
            try:
                # Verificar que el paquete original contenga nuestro ID y secuencia
                orig_id, orig_seq = struct.unpack('!HH', orig_packet[24:28])
                if orig_id == expected_id and orig_seq == expected_seq:
                    return True, None
            except:
                pass
            
            return False, None
            
        elif icmp_type == 0:  # Echo Reply
            if packet_id == expected_id and packet_seq == expected_seq:
                try:
                    send_time = struct.unpack('!d', packet[28:36])[0]
                    return True, send_time
                except:
                    return True, None
        
        return False, None
    except Exception as e:
        logger.error(f"Error parsing ICMP packet: {e}")
        return False, None

def parse_icmpv6_packet(packet, expected_id, expected_seq):
    """Parsea un paquete ICMPv6 y verifica si coincide con el ID y secuencia."""
    try:
        if len(packet) < 8:  # ICMPv6 header mínimo
            return False, None
        
        icmp_type, icmp_code, _, packet_id, packet_seq = struct.unpack('!BBHHH', packet[:8])
        
        # Verificar si es un Time Exceeded o un Echo Reply
        if icmp_type == 3:  # Time Exceeded
            if len(packet) < 48:  # Necesitamos más datos para verificar
                return False, None
            
            # Extraer el paquete original del cuerpo del mensaje Time Exceeded
            orig_packet = packet[8:]
            if len(orig_packet) < 8:
                return False, None
            
            try:
                # Verificar que el paquete original contenga nuestro ID y secuencia
                orig_id, orig_seq = struct.unpack('!HH', orig_packet[4:8])
                if orig_id == expected_id and orig_seq == expected_seq:
                    return True, None
            except:
                pass
            
            return False, None
            
        elif icmp_type == 129:  # Echo Reply
            if packet_id == expected_id and packet_seq == expected_seq:
                try:
                    send_time = struct.unpack('!d', packet[8:16])[0]
                    return True, send_time
                except:
                    return True, None
        
        return False, None
    except Exception as e:
        logger.error(f"Error parsing ICMPv6 packet: {e}")
        return False, None

def send_discover_icmp(dest_addr, ttl, id_num, timeout, seq):
    """Envía un paquete ICMP con un TTL específico para descubrir saltos."""
    try:
        ip_version = get_ip_version(dest_addr)
        if ip_version == 6:
            return send_icmpv6(dest_addr, "", ttl, id_num, timeout, seq)
        else:
            return send_icmp(dest_addr, "", ttl, id_num, timeout, seq)
    except Exception as e:
        logger.error(f"Error en send_discover_icmp: {e}")
        return ICMPReturn()

def get_ip_version(ip_address):
    """Determina si una dirección IP es IPv4 o IPv6."""
    try:
        socket.inet_pton(socket.AF_INET, ip_address)
        return 4
    except socket.error:
        try:
            socket.inet_pton(socket.AF_INET6, ip_address)
            return 6
        except socket.error:
            return None

def send_icmp(dest_addr, target="", ttl=64, id_num=None, timeout=1.0, seq=1):
    """
    Envía un paquete ICMP y espera una respuesta.
    
    Args:
        dest_addr: IP de destino
        target: IP específica de la que se espera respuesta (si está vacía, cualquiera sirve)
        ttl: Time-To-Live del paquete
        id_num: ID del paquete ICMP
        timeout: Tiempo de espera máximo (segundos)
        seq: Número de secuencia
    
    Returns:
        ICMPReturn: Objeto con la información de la respuesta
    """
    result = ICMPReturn()
    
    if id_num is None:
        id_num = os.getpid() & 0xFFFF
    
    try:
        # Crear socket para ICMP
        icmp_socket = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        icmp_socket.setsockopt(socket.IPPROTO_IP, socket.IP_TTL, ttl)
        icmp_socket.settimeout(timeout)
    except socket.error as e:
        if e.errno == 1:
            # Operación no permitida - necesita privilegios de root
            logger.error("ICMP requiere privilegios de root")
            raise Exception("ICMP requiere privilegios de root") from e
        logger.error(f"Error creando socket ICMP: {e}")
        raise
    
    # Crear y enviar el paquete ICMP
    packet = create_icmp_packet(id_num, seq)
    start_time = time.time()
    
    try:
        icmp_socket.sendto(packet, (dest_addr, 0))
        
        # Esperar respuesta
        while True:
            # Usar select para esperar datos
            ready = select.select([icmp_socket], [], [], timeout)
            
            if not ready[0]:  # Timeout
                return result
            
            # Recibir datos
            recv_packet, addr = icmp_socket.recvfrom(1024)
            curr_time = time.time()
            
            # Si se especificó un target, verificar que la respuesta venga de él
            if target and addr[0] != target:
                # Verificar si se agotó el tiempo
                if curr_time - start_time > timeout:
                    return result
                continue
            
            # Parsear el paquete recibido
            is_match, send_time = parse_icmp_packet(recv_packet, id_num, seq)
            
            if is_match:
                result.success = True
                result.addr = addr[0]
                
                if send_time:
                    result.elapsed = curr_time - send_time
                else:
                    result.elapsed = curr_time - start_time
                
                return result
            
            # Verificar si se agotó el tiempo
            if curr_time - start_time > timeout:
                return result
    
    except Exception as e:
        logger.error(f"Error en send_icmp: {e}")
    finally:
        icmp_socket.close()
    
    return result

def send_icmpv6(dest_addr, target="", hop_limit=64, id_num=None, timeout=1.0, seq=1):
    """
    Envía un paquete ICMPv6 y espera una respuesta.
    
    Args:
        dest_addr: IPv6 de destino
        target: IPv6 específica de la que se espera respuesta (si está vacía, cualquiera sirve)
        hop_limit: Hop Limit del paquete (equivalente a TTL en IPv4)
        id_num: ID del paquete ICMPv6
        timeout: Tiempo de espera máximo (segundos)
        seq: Número de secuencia
    
    Returns:
        ICMPReturn: Objeto con la información de la respuesta
    """
    result = ICMPReturn()
    
    if id_num is None:
        id_num = os.getpid() & 0xFFFF
    
    try:
        # Crear socket para ICMPv6
        icmp_socket = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_ICMPV6)
        icmp_socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_UNICAST_HOPS, hop_limit)
        icmp_socket.settimeout(timeout)
    except socket.error as e:
        if e.errno == 1:
            # Operación no permitida - necesita privilegios de root
            logger.error("ICMPv6 requiere privilegios de root")
            raise Exception("ICMPv6 requiere privilegios de root") from e
        logger.error(f"Error creando socket ICMPv6: {e}")
        raise
    
    # Crear y enviar el paquete ICMPv6
    packet = create_icmpv6_packet(id_num, seq)
    start_time = time.time()
    
    try:
        icmp_socket.sendto(packet, (dest_addr, 0, 0, 0))  # IPv6 socket requiere flowinfo y scopeid
        
        # Esperar respuesta
        while True:
            # Usar select para esperar datos
            ready = select.select([icmp_socket], [], [], timeout)
            
            if not ready[0]:  # Timeout
                return result
            
            # Recibir datos
            recv_packet, addr = icmp_socket.recvfrom(1024)
            curr_time = time.time()
            
            # Si se especificó un target, verificar que la respuesta venga de él
            if target and addr[0] != target:
                # Verificar si se agotó el tiempo
                if curr_time - start_time > timeout:
                    return result
                continue
            
            # Parsear el paquete recibido
            is_match, send_time = parse_icmpv6_packet(recv_packet, id_num, seq)
            
            if is_match:
                result.success = True
                result.addr = addr[0]
                
                if send_time:
                    result.elapsed = curr_time - send_time
                else:
                    result.elapsed = curr_time - start_time
                
                return result
            
            # Verificar si se agotó el tiempo
            if curr_time - start_time > timeout:
                return result
    
    except Exception as e:
        logger.error(f"Error en send_icmpv6: {e}")
    finally:
        icmp_socket.close()
    
    return result
