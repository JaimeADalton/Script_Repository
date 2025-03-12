#!/usr/bin/env python3
from flask import Flask, render_template, jsonify, request, redirect, url_for, abort
import threading
import time
import socket
import os
import sys
import logging
from datetime import datetime
import json
from functools import wraps

# Añadir directorio padre al path para importar módulos
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from core.mtr import MTRManager
from core.storage import MTRStorage

# Configuración de logging
logger = logging.getLogger(__name__)

# Inicializar aplicación Flask
app = Flask(__name__)

# Variables globales
mtr_manager = None
storage = None
scan_thread = None
stop_event = None
config = {}

def rate_limit(max_calls=10, period=60):
    """
    Decorador para limitar la tasa de llamadas a endpoints.
    
    Args:
        max_calls: Número máximo de llamadas permitidas en el período
        period: Período en segundos
    """
    calls = {}
    lock = threading.RLock()
    
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            client_ip = request.remote_addr
            
            with lock:
                current_time = time.time()
                
                # Limpiar registros antiguos
                for ip in list(calls.keys()):
                    calls_list = calls[ip]
                    while calls_list and calls_list[0] < current_time - period:
                        calls_list.pop(0)
                    
                    if not calls_list:
                        del calls[ip]
                
                # Verificar límite
                if client_ip not in calls:
                    calls[client_ip] = []
                
                if len(calls[client_ip]) >= max_calls:
                    logger.warning(f"Rate limit excedido para {client_ip}")
                    return jsonify({
                        'success': False, 
                        'error': 'Demasiadas solicitudes. Por favor, espere antes de intentarlo nuevamente.'
                    }), 429
                
                # Registrar llamada
                calls[client_ip].append(current_time)
            
            return f(*args, **kwargs)
        return wrapper
    return decorator

