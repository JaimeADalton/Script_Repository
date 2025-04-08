#!/usr/bin/env python3
"""
Módulo MTR para mtr-topology.
Implementa la lógica de traceroute + estadísticas para monitoreo de red.
"""

import time
import logging
import ipaddress
import threading
import queue
import random
from typing import List, Dict, Any, Optional, Tuple, Union
from dataclasses import dataclass, field

from core.icmp import send_receive_icmp, ICMPTimeoutError, ICMPPermissionError, ICMPNetworkError
from core.storage import InfluxStorage

# Configuración del logger
logger = logging.getLogger(__name__)

@dataclass
class HopResult:
    """Clase para almacenar resultados de un hop individual."""
    hop_number: int
    ip_address: str = None
    latencies: List[float] = field(default_factory=list)
    response_types: List[str] = field(default_factory=list)
    sent_count: int = 0
    received_count: int = 0
    
    @property
    def avg_latency(self) -> Optional[float]:
        """Calcula la latencia promedio."""
        if not self.latencies:
            return None
        return sum(self.latencies) / len(self.latencies)
    
    @property
    def min_latency(self) -> Optional[float]:
        """Obtiene la latencia mínima."""
        if not self.latencies:
            return None
        return min(self.latencies)
    
    @property
    def max_latency(self) -> Optional[float]:
        """Obtiene la latencia máxima."""
        if not self.latencies:
            return None
        return max(self.latencies)
    
    @property
    def packet_loss(self) -> float:
        """Calcula el porcentaje de pérdida de paquetes."""
        if self.sent_count == 0:
            return 0.0
        return (1 - (self.received_count / self.sent_count)) * 100
    
    def to_dict(self) -> Dict[str, Any]:
        """Convierte el resultado a un diccionario."""
        return {
            'hop_number': self.hop_number,
            'ip_address': self.ip_address,
            'latencies': self.latencies,
            'avg_latency': self.avg_latency,
            'min_latency': self.min_latency,
            'max_latency': self.max_latency,
            'sent_count': self.sent_count,
            'received_count': self.received_count,
            'packet_loss': self.packet_loss,
            'response_types': self.response_types
        }

@dataclass
class MTRResult:
    """Clase para almacenar resultados completos de MTR."""
    destination: str
    source: str = None
    start_time: float = field(default_factory=time.time)
    end_time: float = None
    hops: List[HopResult] = field(default_factory=list)
    status: str = "pending"
    error: str = None
    
    def add_hop(self, hop_result: HopResult) -> None:
        """Añade un hop al resultado."""
        self.hops.append(hop_result)
    
    def complete(self, status: str = "completed", error: str = None) -> None:
        """Marca el resultado como completado."""
        self.end_time = time.time()
        self.status = status
        self.error = error
    
    def to_dict(self) -> Dict[str, Any]:
        """Convierte el resultado a un diccionario."""
        return {
            'destination': self.destination,
            'source': self.source,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'duration': self.end_time - self.start_time if self.end_time else None,
            'status': self.status,
            'error': self.error,
            'hops': [hop.to_dict() for hop in self.hops]
        }

