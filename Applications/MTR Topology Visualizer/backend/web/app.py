#!/usr/bin/env python3
"""
API REST para mtr-topology.
Proporciona endpoints para la plataforma web.
"""

import os
import sys
import json
import logging
from typing import Dict, Any, List, Optional
from flask import Flask, request, jsonify, g
import threading
import time

# Agregar directorio raíz al path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core.mtr import MTRRunner
from core.storage import InfluxStorage

# Configuración del logger
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Variables globales
mtr_runner = None
storage = None
config = {}

def init_app(app_config: Dict[str, Any] = None) -> None:
    """
    Inicializa la aplicación Flask con las dependencias necesarias.
    
    Args:
        app_config: Configuración de la aplicación.
    """
    global mtr_runner, storage, config
    
    if app_config is None:
        app_config = {}
    
    config = app_config
    
    # Inicializar almacenamiento
    storage_config = app_config.get('storage', {})
    storage = InfluxStorage(
        host=storage_config.get('host', 'localhost'),
        port=storage_config.get('port', 8086),
        username=storage_config.get('username'),
        password=storage_config.get('password'),
        database=storage_config.get('database', 'mtr_topology'),
        ssl=storage_config.get('ssl', False),
        verify_ssl=storage_config.get('verify_ssl', False),
        default_tags=storage_config.get('default_tags', {})
    )
    
    # Inicializar MTR runner
    mtr_runner = MTRRunner(storage=storage)
    
    # Configurar opciones de MTR
    mtr_options = app_config.get('mtr', {})
    if mtr_options:
        mtr_runner.set_options(mtr_options)
    
    # Iniciar bucle de escaneo si se solicita
    if app_config.get('auto_start_scan', True):
        parallel_jobs = app_config.get('parallel_jobs', 10)
        mtr_runner.start_scan_loop(parallel_jobs)
        
        # Programar escaneo inicial de agentes si se solicita
        if app_config.get('scan_on_start', True):
            # Programar escaneo en un hilo separado para no bloquear el arranque
            def initial_scan():
                time.sleep(2)  # Dar tiempo a que la aplicación se inicie
                try:
                    # Primero, buscar agentes de Telegraf
                    if app_config.get('discover_telegraf', True):
                        config_dir = app_config.get('telegraf_config_dir', '/etc/telegraf/telegraf.d')
                        agents = storage.parse_telegraf_configs(config_dir)
                        logger.info(f"Descubiertos {len(agents)} agentes de Telegraf")
                    else:
                        # Si no se descubren, obtener de la base de datos
                        agents = storage.query_agents()
                    
                    # Programar escaneo para todos los agentes
                    if agents:
                        logger.info(f"Programando escaneo inicial para {len(agents)} agentes")
                        mtr_runner.scan_all_agents(agents)
                    else:
                        logger.warning("No se encontraron agentes para escanear")
                
                except Exception as e:
                    logger.error(f"Error en escaneo inicial: {str(e)}")
            
            threading.Thread(target=initial_scan, daemon=True).start()
    
    logger.info("Aplicación inicializada")

@app.before_request
def before_request():
    """Middleware que se ejecuta antes de cada solicitud."""
    # Verificar que la aplicación está inicializada
    if mtr_runner is None or storage is None:
        return jsonify({
            'status': 'error',
            'message': 'La aplicación no está inicializada correctamente'
        }), 500

