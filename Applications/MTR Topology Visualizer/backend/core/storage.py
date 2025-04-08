#!/usr/bin/env python3
"""
Módulo de almacenamiento para mtr-topology.
Gestiona la conexión con InfluxDB y el almacenamiento de resultados.
"""

import logging
import json
import time
from typing import List, Dict, Any, Optional, Union
from influxdb import InfluxDBClient
from datetime import datetime

# Configuración del logger
logger = logging.getLogger(__name__)

class StorageError(Exception):
    """Excepción base para errores de almacenamiento."""
    pass

class InfluxConnectionError(StorageError):
    """Error de conexión con InfluxDB."""
    pass

class InfluxStorage:
    """Clase para manejar el almacenamiento en InfluxDB."""
    
    def __init__(
        self,
        host: str = 'localhost',
        port: int = 8086,
        username: str = None,
        password: str = None,
        database: str = 'mtr_topology',
        ssl: bool = False,
        verify_ssl: bool = False,
        retention_policy: str = None,
        default_tags: Dict[str, str] = None
    ):
        """
        Inicializa la conexión con InfluxDB.
        
        Args:
            host: Host de InfluxDB.
            port: Puerto de InfluxDB.
            username: Usuario de InfluxDB.
            password: Contraseña de InfluxDB.
            database: Base de datos de InfluxDB.
            ssl: Si es True, se usa SSL para la conexión.
            verify_ssl: Si es True, se verifica el certificado SSL.
            retention_policy: Política de retención a usar (opcional).
            default_tags: Tags predeterminados para todas las mediciones.
        """
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.ssl = ssl
        self.verify_ssl = verify_ssl
        self.retention_policy = retention_policy
        self.default_tags = default_tags or {}
        self.client = None
        
        # Inicializar cliente
        self._connect()
    
    def _connect(self) -> None:
        """
        Establece la conexión con InfluxDB.
        
        Raises:
            InfluxConnectionError: Si hay un error al conectar con InfluxDB.
        """
        try:
            self.client = InfluxDBClient(
                host=self.host,
                port=self.port,
                username=self.username,
                password=self.password,
                database=self.database,
                ssl=self.ssl,
                verify_ssl=self.verify_ssl
            )
            
            # Comprobar si la base de datos existe, si no, crearla
            databases = self.client.get_list_database()
            if self.database not in [db['name'] for db in databases]:
                logger.info(f"Creando base de datos {self.database}")
                self.client.create_database(self.database)
            
            # Establecer base de datos activa
            self.client.switch_database(self.database)
            
            logger.info(f"Conectado a InfluxDB en {self.host}:{self.port}, base de datos {self.database}")
        
        except Exception as e:
            raise InfluxConnectionError(f"Error al conectar con InfluxDB: {str(e)}")
    
    def store_mtr_result(self, mtr_result) -> bool:
        """
        Almacena un resultado de MTR en InfluxDB.
        
        Args:
            mtr_result: Objeto MTRResult con los datos a almacenar.
            
        Returns:
            True si se almacenó correctamente, False en caso contrario.
        """
        try:
            # Verificar que la conexión está activa
            if not self.client:
                self._connect()
            
            # Convertir el resultado a puntos de InfluxDB
            points = self._convert_mtr_to_points(mtr_result)
            
            # Escribir los puntos en InfluxDB
            self.client.write_points(
                points,
                time_precision='ms',
                retention_policy=self.retention_policy
            )
            
            logger.debug(f"Almacenados {len(points)} puntos en InfluxDB para {mtr_result.destination}")
            return True
        
        except Exception as e:
            logger.error(f"Error al almacenar resultado en InfluxDB: {str(e)}")
            return False
    
    def _convert_mtr_to_points(self, mtr_result) -> List[Dict[str, Any]]:
        """
        Convierte un resultado de MTR a puntos de InfluxDB.
        
        Args:
            mtr_result: Objeto MTRResult a convertir.
            
        Returns:
            Lista de puntos de InfluxDB.
        """
        points = []
        
        # Timestamp en milisegundos para todos los puntos
        timestamp = int(mtr_result.end_time * 1000) if mtr_result.end_time else int(time.time() * 1000)
        
        # Tags comunes para todos los puntos
        common_tags = {
            'source': mtr_result.source,
            'destination': mtr_result.destination,
            **self.default_tags
        }
        
        # Punto para información general del escaneo
        scan_point = {
            'measurement': 'mtr_scan',
            'tags': {
                **common_tags,
                'status': mtr_result.status
            },
            'time': timestamp,
            'fields': {
                'duration_ms': int((mtr_result.end_time - mtr_result.start_time) * 1000) if mtr_result.end_time else None,
                'total_hops': len(mtr_result.hops),
                'completed': mtr_result.status == 'completed',
                'error': mtr_result.error if mtr_result.error else ''
            }
        }
        points.append(scan_point)
        
        # Puntos para cada hop
        for hop in mtr_result.hops:
            # Skip hops sin IP asignada (timeouts completos)
            if not hop.ip_address:
                continue
                
            hop_point = {
                'measurement': 'mtr_hop',
                'tags': {
                    **common_tags,
                    'hop_number': hop.hop_number,
                    'hop_ip': hop.ip_address,
                    'is_destination': hop.ip_address == mtr_result.destination
                },
                'time': timestamp,
                'fields': {
                    'avg_latency': hop.avg_latency,
                    'min_latency': hop.min_latency,
                    'max_latency': hop.max_latency,
                    'packet_loss': hop.packet_loss,
                    'sent_count': hop.sent_count,
                    'received_count': hop.received_count,
                    # Convertir lista de tipos de respuesta a cadena JSON
                    'response_types': json.dumps(hop.response_types)
                }
            }
            points.append(hop_point)
            
            # Almacenar cada latencia individual como un punto separado para análisis detallado
            for i, latency in enumerate(hop.latencies):
                latency_point = {
                    'measurement': 'mtr_latency',
                    'tags': {
                        **common_tags,
                        'hop_number': hop.hop_number,
                        'hop_ip': hop.ip_address,
                        'sequence': i + 1
                    },
                    'time': timestamp - (len(hop.latencies) - i - 1) * 100,  # Distribuir en el tiempo
                    'fields': {
                        'latency': latency,
                        'response_type': hop.response_types[i] if i < len(hop.response_types) else 'unknown'
                    }
                }
                points.append(latency_point)
        
        return points
    
    def query_agents(self) -> List[Dict[str, Any]]:
        """
        Obtiene la lista de agentes (destinos) monitoreados.
        
        Returns:
            Lista de diccionarios con información de agentes.
        """
        try:
            query = """
            SELECT last("total_hops") as total_hops, last("duration_ms") as duration_ms
            FROM "mtr_scan"
            GROUP BY "destination"
            """
            
            result = self.client.query(query)
            
            agents = []
            for (tags, series) in result.items():
                # Obtener destination de los tags
                destination = tags[1][1]
                
                # Convertir serie a diccionario
                for point in series:
                    agents.append({
                        'ip': destination,
                        'last_scan': point.get('time'),
                        'total_hops': point.get('total_hops'),
                        'last_duration_ms': point.get('duration_ms'),
                        'enabled': True  # Siempre enabled por defecto
                    })
            
            return agents
        
        except Exception as e:
            logger.error(f"Error al obtener agentes de InfluxDB: {str(e)}")
            return []
    
    def query_topology(self, time_range: str = '1h', group: str = None, agent: str = None) -> Dict[str, Any]:
        """
        Obtiene datos de topología para visualización.
        
        Args:
            time_range: Rango de tiempo para la consulta (formato InfluxQL).
            group: Filtrar por grupo (opcional).
            agent: Filtrar por agente/destino (opcional).
            
        Returns:
            Diccionario con datos de topología.
        """
        try:
            # Base de la consulta
            where_clauses = [f"time > now() - {time_range}"]
            
            # Añadir filtros si se proporcionan
            if group:
                # Asumiendo que hay un tag de grupo
                where_clauses.append(f"\"group\" = '{group}'")
            
            if agent:
                where_clauses.append(f"\"destination\" = '{agent}'")
            
            # Construir cláusula WHERE
            where_str = " AND ".join(where_clauses)
            
            # Consulta para obtener datos de hops
            query = f"""
            SELECT mean("avg_latency") as avg_latency, 
                   mean("packet_loss") as packet_loss,
                   count("avg_latency") as count
            FROM "mtr_hop"
            WHERE {where_str}
            GROUP BY "source", "destination", "hop_ip", "hop_number"
            """
            
            result = self.client.query(query)
            
            # Estructuras para construir la topología
            nodes = {}
            links = []
            
            # Procesar resultados
            for (tags, series) in result.items():
                source = tags[1][1]
                destination = tags[2][1]
                hop_ip = tags[3][1]
                hop_number = int(tags[4][1])
                
                # Añadir nodos si no existen
                if source not in nodes:
                    nodes[source] = {'id': source, 'type': 'source'}
                
                if destination not in nodes:
                    nodes[destination] = {'id': destination, 'type': 'destination'}
                
                if hop_ip not in nodes:
                    nodes[hop_ip] = {'id': hop_ip, 'type': 'hop'}
                
                # Añadir enlaces
                for point in series:
                    links.append({
                        'source': source if hop_number == 1 else f"hop_{hop_number-1}_{destination}",
                        'target': hop_ip,
                        'destination': destination,
                        'hop_number': hop_number,
                        'avg_latency': point.get('avg_latency'),
                        'packet_loss': point.get('packet_loss'),
                        'count': point.get('count')
                    })
            
            # Convertir nodes de diccionario a lista
            nodes_list = list(nodes.values())
            
            return {
                'nodes': nodes_list,
                'links': links
            }
        
        except Exception as e:
            logger.error(f"Error al obtener topología de InfluxDB: {str(e)}")
            return {'nodes': [], 'links': []}
    
    def query_hop_stats(self, source: str, destination: str, hop_ip: str, time_range: str = '24h') -> Dict[str, Any]:
        """
        Obtiene estadísticas detalladas para un hop específico.
        
        Args:
            source: IP de origen.
            destination: IP de destino.
            hop_ip: IP del hop.
            time_range: Rango de tiempo para la consulta.
            
        Returns:
            Diccionario con estadísticas del hop.
        """
        try:
            # Consulta para estadísticas agregadas
            query_stats = f"""
            SELECT mean("avg_latency") as avg_latency,
                   min("min_latency") as min_latency,
                   max("max_latency") as max_latency,
                   mean("packet_loss") as packet_loss
            FROM "mtr_hop"
            WHERE time > now() - {time_range}
                AND "source" = '{source}'
                AND "destination" = '{destination}'
                AND "hop_ip" = '{hop_ip}'
            GROUP BY time(1h)
            """
            
            # Consulta para latencias individuales
            query_latencies = f"""
            SELECT "latency", "response_type"
            FROM "mtr_latency"
            WHERE time > now() - {time_range}
                AND "source" = '{source}'
                AND "destination" = '{destination}'
                AND "hop_ip" = '{hop_ip}'
            ORDER BY time ASC
            """
            
            stats_result = self.client.query(query_stats)
            latencies_result = self.client.query(query_latencies)
            
            # Procesar resultados de estadísticas
            time_series = []
            for (tags, series) in stats_result.items():
                for point in series:
                    time_series.append({
                        'time': point['time'],
                        'avg_latency': point['avg_latency'],
                        'min_latency': point['min_latency'],
                        'max_latency': point['max_latency'],
                        'packet_loss': point['packet_loss']
                    })
            
            # Procesar resultados de latencias
            latencies = []
            for point in list(latencies_result.get_points()):
                latencies.append({
                    'time': point['time'],
                    'latency': point['latency'],
                    'response_type': point['response_type']
                })
            
            return {
                'hop_ip': hop_ip,
                'source': source,
                'destination': destination,
                'time_series': time_series,
                'latencies': latencies
            }
        
        except Exception as e:
            logger.error(f"Error al obtener estadísticas de hop de InfluxDB: {str(e)}")
            return {}
    def parse_telegraf_configs(self, config_dir: str = '/etc/telegraf/telegraf.d') -> List[Dict[str, str]]:
        """
        Lee los archivos de configuración de Telegraf y extrae IPs de agentes.
        
        Args:
            config_dir: Directorio con archivos de configuración de Telegraf.
            
        Returns:
            Lista de diccionarios con información de agentes.
        """
        import os
        import re
        
        agents = []
        
        try:
            # Verificar que el directorio existe
            if not os.path.isdir(config_dir):
                logger.warning(f"El directorio {config_dir} no existe")
                return agents
            
            # Expresiones regulares para diferentes patrones
            # Patrón para inputs.ping URLs
            ping_regex = re.compile(r'\[\[inputs\.ping\]\](?:.*?\n)+?(?:\s*urls\s*=\s*\[([^\]]+)\])', re.DOTALL)
            url_regex = re.compile(r'"([^"]+)"')
            
            # Patrón para SNMP agents
            snmp_regex = re.compile(r'agents\s*=\s*\[\'udp://([^:]+):161\'\]')
            
            # Patrón para ICMP URLs
            icmp_regex = re.compile(r'urls\s*=\s*\["([^"]+)"\]')
            
            # Recorrer archivos .conf
            for filename in os.listdir(config_dir):
                if not filename.endswith('.conf'):
                    continue
                
                filepath = os.path.join(config_dir, filename)
                
                try:
                    with open(filepath, 'r') as f:
                        content = f.read()
                    
                    # Detectar por prefijo del nombre de archivo
                    if filename.startswith('snmp_'):
                        # Buscar IPs en formato snmp_*.conf
                        snmp_matches = snmp_regex.findall(content)
                        for ip in snmp_matches:
                            agents.append({
                                'ip': ip,
                                'source': f"telegraf:{filename}",
                                'enabled': True
                            })
                        logger.debug(f"Archivo {filename}: Encontrados {len(snmp_matches)} agentes SNMP")
                    
                    elif filename.startswith('icmp_'):
                        # Buscar IPs en formato icmp_*.conf
                        icmp_matches = icmp_regex.findall(content)
                        for ip in icmp_matches:
                            agents.append({
                                'ip': ip,
                                'source': f"telegraf:{filename}",
                                'enabled': True
                            })
                        logger.debug(f"Archivo {filename}: Encontrados {len(icmp_matches)} agentes ICMP")
                    
                    else:
                        # Buscar secciones de ping (formato general)
                        ping_matches = ping_regex.findall(content)
                        agent_count = 0
                        
                        for urls_str in ping_matches:
                            # Extraer URLs
                            url_matches = url_regex.findall(urls_str)
                            
                            for url in url_matches:
                                # Limpiar URL (quitar protocolo si existe)
                                clean_url = url.replace('http://', '').replace('https://', '')
                                
                                # Extraer hostname/IP
                                hostname = clean_url.split('/')[0].split(':')[0]
                                agent_count += 1
                                
                                # Añadir a la lista de agentes
                                agents.append({
                                    'ip': hostname,
                                    'source': f"telegraf:{filename}",
                                    'enabled': True
                                })
                        
                        # También buscar patrones SNMP e ICMP en cualquier archivo
                        # En caso de que no sigan la convención de nombres
                        snmp_matches = snmp_regex.findall(content)
                        icmp_matches = icmp_regex.findall(content)
                        
                        for ip in snmp_matches:
                            agents.append({
                                'ip': ip,
                                'source': f"telegraf:{filename} (snmp)",
                                'enabled': True
                            })
                        
                        for ip in icmp_matches:
                            agents.append({
                                'ip': ip,
                                'source': f"telegraf:{filename} (icmp)",
                                'enabled': True
                            })
                        
                        total = agent_count + len(snmp_matches) + len(icmp_matches)
                        logger.debug(f"Archivo {filename}: Encontrados {total} agentes en total")
                
                except Exception as e:
                    logger.error(f"Error al procesar archivo {filepath}: {str(e)}")
            
            logger.info(f"Encontrados {len(agents)} agentes en configuraciones de Telegraf")
            return agents
        
        except Exception as e:
            logger.error(f"Error al parsear configuraciones de Telegraf: {str(e)}")
            return [] 

    # 1. Añadir a storage.py - Mejorar el método _convert_mtr_to_points
    
    def _convert_mtr_to_points(self, mtr_result) -> List[Dict[str, Any]]:
        """
        Convierte un resultado de MTR a puntos de InfluxDB.
        
        Args:
            mtr_result: Objeto MTRResult a convertir.
            
        Returns:
            Lista de puntos de InfluxDB.
        """
        points = []
        
        # Timestamp en milisegundos para todos los puntos
        timestamp = int(mtr_result.end_time * 1000) if mtr_result.end_time else int(time.time() * 1000)
        
        # Calcular una firma única para esta ruta (path signature)
        path_signature = self._calculate_path_signature(mtr_result.hops)
        
        # Tags comunes para todos los puntos
        common_tags = {
            'source': mtr_result.source,
            'destination': mtr_result.destination,
            'path_signature': path_signature,  # Añadir firma de ruta como tag
            **self.default_tags
        }
        
        # Punto para información general del escaneo
        scan_point = {
            'measurement': 'mtr_scan',
            'tags': {
                **common_tags,
                'status': mtr_result.status
            },
            'time': timestamp,
            'fields': {
                'duration_ms': int((mtr_result.end_time - mtr_result.start_time) * 1000) if mtr_result.end_time else None,
                'total_hops': len(mtr_result.hops),
                'completed': mtr_result.status == 'completed',
                'error': mtr_result.error if mtr_result.error else ''
            }
        }
        points.append(scan_point)
        
        # Guardar la ruta completa como una medición separada para análisis de topología
        path_point = {
            'measurement': 'mtr_path',
            'tags': common_tags,
            'time': timestamp,
            'fields': {
                'path_json': json.dumps([hop.ip_address for hop in mtr_result.hops if hop.ip_address]),
                'hop_count': len([hop for hop in mtr_result.hops if hop.ip_address])
            }
        }
        points.append(path_point)
        
        # Puntos para cada hop
        for hop in mtr_result.hops:
            # Skip hops sin IP asignada (timeouts completos)
            if not hop.ip_address:
                continue
                
            hop_point = {
                'measurement': 'mtr_hop',
                'tags': {
                    **common_tags,
                    'hop_number': hop.hop_number,
                    'hop_ip': hop.ip_address,
                    'is_destination': hop.ip_address == mtr_result.destination
                },
                'time': timestamp,
                'fields': {
                    'avg_latency': hop.avg_latency,
                    'min_latency': hop.min_latency,
                    'max_latency': hop.max_latency,
                    'packet_loss': hop.packet_loss,
                    'sent_count': hop.sent_count,
                    'received_count': hop.received_count,
                    # Convertir lista de tipos de respuesta a cadena JSON
                    'response_types': json.dumps(hop.response_types)
                }
            }
            points.append(hop_point)
            
            # Almacenar cada latencia individual como un punto separado para análisis detallado
            for i, latency in enumerate(hop.latencies):
                latency_point = {
                    'measurement': 'mtr_latency',
                    'tags': {
                        **common_tags,
                        'hop_number': hop.hop_number,
                        'hop_ip': hop.ip_address,
                        'sequence': i + 1
                    },
                    'time': timestamp - (len(hop.latencies) - i - 1) * 100,  # Distribuir en el tiempo
                    'fields': {
                        'latency': latency,
                        'response_type': hop.response_types[i] if i < len(hop.response_types) else 'unknown'
                    }
                }
                points.append(latency_point)
        
        return points
    
    # 2. Añadir a storage.py - Método para calcular la firma de la ruta
    
    def _calculate_path_signature(self, hops) -> str:
        """
        Calcula una firma única para una ruta específica.
        Esta firma permite detectar cuando la ruta cambia.
        
        Args:
            hops: Lista de objetos HopResult.
            
        Returns:
            String con la firma del path.
        """
        # Extraer IPs de los hops que tienen dirección
        path_ips = [hop.ip_address for hop in hops if hop.ip_address]
        
        # Si no hay IPs, es una ruta vacía
        if not path_ips:
            return "empty_path"
        
        # Generar una firma combinando todas las IPs
        return "_".join(path_ips)
    
    # 3. Añadir a storage.py - Método para consultar cambios en rutas
    
    def query_path_changes(self, source: str, destination: str, time_range: str = '7d') -> List[Dict[str, Any]]:
        """
        Consulta cambios en las rutas entre un origen y destino.
        
        Args:
            source: IP de origen.
            destination: IP de destino.
            time_range: Rango de tiempo para la consulta.
            
        Returns:
            Lista de cambios en las rutas con información comparativa.
        """
        try:
            # Consulta para obtener firmas de ruta distintas ordenadas por tiempo
            query = f"""
            SELECT DISTINCT("path_signature")
            FROM (
                SELECT last("total_hops") as "total_hops", "path_signature"
                FROM "mtr_scan"
                WHERE time > now() - {time_range}
                  AND "source" = '{source}'
                  AND "destination" = '{destination}'
                GROUP BY time(1h), "path_signature"
            )
            """
            
            result = self.client.query(query)
            
            # Obtener firmas únicas
            signatures = []
            for point in list(result.get_points()):
                if 'distinct' in point and point['distinct'] not in signatures:
                    signatures.append(point['distinct'])
            
            if not signatures:
                return []
            
            # Para cada firma, obtener la ruta completa y sus timestamps
            path_details = []
            for signature in signatures:
                # Obtener la primera y última vez que se vio esta ruta
                time_query = f"""
                SELECT first("path_json") as "first_path", last("path_json") as "last_path",
                       min(time) as "first_seen", max(time) as "last_seen"
                FROM "mtr_path"
                WHERE time > now() - {time_range}
                  AND "source" = '{source}'
                  AND "destination" = '{destination}'
                  AND "path_signature" = '{signature}'
                """
                
                time_result = self.client.query(time_query)
                
                for point in list(time_result.get_points()):
                    path_details.append({
                        'path_signature': signature,
                        'first_seen': point.get('first_seen'),
                        'last_seen': point.get('last_seen'),
                        'path': json.loads(point.get('first_path', '[]'))
                    })
            
            # Ordenar por primera vez visto
            path_details.sort(key=lambda x: x['first_seen'])
            
            # Detectar cambios comparando rutas consecutivas
            changes = []
            for i in range(1, len(path_details)):
                previous = path_details[i-1]
                current = path_details[i]
                
                changes.append({
                    'change_time': current['first_seen'],
                    'old_path': previous['path'],
                    'new_path': current['path'],
                    'old_signature': previous['path_signature'],
                    'new_signature': current['path_signature'],
                    'duration': self._calculate_time_diff(previous['first_seen'], previous['last_seen'])
                })
            
            return changes
        
        except Exception as e:
            logger.error(f"Error al consultar cambios de ruta: {str(e)}")
            return []
    
    # 4. Función auxiliar para calcular diferencia de tiempo
    
    def _calculate_time_diff(self, start_time, end_time):
        """Calcula la diferencia de tiempo en formato legible."""
        from datetime import datetime
        import dateutil.parser
        
        try:
            if isinstance(start_time, str):
                start = dateutil.parser.parse(start_time)
            else:
                start = start_time
                
            if isinstance(end_time, str):
                end = dateutil.parser.parse(end_time)
            else:
                end = end_time
                
            diff = end - start
            hours = diff.total_seconds() / 3600
            
            if hours < 1:
                return f"{int(diff.total_seconds() / 60)} minutos"
            elif hours < 24:
                return f"{int(hours)} horas"
            else:
                return f"{int(hours / 24)} días"
        except:
            return "desconocido"
    