class MTRRunner:
    """Clase para ejecutar análisis MTR."""
    
    def __init__(self, storage=None):
        """
        Inicializa el runner de MTR.
        
        Args:
            storage: Instancia de la clase de almacenamiento (opcional).
        """
        self.storage = storage
        self.default_options = {
            'count': 3,                # Número de pings por hop
            'timeout': 1.0,            # Timeout por ping (segundos)
            'interval': 0.1,           # Intervalo entre pings (segundos)
            'max_hops': 30,            # Número máximo de hops
            'max_unknown_hops': 3,     # Número máximo de hops desconocidos consecutivos
            'hop_sleep': 0.05,         # Tiempo entre hops distintos (segundos)
            'parallel_jobs': 10        # Número máximo de trabajos paralelos
        }
        self.scan_jobs = queue.Queue()
        self.scan_threads = []
        self.running = False
        self.stop_event = threading.Event()
    
    def set_options(self, options: Dict[str, Any]) -> None:
        """
        Actualiza las opciones de configuración.
        
        Args:
            options: Diccionario con las opciones a actualizar.
        """
        self.default_options.update(options)
    
    def trace_route(self, destination: str, options: Dict[str, Any] = None) -> MTRResult:
        """
        Ejecuta un análisis de traceroute + estadísticas (MTR).
        
        Args:
            destination: IP de destino.
            options: Opciones específicas para este análisis (opcional).
            
        Returns:
            Objeto MTRResult con los resultados del análisis.
        """
        # Fusionar opciones predeterminadas con las proporcionadas
        if options is None:
            options = {}
        actual_options = {**self.default_options, **options}
        
        # Validar dirección IP
        try:
            ipaddress.ip_address(destination)
        except ValueError:
            result = MTRResult(destination=destination)
            result.complete(status="error", error="Dirección IP inválida")
            return result
        
        # Crear objeto de resultado
        result = MTRResult(destination=destination)
        
        # Intentar determinar la IP de origen
        try:
            # Crear un socket temporal para determinar la IP de origen
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect((destination, 80))  # El puerto es irrelevante
            result.source = s.getsockname()[0]
            s.close()
        except Exception as e:
            logger.warning(f"No se pudo determinar la IP de origen: {str(e)}")
        
        # Realizar traceroute
        unknown_hop_count = 0
        
        for ttl in range(1, actual_options['max_hops'] + 1):
            hop_result = HopResult(hop_number=ttl)
            
            # Realizar múltiples pings para este hop
            for i in range(actual_options['count']):
                hop_result.sent_count += 1
                
                try:
                    addr, rtt, response_type = send_receive_icmp(
                        destination, 
                        ttl=ttl,
                        timeout=actual_options['timeout']
                    )
                    
                    # Registrar resultado
                    if hop_result.ip_address is None:
                        hop_result.ip_address = addr
                    
                    hop_result.received_count += 1
                    hop_result.latencies.append(rtt)
                    hop_result.response_types.append(response_type)
                    
                    # Si es el destino final y hemos recibido una respuesta echo_reply, hemos llegado
                    if response_type == 'echo_reply' and addr == destination:
                        unknown_hop_count = 0  # Resetear contador de hops desconocidos
                    
                except ICMPTimeoutError:
                    # Timeout - no se recibió respuesta
                    hop_result.response_types.append('timeout')
                    unknown_hop_count += 1
                    
                except (ICMPPermissionError, ICMPNetworkError) as e:
                    # Error de permisos o de red
                    logger.error(f"Error en hop {ttl}: {str(e)}")
                    hop_result.response_types.append('error')
                    result.complete(status="error", error=str(e))
                    return result
                
                # Esperar antes del siguiente ping (excepto el último)
                if i < actual_options['count'] - 1:
                    time.sleep(actual_options['interval'])
            
            # Añadir el hop al resultado
            result.add_hop(hop_result)
            
            # Esperar entre hops
            time.sleep(actual_options['hop_sleep'])
            
            # Si hemos llegado al destino, terminamos
            if any(resp == 'echo_reply' for resp in hop_result.response_types) and hop_result.ip_address == destination:
                break
                
            # Si hay demasiados hops desconocidos consecutivos, terminamos
            if unknown_hop_count >= actual_options['max_unknown_hops']:
                logger.warning(f"Demasiados hops desconocidos consecutivos ({unknown_hop_count}). Finalizando traceroute.")
                break
        
        # Marcar como completado
        result.complete()
        
        # Guardar en almacenamiento si está disponible
        if self.storage:
            try:
                self.storage.store_mtr_result(result)
            except Exception as e:
                logger.error(f"Error al guardar resultado en almacenamiento: {str(e)}")
        
        return result
    
    def _worker(self) -> None:
        """
        Función de trabajo para el hilo de escaneo.
        Procesa trabajos de la cola hasta que se detiene.
        """
        while not self.stop_event.is_set():
            try:
                # Obtener un trabajo de la cola con timeout
                job = self.scan_jobs.get(timeout=1.0)
                
                # Ejecutar el trabajo
                destination, options, callback = job
                
                logger.info(f"Iniciando escaneo de {destination}")
                result = self.trace_route(destination, options)
                
                # Ejecutar callback si existe
                if callback:
                    try:
                        callback(result)
                    except Exception as e:
                        logger.error(f"Error en callback para {destination}: {str(e)}")
                
                # Marcar trabajo como completado
                self.scan_jobs.task_done()
                
            except queue.Empty:
                # No hay trabajos, esperar
                continue
            except Exception as e:
                logger.error(f"Error en worker de escaneo: {str(e)}")
    
    def start_scan_loop(self, parallel_jobs: int = None) -> None:
        """
        Inicia los hilos de escaneo en segundo plano.
        
        Args:
            parallel_jobs: Número de hilos de escaneo paralelos.
        """
        if self.running:
            logger.warning("El bucle de escaneo ya está en ejecución")
            return
        
        self.running = True
        self.stop_event.clear()
        
        if parallel_jobs is None:
            parallel_jobs = self.default_options['parallel_jobs']
        
        # Crear y arrancar los hilos de escaneo
        for i in range(parallel_jobs):
            thread = threading.Thread(target=self._worker, daemon=True)
            thread.start()
            self.scan_threads.append(thread)
        
        logger.info(f"Iniciado bucle de escaneo con {parallel_jobs} trabajadores")
    
    def stop_scan_loop(self, wait: bool = True) -> None:
        """
        Detiene los hilos de escaneo.
        
        Args:
            wait: Si es True, espera a que todos los trabajos pendientes terminen.
        """
        if not self.running:
            logger.warning("El bucle de escaneo no está en ejecución")
            return
        
        self.running = False
        self.stop_event.set()
        
        if wait:
            # Esperar a que se completen todos los trabajos pendientes
            self.scan_jobs.join()
        
        # Esperar a que terminen los hilos
        for thread in self.scan_threads:
            thread.join(timeout=1.0)
        
        # Limpiar lista de hilos
        self.scan_threads = []
        
        logger.info("Detenido bucle de escaneo")
    
    def schedule_scan(self, destination: str, options: Dict[str, Any] = None, callback=None) -> None:
        """
        Programa un escaneo para ser ejecutado por los hilos de trabajo.
        
        Args:
            destination: IP de destino.
            options: Opciones específicas para este análisis (opcional).
            callback: Función a llamar con el resultado (opcional).
        """
        if not self.running:
            logger.warning("El bucle de escaneo no está en ejecución. Iniciando...")
            self.start_scan_loop()
        
        self.scan_jobs.put((destination, options, callback))
        logger.debug(f"Programado escaneo para {destination}")
    
    def scan_all_agents(self, agents: List[Dict[str, Any]], randomize_interval: bool = True) -> None:
        """
        Programa escaneos para todos los agentes.
        
        Args:
            agents: Lista de diccionarios con información de agentes.
            randomize_interval: Si es True, añade intervalos aleatorios entre escaneos.
        """
        for agent in agents:
            # Verificar que el agente esté habilitado
            if not agent.get('enabled', True):
                logger.debug(f"Agente {agent['ip']} deshabilitado, omitiendo")
                continue
            
            # Programar escaneo
            self.schedule_scan(agent['ip'], agent.get('options'))
            
            # Añadir intervalo aleatorio si se solicita
            if randomize_interval and len(agents) > 1:
                time.sleep(random.uniform(0.1, 0.5))