def api_error_handler(f):
    """Decorador para manejar excepciones en endpoints de API."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except Exception as e:
            logger.error(f"Error en endpoint {request.path}: {e}", exc_info=True)
            return jsonify({
                'success': False,
                'error': str(e)
            }), 500
    return wrapper

def init_app(app_config):
    """Inicializa la aplicación y sus componentes."""
    global mtr_manager, storage, scan_thread, stop_event, config
    
    # Guardar configuración
    config = app_config
    stop_event = config.get('stop_event', threading.Event())
    
    # Usar almacenamiento proporcionado o crear uno nuevo
    storage = config.get('storage')
    if not storage:
        storage = MTRStorage()
    
    # Inicializar gestor MTR
    mtr_options = {
        'timeout': 1.0,
        'interval': 0.1,  # Más rápido para inicialización
        'hop_sleep': 0.05,
        'max_hops': config.get('max_hops', 30),
        'max_unknown_hops': config.get('max_unknown_hops', 3),
        'ring_buffer_size': config.get('buffer_size', 5),
        'ptr_lookup': False
    }
    
    mtr_manager = MTRManager(
        max_concurrent=config.get('max_concurrent', 20), 
        **mtr_options
    )
    
    # Cargar agentes existentes
    agents = storage.get_all_agents()
    logger.info(f"Cargados {len(agents)} agentes desde la base de datos")
    
    # Añadir agentes al gestor MTR
    for agent in agents:
        if agent['enabled']:
            try:
                mtr_manager.add_target(agent['address'])
            except Exception as e:
                logger.error(f"Error al añadir agente {agent['address']}: {e}")
    
    # Iniciar hilo de escaneo
    scan_thread = threading.Thread(target=scan_loop)
    scan_thread.daemon = True
    scan_thread.start()

def scan_loop():
    """Bucle principal para escanear periódicamente todos los agentes."""
    logger.info("Iniciado hilo de escaneo")
    
    scan_interval = config.get('scan_interval', 300)  # 5 minutos entre escaneos completos
    chunk_size = 5  # Procesar agentes en grupos para evitar sobrecarga
    
    while not stop_event.is_set():
        try:
            # Generar y guardar datos de topología 
            topology_data = mtr_manager.get_topology_data()
            if topology_data and topology_data['nodes']:
                storage.save_topology(topology_data)
                logger.info(f"Topología actualizada: {len(topology_data['nodes'])} nodos, {len(topology_data['links'])} enlaces")
            
            # Escanear todos los agentes en chunks
            agents = storage.get_all_agents()
            agent_chunks = [agents[i:i+chunk_size] for i in range(0, len(agents), chunk_size)]
            
            for chunk in agent_chunks:
                if stop_event.is_set():
                    break
                
                scan_chunk(chunk)
                # Pequeña pausa entre chunks
                time.sleep(2)
            
            # Esperar hasta el siguiente escaneo
            wait_with_timeout(scan_interval)
                
        except Exception as e:
            logger.error(f"Error en bucle de escaneo: {e}", exc_info=True)
            wait_with_timeout(60)  # Esperar un minuto antes de reintentar

def scan_chunk(agents):
    """Escanea un grupo de agentes."""
    for agent in agents:
        if stop_event.is_set():
            break
            
        try:
            address = agent['address']
            
            # Verificar si el agente está habilitado
            if not agent['enabled']:
                if address in mtr_manager.mtrs:
                    mtr_manager.remove_target(address)
                continue
            
            # Añadir si no existe, escanear si ya existe
            if address in mtr_manager.mtrs:
                mtr = mtr_manager.mtrs[address]
                future = mtr.discover(count=1)
                success = True
            else:
                success = mtr_manager.add_target(address)
            
            # Actualizar estado en la base de datos
            storage.update_agent_scan_status(address, success)
            
        except Exception as e:
            logger.error(f"Error al escanear {agent['address']}: {e}")
            try:
                storage.update_agent_scan_status(agent['address'], False)
            except:
                pass

def wait_with_timeout(seconds):
    """Espera un número de segundos, comprobando periódicamente si debe detenerse."""
    for _ in range(seconds):
        if stop_event.is_set():
            break
        time.sleep(1)

# Rutas web

@app.route('/')
def index():
    """Página principal."""
    return render_template('index.html')

@app.route('/dashboard')
def dashboard():
    """Dashboard principal."""
    return render_template('dashboard.html')

@app.route('/about')
def about():
    """Página de información."""
    return render_template('about.html')

# Rutas de API

@app.route('/api/topology')
@api_error_handler
def get_topology():
    """API para obtener datos de topología."""
    # Filtros opcionales
    group = request.args.get('group', None)
    agent = request.args.get('agent', None)
    
    # Obtener topología más reciente
    topology = storage.get_latest_topology()
    
    if not topology:
        # Si no hay datos almacenados, obtener datos en tiempo real
        topology = mtr_manager.get_topology_data()
        if topology and topology['nodes']:
            storage.save_topology(topology)
    
    # Aplicar filtros si es necesario
    if topology:
        # Filtrar por agente específico
        if agent and agent != 'all':
            topology = filter_topology_by_agent(topology, agent)
        
        # Filtrar por grupo
        elif group and group != 'all':
            topology = filter_topology_by_group(topology, group)
    
    return jsonify(topology or {'nodes': [], 'links': []})

def filter_topology_by_agent(topology, agent_address):
    """Filtra la topología para mostrar solo la ruta a un agente específico."""
    # Encontrar todos los enlaces que tienen este agente como destino
    links_to_keep = [link for link in topology['links'] 
                   if agent_address in link['destinations']]
    
    # Recolectar todos los nodos utilizados en estos enlaces
    nodes_to_keep = set()
    for link in links_to_keep:
        nodes_to_keep.add(link['source'])
        nodes_to_keep.add(link['target'])
    
    # Añadir el nodo de origen (local) y el agente
    nodes_to_keep.add('local')
    nodes_to_keep.add(agent_address)
    
    # Filtrar nodos y enlaces
    filtered_nodes = [node for node in topology['nodes'] 
                    if node['id'] in nodes_to_keep]
    
    return {
        'nodes': filtered_nodes,
        'links': links_to_keep
    }

def filter_topology_by_group(topology, group):
    """Filtra la topología para mostrar solo las rutas a un grupo de agentes."""
    # Obtener agentes de este grupo
    agents = [a['address'] for a in storage.get_all_agents() if a['group'] == group]
    
    if not agents:
        return topology
    
    # Filtrar enlaces que tienen al menos un agente del grupo como destino
    links_to_keep = []
    for link in topology['links']:
        if any(dest in agents for dest in link['destinations']):
            links_to_keep.append(link)
    
    # Recolectar nodos utilizados en estos enlaces
    nodes_to_keep = set()
    for link in links_to_keep:
        nodes_to_keep.add(link['source'])
        nodes_to_keep.add(link['target'])
    
    # Añadir los nodos de agentes
    for agent in agents:
        nodes_to_keep.add(agent)
    
    # Añadir nodo de origen
    nodes_to_keep.add('local')
    
    # Filtrar nodos
    filtered_nodes = [node for node in topology['nodes'] 
                    if node['id'] in nodes_to_keep]
    
    return {
        'nodes': filtered_nodes,
        'links': links_to_keep
    }

@app.route('/api/topology/history')
@api_error_handler
def get_topology_history():
    """API para obtener historial de datos de topología."""
    limit = request.args.get('limit', 24, type=int)
    history = storage.get_topology_history(limit)
    return jsonify(history)

@app.route('/api/agents')
@api_error_handler
def get_agents():
    """API para obtener lista de agentes."""
    enabled_only = request.args.get('enabled_only', 'true').lower() == 'true'
    group = request.args.get('group', None)
    
    agents = storage.get_all_agents(enabled_only, group)
    return jsonify(agents)

@app.route('/api/groups')
@api_error_handler
def get_groups():
    """API para obtener lista de grupos."""
    groups = storage.get_groups()
    return jsonify(groups)

@app.route('/api/agent/<address>', methods=['POST'])
@api_error_handler
@rate_limit(max_calls=20, period=60)
def update_agent(address):
    """API para actualizar un agente."""
    data = request.json
    action = data.get('action')
    
    if action == 'enable':
        success = storage.enable_agent(address, True)
        # Añadir al MTR si no existe
        if success and address not in mtr_manager.mtrs:
            mtr_manager.add_target(address)
        return jsonify({'success': success})
    
    elif action == 'disable':
        success = storage.enable_agent(address, False)
        # Remover del MTR
        if success and address in mtr_manager.mtrs:
            mtr_manager.remove_target(address)
        return jsonify({'success': success})
    
    elif action == 'remove':
        # Remover del MTR y de la base de datos
        if address in mtr_manager.mtrs:
            mtr_manager.remove_target(address)
        success = storage.remove_agent(address)
        return jsonify({'success': success})
    
    else:
        return jsonify({
            'success': False, 
            'error': 'Acción no válida. Use "enable", "disable" o "remove".'
        }), 400

@app.route('/api/agent', methods=['POST'])
@api_error_handler
@rate_limit(max_calls=10, period=60)
def add_agent():
    """API para añadir un nuevo agente."""
    data = request.json
    
    # Validar datos
    if not data or 'address' not in data:
        return jsonify({
            'success': False, 
            'error': 'Datos incompletos. Se requiere al menos una dirección.'
        }), 400
    
    address = data.get('address').strip()
    name = data.get('name', address).strip()
    group = data.get('group', 'default').strip()
    
    # Validar dirección
    try:
        version = get_ip_version(address)
        if not version:
            # Intentar resolución DNS
            try:
                address = socket.gethostbyname(address)
            except socket.gaierror:
                return jsonify({
                    'success': False, 
                    'error': 'No se puede resolver la dirección. Proporcione una IP válida o un hostname resoluble.'
                }), 400
    except Exception as e:
        return jsonify({
            'success': False, 
            'error': f'Error validando dirección: {str(e)}'
        }), 400
    
    # Añadir a la base de datos
    result = storage.add_agent(address, name, group)
    
    # Añadir al MTR
    if result:
        try:
            mtr_manager.add_target(address)
        except Exception as e:
            logger.error(f"Error al añadir agente {address} al MTR: {e}")
            return jsonify({
                'success': False, 
                'error': f'Agente añadido a la base de datos pero error al iniciar monitoreo: {str(e)}'
            }), 500
    
    return jsonify({'success': result})

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

@app.route('/api/scan/<address>')
@api_error_handler
@rate_limit(max_calls=5, period=60)
def scan_agent(address):
    """API para escanear un agente específico."""
    if address not in mtr_manager.mtrs:
        return jsonify({
            'success': False, 
            'error': 'Agente no encontrado o no activo'
        }), 404
    
    try:
        mtr = mtr_manager.mtrs[address]
        mtr.discover(count=1)
        
        # Actualizar estado en la base de datos
        storage.update_agent_scan_status(address, True)
        
        return jsonify({'success': True})
    except Exception as e:
        # Registrar fallo
        storage.update_agent_scan_status(address, False)
        
        return jsonify({
            'success': False, 
            'error': f'Error al escanear: {str(e)}'
        }), 500

@app.route('/api/discover-telegraf')
@api_error_handler
@rate_limit(max_calls=2, period=300)  # Limitar a 2 llamadas cada 5 minutos
def discover_telegraf():
    """API para descubrir agentes desde la configuración de Telegraf."""
    try:
        telegraf_path = request.args.get('path', '/etc/telegraf/telegraf.d/')
        agents = storage.discover_from_telegraf(telegraf_path)
        
        # Añadir nuevos agentes al MTR
        added_count = 0
        for agent in agents:
            if agent['address'] not in mtr_manager.mtrs:
                try:
                    if mtr_manager.add_target(agent['address']):
                        added_count += 1
                except Exception as e:
                    logger.error(f"Error al añadir agente descubierto {agent['address']}: {e}")
        
        return jsonify({
            'success': True, 
            'agents': agents,
            'added_to_monitoring': added_count
        })
    except Exception as e:
        logger.error(f"Error al descubrir agentes: {e}", exc_info=True)
        return jsonify({
            'success': False, 
            'error': str(e)
        }), 500

@app.route('/api/stats')
@api_error_handler
def get_stats():
    """API para obtener estadísticas del sistema."""
    try:
        with mtr_manager.mutex:
            active_mtrs = len(mtr_manager.mtrs)
            active_futures = len(mtr_manager.futures)
        
        agents = storage.get_all_agents(enabled_only=False)
        enabled_agents = sum(1 for a in agents if a['enabled'])
        disabled_agents = len(agents) - enabled_agents
        
        groups = storage.get_groups()
        
        return jsonify({
            'success': True,
            'stats': {
                'active_mtrs': active_mtrs,
                'pending_operations': active_futures,
                'total_agents': len(agents),
                'enabled_agents': enabled_agents,
                'disabled_agents': disabled_agents,
                'groups': len(groups),
                'scan_interval': config.get('scan_interval', 300),
                'running_since': datetime.now().isoformat()  # Esto es aproximado
            }
        })
    except Exception as e:
        logger.error(f"Error al obtener estadísticas: {e}")
        return jsonify({
            'success': False, 
            'error': str(e)
        }), 500

# Función para apagar el servidor
def shutdown_server():
    """Detiene el servidor y los hilos."""
    global stop_event, mtr_manager
    
    logger.info("Deteniendo servidor web...")
    
    # Señalizar terminación
    if stop_event:
        stop_event.set()
    
    # Detener MTR Manager
    if mtr_manager:
        try:
            mtr_manager.shutdown()
        except Exception as e:
            logger.error(f"Error al detener MTR Manager: {e}")
    
    logger.info("Servidor web detenido")

# Inicialización para uso con uWSGI
if __name__ != '__main__':
    # Configurar logging básico para capturar errores tempranos
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    logger.info("Inicializando aplicación web en modo WSGI")

# Para pruebas directas
if __name__ == '__main__':
    # Configurar logging
    logging.basicConfig(level=logging.DEBUG)
    logger = logging.getLogger(__name__)
    
    # Inicializar con configuración de prueba
    stop_event = threading.Event()
    
    init_app({
        'scan_interval': a10,
        'debug': True,
        'stop_event': stop_event
    })
    
    # Ejecutar en modo desarrollo
    try:
        app.run(host='0.0.0.0', port=8088, debug=True, use_reloader=False)
    except KeyboardInterrupt:
        logger.info("Cerrando aplicación...")
        shutdown_server()
