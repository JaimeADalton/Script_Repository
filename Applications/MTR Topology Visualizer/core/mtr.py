#!/usr/bin/env python3
import time
import random
import socket
import threading
import collections
from concurrent.futures import ThreadPoolExecutor

from .icmp import send_discover_icmp, ICMPReturn

class HopStatistic:
    """Estadísticas para un salto particular en una ruta."""
    
    def __init__(self, ttl, timeout, ring_buffer_size=10):
        self.ttl = ttl
        self.timeout = timeout
        self.sent = 0
        self.lost = 0
        self.last = ICMPReturn()
        self.best = ICMPReturn(elapsed=float('inf'))
        self.worst = ICMPReturn(elapsed=0)
        self.sum_elapsed = 0
        self.targets = []
        self.ring_buffer_size = ring_buffer_size
        self.packets = collections.deque(maxlen=ring_buffer_size)
        self.dest = None
        self.pid = 0
    
    def update(self, icmp_return):
        """Actualiza las estadísticas con un nuevo resultado ICMP."""
        self.last = icmp_return
        self.sent += 1
        
        # Actualizar lista de targets
        if icmp_return.addr and icmp_return.addr not in self.targets:
            self.targets.append(icmp_return.addr)
        
        # Añadir al buffer circular
        self.packets.append(icmp_return)
        
        if not icmp_return.success:
            self.lost += 1
            return
        
        # Actualizar estadísticas solo para paquetes exitosos
        self.sum_elapsed += icmp_return.elapsed
        
        if not self.best.success or self.best.elapsed > icmp_return.elapsed:
            self.best = icmp_return
        
        if self.worst.elapsed < icmp_return.elapsed:
            self.worst = icmp_return
    
    def loss_percent(self):
        """Retorna el porcentaje de paquetes perdidos."""
        if self.sent == 0:
            return 0
        return (self.lost / self.sent) * 100
    
    def avg_ms(self):
        """Retorna la latencia promedio en milisegundos."""
        if self.sent - self.lost == 0:
            return 0
        return (self.sum_elapsed / (self.sent - self.lost)) * 1000
    
    def to_dict(self):
        """Convierte las estadísticas a un diccionario."""
        return {
            'ttl': self.ttl,
            'target': self.targets,
            'sent': self.sent,
            'loss_percent': self.loss_percent(),
            'last_ms': self.last.elapsed * 1000 if self.last.success else None,
            'avg_ms': self.avg_ms(),
            'best_ms': self.best.elapsed * 1000 if self.best.success else None,
            'worst_ms': self.worst.elapsed * 1000 if self.worst.success else None,
            'packets': [{'success': p.success, 'elapsed_ms': p.elapsed * 1000 if p.success else None} 
                      for p in self.packets]
        }

