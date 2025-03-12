#!/usr/bin/env python3
import os
import sys
import argparse
import logging
from threading import Thread

# Configurar path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

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
    parser.add_argument('--discover', action='store_true',
                        help='Descubrir agentes desde Telegraf al iniciar')
    parser.add_argument('--telegraf-path', type=str, default='/etc/telegraf/telegraf.d/',
                        help='Ruta a los archivos de configuración de Telegraf')
    
    return parser.parse_args()

def main():
    """Función principal."""
    args = parse_args()
    
    # Configurar logging
    log_level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler("mtr_topology.log"),
            logging.StreamHandler()
        ]
    )
    logger = logging.getLogger(__name__)
    
    logger.info("Iniciando MTR Topology Visualizer")
    
    # Inicializar almacenamiento
    from core.storage import MTRStorage
    storage = MTRStorage()
    
    # Descubrir agentes si se solicita
    if args.discover:
        logger.info(f"Descubriendo agentes desde {args.telegraf_path}")
        try:
            agents = storage.discover_from_telegraf(args.telegraf_path)
            logger.info(f"Se descubrieron {len(agents)} agentes")
        except Exception as e:
            logger.error(f"Error al descubrir agentes: {e}")
    
    # Iniciar el servidor web en un hilo separado
    from web.app import app, init_app
    
    # Pasar configuración a la aplicación
    config = {
        'scan_interval': args.scan_interval,
        'debug': args.debug
    }
    
    # Inicializar la aplicación
    init_app(config)
    
    # Iniciar el servidor
    logger.info(f"Iniciando servidor web en {args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=args.debug)

if __name__ == '__main__':
    main()
