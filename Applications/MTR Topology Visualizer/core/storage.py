#!/usr/bin/env python3
import json
import sqlite3
import threading
import time
import os
from datetime import datetime

class MTRStorage:
    """Almacenamiento persistente para datos MTR."""
    
    def __init__(self, db_path="mtr_data.db"):
        """
        Inicializa el almacenamiento.
        
        Args:
            db_path: Ruta al archivo de base de datos SQLite
        """
        self.db_path = db_path
        self.mutex = threading.RLock()
        self._init_db()
    
    def _init_db(self):
        """Inicializa la base de datos."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Tabla para datos de topología
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS topology_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                data TEXT NOT NULL
            )
            ''')
            
            # Tabla para configuración de agentes
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS agents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                address TEXT UNIQUE NOT NULL,
                name TEXT,
                group_name TEXT,
                enabled INTEGER DEFAULT 1,
                added_timestamp TEXT NOT NULL
            )
            ''')
            
            conn.commit()
            conn.close()
    
    def save_topology(self, data):
        """Guarda datos de topología en la base de datos."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Convertir datos a JSON
            json_data = json.dumps(data)
            timestamp = datetime.now().isoformat()
            
            cursor.execute(
                "INSERT INTO topology_data (timestamp, data) VALUES (?, ?)",
                (timestamp, json_data)
            )
            
            conn.commit()
            conn.close()
            
            # Limpiar datos antiguos (mantener solo los últimos 100)
            self._cleanup_old_data()
    
    def _cleanup_old_data(self):
        """Elimina datos antiguos para conservar espacio."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Obtener recuento total
            cursor.execute("SELECT COUNT(*) FROM topology_data")
            count = cursor.fetchone()[0]
            
            # Si hay más de 100 registros, eliminar los más antiguos
            if count > 100:
                cursor.execute("""
                DELETE FROM topology_data 
                WHERE id IN (
                    SELECT id FROM topology_data 
                    ORDER BY timestamp ASC 
                    LIMIT ?
                )
                """, (count - 100,))
            
            conn.commit()
            conn.close()
    
    def get_latest_topology(self):
        """Obtiene los datos de topología más recientes."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("""
            SELECT data FROM topology_data 
            ORDER BY timestamp DESC 
            LIMIT 1
            """)
            
            row = cursor.fetchone()
            conn.close()
            
            if row:
                return json.loads(row[0])
            return None
    
    def add_agent(self, address, name=None, group_name=None):
        """Añade un nuevo agente para monitoreo."""
        if not name:
            name = address
            
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            try:
                timestamp = datetime.now().isoformat()
                cursor.execute(
                    "INSERT INTO agents (address, name, group_name, added_timestamp) VALUES (?, ?, ?, ?)",
                    (address, name, group_name, timestamp)
                )
                conn.commit()
                result = True
            except sqlite3.IntegrityError:
                # Ya existe
                result = False
            finally:
                conn.close()
            
            return result
    
    def remove_agent(self, address):
        """Elimina un agente del monitoreo."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM agents WHERE address = ?", (address,))
            
            affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            return affected > 0
    
    def get_all_agents(self, enabled_only=True):
        """Obtiene todos los agentes."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            if enabled_only:
                cursor.execute("SELECT address, name, group_name FROM agents WHERE enabled = 1")
            else:
                cursor.execute("SELECT address, name, group_name FROM agents")
            
            agents = [
                {
                    'address': row[0],
                    'name': row[1],
                    'group': row[2]
                }
                for row in cursor.fetchall()
            ]
            
            conn.close()
            return agents
    
    def enable_agent(self, address, enabled=True):
        """Habilita o deshabilita un agente."""
        with self.mutex:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute(
                "UPDATE agents SET enabled = ? WHERE address = ?",
                (1 if enabled else 0, address)
            )
            
            affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            return affected > 0

    def discover_from_telegraf(self, telegraf_path="/etc/telegraf/telegraf.d/"):
        """
        Descubre agentes a partir de archivos de configuración de Telegraf.
        Busca archivos que contienen 'icmp' y extrae URLs para monitorear.
        """
        import glob
        import re
        import configparser
        
        agents = []
        pattern = os.path.join(telegraf_path, "**", "*icmp*.conf")
        
        for conf_file in glob.glob(pattern, recursive=True):
            group_name = os.path.basename(conf_file).replace('.conf', '')
            
            try:
                # Leer archivo de configuración
                config = configparser.ConfigParser(strict=False)
                config.read(conf_file)
                
                # Buscar secciones inputs.ping
                for section in config.sections():
                    if "inputs.ping" in section and "urls" in config[section]:
                        # Extraer URLs
                        urls_text = config[section]["urls"]
                        # Limpiar formato
                        urls_text = urls_text.replace('[', '').replace(']', '').replace('"', '')
                        urls = [u.strip() for u in urls_text.split(',') if u.strip()]
                        
                        for url in urls:
                            if url and not url.startswith('#'):
                                agents.append({
                                    'address': url,
                                    'name': url,
                                    'group': group_name
                                })
            except Exception as e:
                print(f"Error al analizar {conf_file}: {e}")
        
        # Añadir agentes descubiertos a la base de datos
        for agent in agents:
            self.add_agent(agent['address'], agent['name'], agent['group'])
        
        return agents
