#!/usr/bin/env python3
import os
import sys
import argparse
import logging
import signal
import threading
from threading import Thread
import time

# Configurar path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

# Evento global para señalizar terminación
stop_event = threading.Event()

def parse_args():
    """Procesa los argumentos de línea de comandos."""
    parser = argparse.ArgumentParser(description='MTR Topology Visualizer')
    
    parser.add_argument('--port', type=int, default=8088,
                        help='Puerto para el servidor web (predeterminado: 8088)')
    parser.add_argument('--host', type=str, default='0.0.0.0',
                        help='Host para el servidor web (predeterminado: 0.0.0.0)')
    parser.add_argument('--debug', action='store_true',
                        help='Ejecutar en modo debug')
    parser.add_argument('--scan-interval', type=int, default=300,
                        help='Intervalo de escaneo en segundos (predeterminado: 300)')
    parser.add_argument('--max-hops', type=int, default=30,
                        help='Número máximo de saltos a sondear (predeterminado: 30)')
    parser.add_argument('--max-unknown-hops', type=int, default=5,
                        help='Número máximo de saltos desconocidos permitidos (predeterminado: 5)')
    parser.add_argument('--max-concurrent', type=int, default=20,
                        help='Número máximo de MTRs concurrentes (predeterminado: 20)')
    parser.add_argument('--buffer-size', type=int, default=10,
                        help='Tamaño del buffer para estadísticas (predeterminado: 10)')
    parser.add_argument('--db-path', type=str, default='mtr_data.db',
                        help='Ruta a la base de datos SQLite (predeterminado: mtr_data.db)')
    parser.add_argument('--retention-days', type=int, default=7,
                        help='Días de retención para datos históricos (predeterminado: 7)')
    parser.add_argument('--discover', action='store_true',
                        help='Descubrir agentes desde Telegraf al iniciar')
    parser.add_argument('--telegraf-path', type=str, default='/etc/telegraf/telegraf.d/',
                        help='Ruta a los archivos de configuración de Telegraf')
    parser.add_argument('--log-file', type=str, default='mtr_topology.log',
                        help='Archivo de log (predeterminado: mtr_topology.log)')
    parser.add_argument('--log-level', type=str, default='INFO',
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                        help='Nivel de logging (predeterminado: INFO)')
    parser.add_argument('--production', action='store_true',
                        help='Ejecutar en modo producción con uWSGI')
    
    return parser.parse_args()

def setup_logging(args):
    """Configura el sistema de logging."""
    log_level = getattr(logging, args.log_level)
    
    # Crear directorio de logs si no existe
    log_dir = os.path.dirname(args.log_file)
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir)
    
    # Configurar formato de log
    log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # Configurar logging
    logging.basicConfig(
        level=log_level,
        format=log_format,
        handlers=[
            logging.FileHandler(args.log_file),
            logging.StreamHandler()
        ]
    )
    
    # Reducir verbosidad de algunos loggers de terceros
    logging.getLogger('werkzeug').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
    
    logger = logging.getLogger(__name__)
    logger.info(f"Logging configurado en nivel {args.log_level}")
    
    return logger

def signal_handler(signum, frame):
    """Manejador de señales para terminación limpia."""
    logger = logging.getLogger(__name__)
    logger.info(f"Señal recibida: {signum}. Iniciando cierre...")
    stop_event.set()

def setup_signal_handlers():
    """Configura manejadores de señales para cierre limpio."""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

def main():
    """Función principal."""
    # Procesar argumentos
    args = parse_args()
    
    # Configurar logging
    logger = setup_logging(args)
    
    # Configurar manejadores de señales
    setup_signal_handlers()
    
    logger.info("Iniciando MTR Topology Visualizer")
    
    # Inicializar almacenamiento
    from core.storage import MTRStorage
    storage = MTRStorage(db_path=args.db_path, retention_days=args.retention_days)
    
    # Descubrir agentes si se solicita
    if args.discover:
        logger.info(f"Descubriendo agentes desde {args.telegraf_path}")
        try:
            agents = storage.discover_from_telegraf(args.telegraf_path)
            logger.info(f"Se descubrieron {len(agents)} agentes")
        except Exception as e:
            logger.error(f"Error al descubrir agentes: {e}")
    
    # Iniciar el servidor web
    from web.app import app, init_app, shutdown_server
    
    # Pasar configuración a la aplicación
    config = {
        'scan_interval': args.scan_interval,
        'debug': args.debug,
        'max_hops': args.max_hops,
        'max_unknown_hops': args.max_unknown_hops,
        'max_concurrent': args.max_concurrent,
        'buffer_size': args.buffer_size,
        'storage': storage,
        'stop_event': stop_event
    }
    
    # Inicializar la aplicación
    init_app(config)
    
    # Modo de ejecución: desarrollo o producción
    if args.production:
        # En producción, no ejecutamos el servidor directamente
        # Se espera que se use con uWSGI o similar
        logger.info("Aplicación inicializada en modo producción")
        
        # Esperar señal de terminación
        while not stop_event.is_set():
            time.sleep(1)
    else:
        # Modo desarrollo
        flask_thread = Thread(target=lambda: app.run(
            host=args.host, 
            port=args.port, 
            debug=args.debug,
            use_reloader=False  # Evitar problemas con threads duplicados
        ))
        flask_thread.daemon = True
        flask_thread.start()
        
        logger.info(f"Servidor web iniciado en {args.host}:{args.port}")
        
        # Esperar señal de terminación
        try:
            while not stop_event.is_set():
                time.sleep(1)
        except:
            stop_event.set()
        
    # Cierre limpio
    logger.info("Iniciando cierre limpio...")
    
    # Cerrar almacenamiento
    try:
        storage.shutdown()
    except Exception as e:
        logger.error(f"Error al cerrar almacenamiento: {e}")
    
    # Cerrar servidor web
    try:
        shutdown_server()
    except Exception as e:
        logger.error(f"Error al cerrar servidor web: {e}")
    
    logger.info("MTR Topology Visualizer cerrado correctamente")

if __name__ == '__main__':
    main()