class MTR:
    """Implementación del tracer MTR (combinación de traceroute y ping)."""
    
    def __init__(self, address, src_address="", timeout=1.0, interval=1.0, 
                 hop_sleep=0.1, max_hops=30, max_unknown_hops=5, 
                 ring_buffer_size=10, ptr_lookup=False):
        """
        Inicializa un nuevo MTR.
        
        Args:
            address: IP o hostname de destino
            src_address: IP de origen (vacía para usar la predeterminada)
            timeout: Tiempo de espera para cada paquete ICMP
            interval: Intervalo entre rondas de sondeo
            hop_sleep: Tiempo de espera entre saltos
            max_hops: Número máximo de saltos a sondear
            max_unknown_hops: Número máximo de saltos desconocidos permitidos
            ring_buffer_size: Tamaño del buffer circular para estadísticas
            ptr_lookup: Si se debe realizar resolución DNS inversa
        """
        # Resolución de nombres si es necesario
        if not socket.inet_aton(address):
            try:
                address = socket.gethostbyname(address)
            except socket.gaierror:
                raise ValueError(f"No se puede resolver el host: {address}")
        
        # IP de origen predeterminada si no se proporciona
        if not src_address:
            src_address = "0.0.0.0"
        
        self.src_address = src_address
        self.address = address
        self.timeout = timeout
        self.interval = interval
        self.hop_sleep = hop_sleep
        self.max_hops = max_hops
        self.max_unknown_hops = max_unknown_hops
        self.ring_buffer_size = ring_buffer_size
        self.ptr_lookup = ptr_lookup
        
        self.statistics = {}  # ttl -> HopStatistic
        self.mutex = threading.RLock()
        self.stop_event = threading.Event()
    
    def register_statistic(self, ttl, icmp_return):
        """Registra una nueva estadística para un salto."""
        with self.mutex:
            if ttl not in self.statistics:
                self.statistics[ttl] = HopStatistic(ttl, self.timeout, self.ring_buffer_size)
            
            s = self.statistics[ttl]
            s.update(icmp_return)
            return s
    
    def discover(self, count=10, callback=None):
        """
        Descubre la ruta al destino enviando paquetes ICMP.
        
        Args:
            count: Número de veces que se debe recorrer la ruta
            callback: Función a llamar después de cada actualización
        """
        # ID aleatorio para los paquetes ICMP
        id_num = random.randint(1, 65535) & 0xFFFF
        seq = random.randint(1, 65535)
        
        for i in range(count):
            if self.stop_event.is_set():
                break
                
            time.sleep(self.interval)
            
            unknown_hops_count = 0
            for ttl in range(1, self.max_hops + 1):
                if self.stop_event.is_set():
                    break
                    
                time.sleep(self.hop_sleep)
                seq += 1
                
                # Enviar paquete ICMP
                icmp_return = send_discover_icmp(self.address, ttl, id_num, self.timeout, seq)
                
                # Registrar resultado
                s = self.register_statistic(ttl, icmp_return)
                s.dest = self.address
                s.pid = id_num
                
                # Notificar actualización
                if callback:
                    callback(ttl, s)
                
                # Si llegamos al destino, terminar
                if icmp_return.addr == self.address:
                    break
                
                # Gestionar saltos desconocidos
                if not icmp_return.success:
                    unknown_hops_count += 1
                    if unknown_hops_count >= self.max_unknown_hops:
                        break
                    continue
                
                unknown_hops_count = 0
    
    def run(self, count=10, callback=None):
        """Ejecuta el MTR en un hilo separado."""
        thread = threading.Thread(target=self.discover, args=(count, callback))
        thread.daemon = True
        thread.start()
        return thread
    
    def stop(self):
        """Detiene el MTR en ejecución."""
        self.stop_event.set()
    
    def get_statistics(self):
        """Retorna todas las estadísticas actuales."""
        with self.mutex:
            return {ttl: stat.to_dict() for ttl, stat in self.statistics.items()}
    
    def get_route(self):
        """Retorna la ruta completa al destino."""
        with self.mutex:
            route = []
            for ttl in sorted(self.statistics.keys()):
                stat = self.statistics[ttl]
                if stat.targets:
                    route.append({
                        'ttl': ttl,
                        'ip': stat.targets[0] if stat.targets else None,
                        'loss': stat.loss_percent(),
                        'latency': stat.avg_ms()
                    })
            return route