@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint para verificar el estado del servicio."""
    return jsonify({
        'status': 'ok',
        'version': '1.0.0',
        'scan_running': mtr_runner.running,
        'scan_jobs_pending': mtr_runner.scan_jobs.qsize(),
        'scan_threads': len(mtr_runner.scan_threads),
        'config': {k: v for k, v in config.items() if k not in ['storage']}  # Omitir credenciales
    })

@app.route('/api/topology', methods=['GET'])
def get_topology():
    """Endpoint para obtener datos de topología."""
    # Obtener parámetros
    time_range = request.args.get('time_range', '1h')
    group = request.args.get('group')
    agent = request.args.get('agent')
    
    # Consultar topología
    topology = storage.query_topology(time_range, group, agent)
    
    return jsonify({
        'status': 'ok',
        'data': topology
    })

@app.route('/api/agents', methods=['GET'])
def get_agents():
    """Endpoint para obtener la lista de agentes."""
    agents = storage.query_agents()
    
    return jsonify({
        'status': 'ok',
        'data': agents
    })

@app.route('/api/agent', methods=['POST'])
def create_agent():
    """Endpoint para crear un nuevo agente."""
    data = request.json
    
    if not data:
        return jsonify({
            'status': 'error',
            'message': 'No se proporcionaron datos'
        }), 400
    
    ip = data.get('ip')
    if not ip:
        return jsonify({
            'status': 'error',
            'message': 'No se proporcionó dirección IP'
        }), 400
    
    # Crear agente (programar un escaneo)
    enabled = data.get('enabled', True)
    
    if enabled:
        options = data.get('options', {})
        mtr_runner.schedule_scan(ip, options)
    
    return jsonify({
        'status': 'ok',
        'message': f'Agente {ip} creado y {"habilitado" if enabled else "deshabilitado"}'
    }), 201

@app.route('/api/agent/<address>', methods=['POST'])
def update_agent(address):
    """Endpoint para actualizar un agente."""
    data = request.json
    
    if not data:
        return jsonify({
            'status': 'error',
            'message': 'No se proporcionaron datos'
        }), 400
    
    action = data.get('action')
    
    if action == 'enable':
        # Habilitar agente (programar un escaneo)
        options = data.get('options', {})
        mtr_runner.schedule_scan(address, options)
        
        return jsonify({
            'status': 'ok',
            'message': f'Agente {address} habilitado'
        })
    
    elif action == 'disable':
        # No hay acción directa para deshabilitar, simplemente no se programan más escaneos
        return jsonify({
            'status': 'ok',
            'message': f'Agente {address} deshabilitado'
        })
    
    elif action == 'delete':
        # No implementado en InfluxDB (requeriría eliminar datos)
        return jsonify({
            'status': 'error',
            'message': 'La eliminación de agentes no está implementada'
        }), 501
    
    else:
        return jsonify({
            'status': 'error',
            'message': f'Acción desconocida: {action}'
        }), 400

@app.route('/api/scan/<address>', methods=['GET'])
def scan_agent(address):
    """Endpoint para escanear un agente bajo demanda."""
    # Obtener opciones
    options = {}
    
    # Programar escaneo
    mtr_runner.schedule_scan(address, options)
    
    return jsonify({
        'status': 'ok',
        'message': f'Escaneo programado para {address}'
    })

@app.route('/api/discover-telegraf', methods=['GET'])
def discover_telegraf():
    """Endpoint para descubrir agentes de Telegraf."""
    config_dir = request.args.get('config_dir', '/etc/telegraf/telegraf.d')
    
    # Descubrir agentes
    agents = storage.parse_telegraf_configs(config_dir)
    
    # Programar escaneos para agentes descubiertos
    if agents:
        mtr_runner.scan_all_agents(agents)
    
    return jsonify({
        'status': 'ok',
        'message': f'Descubiertos {len(agents)} agentes de Telegraf',
        'data': agents
    })

@app.route('/api/hop/<source>/<destination>/<hop_ip>', methods=['GET'])
def get_hop_stats(source, destination, hop_ip):
    """Endpoint para obtener estadísticas detalladas de un hop."""
    # Obtener parámetros
    time_range = request.args.get('time_range', '24h')
    
    # Consultar estadísticas
    stats = storage.query_hop_stats(source, destination, hop_ip, time_range)
    
    return jsonify({
        'status': 'ok',
        'data': stats
    })

@app.route('/api/config', methods=['GET'])
def get_config():
    """Endpoint para obtener la configuración actual."""
    # Filtrar información sensible
    safe_config = {k: v for k, v in config.items() if k not in ['storage']}
    
    return jsonify({
        'status': 'ok',
        'data': safe_config
    })

@app.route('/api/config', methods=['POST'])
def update_config():
    """Endpoint para actualizar la configuración."""
    data = request.json
    
    if not data:
        return jsonify({
            'status': 'error',
            'message': 'No se proporcionaron datos'
        }), 400
    
    # Actualizar configuración
    for key, value in data.items():
        if key == 'storage':
            # No permitir actualizar configuración de almacenamiento
            continue
        elif key == 'mtr':
            # Actualizar opciones de MTR
            mtr_runner.set_options(value)
        
        # Actualizar configuración global
        config[key] = value
    
    return jsonify({
        'status': 'ok',
        'message': 'Configuración actualizada'
    })

def shutdown_app():
    """Función para detener la aplicación correctamente."""
    if mtr_runner and mtr_runner.running:
        logger.info("Deteniendo bucle de escaneo...")
        mtr_runner.stop_scan_loop(wait=True)
    
    logger.info("Aplicación detenida")

if __name__ == '__main__':
    # Configuración básica de logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Configuración de ejemplo
    app_config = {
        'storage': {
            'host': 'localhost',
            'port': 8086,
            'database': 'mtr_topology'
        },
        'mtr': {
            'count': 3,
            'timeout': 1.0,
            'interval': 0.1,
            'max_hops': 30
        },
        'auto_start_scan': True,
        'scan_on_start': True,
        'discover_telegraf': True,
        'parallel_jobs': 5
    }
    
    # Inicializar aplicación
    init_app(app_config)
    
    try:
        # Iniciar servidor
        app.run(host='0.0.0.0', port=5000, debug=True)
    finally:
        # Detener aplicación al salir
        shutdown_app()

@app.route('/api/path/changes/<source>/<destination>', methods=['GET'])
def get_path_changes(source, destination):
    """Endpoint para obtener cambios en las rutas entre origen y destino."""
    # Obtener parámetros
    time_range = request.args.get('time_range', '7d')
    
    # Consultar cambios
    changes = storage.query_path_changes(source, destination, time_range)
    
    return jsonify({
        'status': 'ok',
        'data': changes
    })

# 6. Añadir a web/app.py - Endpoint para consultar circuitos actuales

@app.route('/api/path/current', methods=['GET'])
def get_current_paths():
    """Endpoint para obtener todas las rutas actuales."""
    # Obtener parámetros
    time_range = request.args.get('time_range', '1h')
    
    # Consulta a InfluxDB
    query = f"""
    SELECT last("path_json") as "path"
    FROM "mtr_path"
    WHERE time > now() - {time_range}
    GROUP BY "source", "destination"
    """
    
    try:
        result = storage.client.query(query)
        
        paths = []
        for (tags, series) in result.items():
            source = tags[1][1]
            destination = tags[2][1]
            
            for point in series:
                path_data = {
                    'source': source,
                    'destination': destination,
                    'time': point['time'],
                    'path': json.loads(point['path'])
                }
                paths.append(path_data)
        
        return jsonify({
            'status': 'ok',
            'data': paths
        })
    
    except Exception as e:
        logger.error(f"Error al consultar rutas actuales: {str(e)}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500
