#!/usr/bin/env python3
from flask import Flask, render_template, jsonify, request, redirect, url_for
import threading
import time
import socket
import os
import sys
import logging
from datetime import datetime

# Añadir directorio padre al path para importar módulos
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from core.mtr import MTRManager
from core.storage import MTRStorage

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("mtr_app.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Variables globales
mtr_manager = None
storage = None
scan_thread = None
stop_event = threading.Event()

def init_app(config=None):
    """Inicializa la aplicación y sus componentes."""
    global mtr_manager, storage, scan_thread
    
    # Inicializar almacenamiento
    storage = MTRStorage()
    
    # Inicializar gestor MTR
    mtr_options = {
        'timeout': 1.0,
        'interval': 0.1,  # Más rápido para inicialización
        'hop_sleep': 0.05,
        'max_hops': 30,
        'max_unknown_hops': 3,
        'ring_buffer_size': 5,
        'ptr_lookup': False
    }
    mtr_manager = MTRManager(max_concurrent=20, **mtr_options)
    
    # Cargar agentes existentes
    agents = storage.get_all_agents()
    logger.info(f"Cargados {len(agents)} agentes desde la base de datos")
    
    # Añadir agentes al gestor MTR
    for agent in agents:
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
    scan_interval = 300  # 5 minutos entre escaneos completos
    chunk_size = 10  # Procesar agentes en grupos para evitar sobrecarga
    
    while not stop_event.is_set():
        try:
            # Escanear todos los agentes en chunks
            agents = storage.get_all_agents()
            agent_chunks = [agents[i:i+chunk_size] for i in range(0, len(agents), chunk_size)]
            
            for chunk in agent_chunks:
                if stop_event.is_set():
                    break
                    
                for agent in chunk:
                    if stop_event.is_set():
                        break
                        
                    try:
                        # Añadir si no existe, escanear si ya existe
                        if agent['address'] not in mtr_manager.mtrs:
                            mtr_manager.add_target(agent['address'])
                        else:
                            mtr = mtr_manager.mtrs[agent['address']]
                            mtr.discover(count=1)
                    except Exception as e:
                        logger.error(f"Error al escanear {agent['address']}: {e}")
                
                # Pequeña pausa entre chunks
                time.sleep(2)
            
            # Generar y guardar datos de topología
            try:
                topology_data = mtr_manager.get_topology_data()
                storage.save_topology(topology_data)
                logger.info(f"Topología actualizada: {len(topology_data['nodes'])} nodos, {len(topology_data['links'])} enlaces")
            except Exception as e:
                logger.error(f"Error al guardar topología: {e}")
            
            # Esperar hasta el siguiente escaneo
            for _ in range(scan_interval):
                if stop_event.is_set():
                    break
                time.sleep(1)
                
        except Exception as e:
            logger.error(f"Error en bucle de escaneo: {e}")
            time.sleep(60)  # Esperar un minuto antes de reintentar

@app.route('/')
def index():
    """Página principal."""
    return render_template('index.html')

@app.route('/api/topology')
def get_topology():
    """API para obtener datos de topología."""
    # Filtros opcionales
    group = request.args.get('group', None)
    
    # Obtener topología más reciente
    topology = storage.get_latest_topology()
    
    if not topology:
        # Si no hay datos almacenados, obtener datos en tiempo real
        topology = mtr_manager.get_topology_data()
    
    # Aplicar filtros si es necesario
    if group and topology:
        # Obtener agentes de este grupo
        agents = [a['address'] for a in storage.get_all_agents() if a['group'] == group]
        
        # Filtrar nodos y enlaces
        filtered_links = [link for link in topology['links'] 
                        if any(dest in agents for dest in link['destinations'])]
        
        # Recolectar nodos utilizados en estos enlaces
        used_nodes = set()
        for link in filtered_links:
            used_nodes.add(link['source'])
            used_nodes.add(link['target'])
        
        # Filtrar nodos
        filtered_nodes = [node for node in topology['nodes'] 
                        if node['id'] in used_nodes or (node['type'] == 'destination' and node['id'] in agents)]
        
        topology = {
            'nodes': filtered_nodes,
            'links': filtered_links
        }
    
    return jsonify(topology)

@app.route('/api/agents')
def get_agents():
    """API para obtener lista de agentes."""
    agents = storage.get_all_agents(enabled_only=False)
    return jsonify(agents)

@app.route('/api/agent/<address>', methods=['POST'])
def update_agent(address):
    """API para actualizar un agente."""
    data = request.json
    action = data.get('action')
    
    if action == 'enable':
        storage.enable_agent(address, True)
        # Añadir al MTR si no existe
        if address not in mtr_manager.mtrs:
            mtr_manager.add_target(address)
        return jsonify({'success': True})
    elif action == 'disable':
        storage.enable_agent(address, False)
        # Remover del MTR
        if address in mtr_manager.mtrs:
            mtr_manager.remove_target(address)
        return jsonify({'success': True})
    elif action == 'remove':
        # Remover del MTR y de la base de datos
        if address in mtr_manager.mtrs:
            mtr_manager.remove_target(address)
        storage.remove_agent(address)
        return jsonify({'success': True})
    
    return jsonify({'success': False, 'error': 'Acción no válida'})

@app.route('/api/agent', methods=['POST'])
def add_agent():
    """API para añadir un nuevo agente."""
    data = request.json
    address = data.get('address')
    name = data.get('name', address)
    group = data.get('group', 'default')
    
    # Validar dirección
    try:
        socket.inet_aton(address)
    except:
        try:
            address = socket.gethostbyname(address)
        except:
            return jsonify({'success': False, 'error': 'Dirección no válida'})
    
    # Añadir a la base de datos
    result = storage.add_agent(address, name, group)
    
    # Añadir al MTR
    if result:
        try:
            mtr_manager.add_target(address)
        except Exception as e:
            logger.error(f"Error al añadir agente {address}: {e}")
            return jsonify({'success': False, 'error': str(e)})
    
    return jsonify({'success': result})

@app.route('/api/scan/<address>')
def scan_agent(address):
    """API para escanear un agente específico."""
    if address not in mtr_manager.mtrs:
        return jsonify({'success': False, 'error': 'Agente no encontrado'})
    
    try:
        mtr = mtr_manager.mtrs[address]
        mtr.discover(count=1)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/discover-telegraf')
def discover_telegraf():
    """API para descubrir agentes desde la configuración de Telegraf."""
    try:
        telegraf_path = request.args.get('path', '/etc/telegraf/telegraf.d/')
        agents = storage.discover_from_telegraf(telegraf_path)
        
        # Añadir nuevos agentes al MTR
        for agent in agents:
            if agent['address'] not in mtr_manager.mtrs:
                mtr_manager.add_target(agent['address'])
        
        return jsonify({'success': True, 'agents': agents})
    except Exception as e:
        logger.error(f"Error al descubrir agentes: {e}")
        return jsonify({'success': False, 'error': str(e)})

def shutdown_server():
    """Detiene el servidor y los hilos."""
    global stop_event
    stop_event.set()
    logger.info("Deteniendo servidor...")

if __name__ == '__main__':
    init_app()
    app.run(host='0.0.0.0', port=8088, debug=False)