class MTRManager:
    """Gestiona múltiples instancias de MTR para diferentes destinos."""
    
    def __init__(self, max_concurrent=20, **mtr_options):
        """
        Inicializa el gestor MTR.
        
        Args:
            max_concurrent: Número máximo de MTRs concurrentes
            mtr_options: Opciones para pasar a las instancias de MTR
        """
        self.mtrs = {}  # address -> MTR
        self.mutex = threading.RLock()
        self.max_concurrent = max_concurrent
        self.mtr_options = mtr_options
        self.executor = ThreadPoolExecutor(max_workers=max_concurrent)
    
    def add_target(self, address, callback=None):
        """Añade un nuevo destino para monitorear."""
        with self.mutex:
            if address in self.mtrs:
                return False
            
            try:
                mtr = MTR(address, **self.mtr_options)
                self.mtrs[address] = mtr
                
                # Ejecutar MTR en segundo plano
                future = self.executor.submit(mtr.discover, 1, callback)
                future.add_done_callback(lambda f: self._handle_completion(address, f))
                
                return True
            except Exception as e:
                print(f"Error al añadir destino {address}: {e}")
                return False
    
    def _handle_completion(self, address, future):
        """Maneja la finalización de un MTR."""
        try:
            future.result()  # Obtener resultado o excepción
        except Exception as e:
            print(f"Error en MTR para {address}: {e}")
    
    def remove_target(self, address):
        """Elimina un destino del monitoreo."""
        with self.mutex:
            if address not in self.mtrs:
                return False
            
            mtr = self.mtrs[address]
            mtr.stop()
            del self.mtrs[address]
            return True
    
    def get_all_routes(self):
        """Obtiene todas las rutas de todos los destinos."""
        with self.mutex:
            return {addr: mtr.get_route() for addr, mtr in self.mtrs.items()}
    
    def get_topology_data(self):
        """
        Construye datos de topología a partir de todas las rutas.
        Retorna un diccionario con nodos y enlaces para visualización.
        """
        with self.mutex:
            nodes = {}
            links = {}
            
            # Añadir nodo de origen (servidor local)
            nodes["local"] = {
                'id': "local",
                'name': "Local Server",
                'ip': self.mtr_options.get('src_address', "0.0.0.0"),
                'type': "source"
            }
            
            # Procesar cada MTR
            for addr, mtr in self.mtrs.items():
                stats = mtr.get_statistics()
                
                # Añadir nodo de destino
                nodes[addr] = {
                    'id': addr,
                    'name': addr,
                    'ip': addr,
                    'type': "destination"
                }
                
                prev_hop = "local"
                for ttl in sorted(stats.keys()):
                    stat = stats[ttl]
                    
                    # Saltarse los hops sin respuesta
                    if not stat['target'] or len(stat['target']) == 0:
                        continue
                    
                    # Usar el primer target como representativo
                    target = stat['target'][0]
                    hop_id = f"hop_{target.replace('.', '_')}"
                    
                    # Añadir nodo para este hop si no existe
                    if hop_id not in nodes:
                        nodes[hop_id] = {
                            'id': hop_id,
                            'name': target,
                            'ip': target,
                            'type': "router"
                        }
                    
                    # Crear enlace para este hop
                    link_id = f"{prev_hop}-{hop_id}"
                    if link_id not in links:
                        links[link_id] = {
                            'id': link_id,
                            'source': prev_hop,
                            'target': hop_id,
                            'destinations': [addr],
                            'latency': stat['avg_ms'],
                            'loss': stat['loss_percent']
                        }
                    else:
                        # Actualizar enlace existente
                        if addr not in links[link_id]['destinations']:
                            links[link_id]['destinations'].append(addr)
                        # Promediar latencia y pérdida
                        links[link_id]['latency'] = (links[link_id]['latency'] + stat['avg_ms']) / 2
                        links[link_id]['loss'] = (links[link_id]['loss'] + stat['loss_percent']) / 2
                    
                    prev_hop = hop_id
                
                # Enlace final al destino
                link_id = f"{prev_hop}-{addr}"
                if prev_hop != "local":  # Evitar enlace directo si solo hay un salto
                    links[link_id] = {
                        'id': link_id,
                        'source': prev_hop,
                        'target': addr,
                        'destinations': [addr],
                        'latency': stats[max(stats.keys())]['avg_ms'],
                        'loss': stats[max(stats.keys())]['loss_percent']
                    }
            
            return {
                'nodes': list(nodes.values()),
                'links': list(links.values())
            }
    
    def scan_all(self, count=1, callback=None):
        """Escanea todos los destinos actualmente monitoreados."""
        futures = []
        
        with self.mutex:
            for addr, mtr in self.mtrs.items():
                future = self.executor.submit(mtr.discover, count, callback)
                futures.append(future)
        
        # Esperar a que todos terminen
        for future in futures:
            try:
                future.result()
            except Exception as e:
                print(f"Error en escaneo: {e}")

