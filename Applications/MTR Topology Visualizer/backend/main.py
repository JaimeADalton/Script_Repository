#!/usr/bin/env python3
"""
Punto de entrada principal para mtr-topology.
Coordina los distintos componentes del sistema.
"""

import os
import sys
import time
import logging
import threading
import signal
import random
from typing import Dict, Any, List

# Importar módulos propios
from config import config, load_from_args
from core.storage import InfluxStorage
from core.mtr import MTRRunner
from web.app import app, init_app, shutdown_app

# Configuración del logger
logger = logging.getLogger(__name__)

class MTRTopologyService:
    """Clase principal del servicio MTR Topology."""
    
    def __init__(self):
        """Inicializa el servicio."""
        self.storage = None
        self.mtr_runner = None
        self.flask_app = app
        self.scheduler_thread = None
        self.running = False
        self.stop_event = threading.Event()
    
    def init(self) -> None:
        """Inicializa los componentes del sistema."""
        logger.info("Inicializando servicio MTR Topology...")
        
        # Inicializar almacenamiento
        logger.info("Inicializando almacenamiento...")
        self.storage = InfluxStorage(
            host=config.get('storage.host', 'localhost'),
            port=config.get('storage.port', 8086),
            username=config.get('storage.username'),
            password=config.get('storage.password'),
            database=config.get('storage.database', 'mtr_topology'),
            ssl=config.get('storage.ssl', False),
            verify_ssl=config.get('storage.verify_ssl', False),
            default_tags=config.get('storage.default_tags', {})
        )
        
        # Inicializar MTR runner
        logger.info("Inicializando MTR runner...")
        self.mtr_runner = MTRRunner(storage=self.storage)
        
        # Configurar opciones de MTR
        mtr_options = config.get('mtr', {})
        if mtr_options:
            self.mtr_runner.set_options(mtr_options)
        
        # Inicializar aplicación Flask
        logger.info("Inicializando API web...")
        app_config = {
            'storage': config.get('storage'),
            'mtr': config.get('mtr'),
            'auto_start_scan': config.get('scan.auto_start', True),
            'scan_on_start': config.get('scan.scan_on_start', True),
            'discover_telegraf': config.get('scan.discover_telegraf', True),
            'telegraf_config_dir': config.get('scan.telegraf_config_dir', '/etc/telegraf/telegraf.d'),
            'parallel_jobs': config.get('mtr.parallel_jobs', 10)
        }
        init_app(app_config)
        
        logger.info("Servicio inicializado")
    
    def _scheduler(self) -> None:
        """
        Función del hilo programador de escaneos periódicos.
        Programa escaneos con el intervalo configurado.
        """
        scan_interval = config.get('scan.scan_interval', 300)  # Por defecto, cada 5 minutos
        
        logger.info(f"Iniciando programador de escaneos (intervalo: {scan_interval}s)")
        
        while not self.stop_event.is_set():
            try:
                # Obtener agentes
                agents = self.storage.query_agents()
                
                if not agents:
                    # Si no hay agentes, intentar descubrir desde Telegraf
                    if config.get('scan.discover_telegraf', True):
                        config_dir = config.get('scan.telegraf_config_dir', '/etc/telegraf/telegraf.d')
                        agents = self.storage.parse_telegraf_configs(config_dir)
                
                if agents:
                    logger.info(f"Programando escaneo para {len(agents)} agentes")
                    self.mtr_runner.scan_all_agents(agents, randomize_interval=True)
                else:
                    logger.warning("No se encontraron agentes para escanear")
                
                # Esperar hasta el próximo intervalo o hasta que se solicite detener
                self.stop_event.wait(scan_interval)
                
            except Exception as e:
                logger.error(f"Error en programador de escaneos: {str(e)}")
                # Esperar un poco antes de reintentar en caso de error
                time.sleep(10)

    def start(self) -> None:
        """Inicia el servicio."""
        if self.running:
            logger.warning("El servicio ya está en ejecución")
            return
    
        logger.info("Iniciando servicio MTR Topology...")
    
        self.running = True
        self.stop_event.clear()
    
        # Iniciar MTR runner si auto_start está habilitado
        if config.get('scan.auto_start', True):
            logger.info("Iniciando bucle de escaneo MTR...")
            parallel_jobs = config.get('mtr.parallel_jobs', 10)
            self.mtr_runner.start_scan_loop(parallel_jobs)
    
        # Iniciar hilo programador si scan_interval > 0
        scan_interval = config.get('scan.scan_interval', 300)
        if scan_interval > 0:
            logger.info("Iniciando programador de escaneos...")
            self.scheduler_thread = threading.Thread(target=self._scheduler, daemon=True)
            self.scheduler_thread.start()
    
        # Iniciar aplicación Flask
        web_host = config.get('web.host', '0.0.0.0')
        web_port = config.get('web.port', 5000)
        web_debug = config.get('web.debug', False)
    
        logger.info(f"Iniciando API web en {web_host}:{web_port}...")
    
        # En modo no debug, Flask se ejecuta en un hilo separado
        if not web_debug:
            def run_flask():
                self.flask_app.run(host=web_host, port=web_port, debug=False, use_reloader=False)
    
            flask_thread = threading.Thread(target=run_flask, daemon=False)  # Cambiado a no daemon
            flask_thread.start()
    
            # Bloquear para evitar que el programa principal termine
            try:
                # Esperar indefinidamente o hasta señal de parada
                while not self.stop_event.is_set():
                    time.sleep(1)
            except KeyboardInterrupt:
                logger.info("Recibido Ctrl+C, deteniendo servicio...")
                self.stop()
        else:
            # En modo debug, Flask debe ejecutarse en el hilo principal
            self.flask_app.run(host=web_host, port=web_port, debug=True, use_reloader=False)

    
    def stop(self) -> None:
        """Detiene el servicio."""
        if not self.running:
            logger.warning("El servicio no está en ejecución")
            return
        
        logger.info("Deteniendo servicio MTR Topology...")
        
        self.running = False
        self.stop_event.set()
        
        # Detener MTR runner
        if self.mtr_runner and self.mtr_runner.running:
            logger.info("Deteniendo bucle de escaneo MTR...")
            self.mtr_runner.stop_scan_loop(wait=True)
        
        # Detener hilo programador
        if self.scheduler_thread:
            logger.info("Deteniendo programador de escaneos...")
            self.scheduler_thread.join(timeout=2.0)
            self.scheduler_thread = None
        
        # Detener aplicación Flask
        logger.info("Deteniendo API web...")
        shutdown_app()
        
        logger.info("Servicio detenido")

def handle_signal(signum, frame):
    """Manejador de señales para detener el servicio."""
    logger.info(f"Recibida señal {signum}, deteniendo servicio...")
    if service:
        service.stop()
    sys.exit(0)

# Instancia global del servicio
service = None

if __name__ == "__main__":
    # Cargar configuración desde argumentos
    load_from_args()
    
    # Registrar manejadores de señales
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)
    
    # Crear e inicializar servicio
    service = MTRTopologyService()
    service.init()
    
    try:
        # Iniciar servicio
        service.start()
    except KeyboardInterrupt:
        # Capturar Ctrl+C
        logger.info("Recibido Ctrl+C, deteniendo servicio...")
        service.stop()
    except Exception as e:
        logger.error(f"Error al ejecutar servicio: {str(e)}")
        service.stop()
        sys.exit(1)
