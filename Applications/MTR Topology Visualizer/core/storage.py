#!/usr/bin/env python3
import json
import sqlite3
import threading
import time
import os
import logging
from datetime import datetime

# Configurar logging
logger = logging.getLogger(__name__)

class MTRStorage:
    """Almacenamiento persistente para datos MTR."""
    
    def __init__(self, db_path="mtr_data.db", retention_days=7, max_records=1000):
        """
        Inicializa el almacenamiento.
        
        Args:
            db_path: Ruta al archivo de base de datos SQLite
            retention_days: Días de retención para datos históricos
            max_records: Número máximo de registros a mantener
        """
        self.db_path = db_path
        self.retention_days = retention_days
        self.max_records = max_records
        self.mutex = threading.RLock()
        self._init_db()
        
        # Programar limpieza periódica
        self.cleanup_thread = threading.Thread(target=self._periodic_cleanup, daemon=True)
        self.stop_event = threading.Event()
        self.cleanup_thread.start()
    
    def _init_db(self):
        """Inicializa la base de datos."""
        try:
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
                    added_timestamp TEXT NOT NULL,
                    last_scan_timestamp TEXT,
                    last_scan_success INTEGER DEFAULT 0
                )
                ''')
                
                # Índice para búsqueda rápida por dirección
                cursor.execute('CREATE INDEX IF NOT EXISTS idx_agent_address ON agents(address)')
                
                # Índice para búsqueda por timestamp
                cursor.execute('CREATE INDEX IF NOT EXISTS idx_topology_timestamp ON topology_data(timestamp)')
                
                conn.commit()
                conn.close()
                logger.info("Base de datos inicializada correctamente")
        except Exception as e:
            logger.error(f"Error al inicializar la base de datos: {e}")
            raise
    
    def _get_connection(self):
        """Obtiene una conexión a la base de datos con timeout y retry."""
        max_retries = 3
        retry_delay = 1
        
        for attempt in range(max_retries):
            try:
                conn = sqlite3.connect(self.db_path, timeout=10)
                conn.row_factory = sqlite3.Row  # Para acceder a columnas por nombre
                return conn
            except sqlite3.OperationalError as e:
                if "database is locked" in str(e) and attempt < max_retries - 1:
                    logger.warning(f"Base de datos bloqueada, reintentando en {retry_delay}s...")
                    time.sleep(retry_delay)
                    retry_delay *= 2  # Backoff exponencial
                else:
                    logger.error(f"Error de acceso a la base de datos: {e}")
                    raise
    
    def save_topology(self, data):
        """Guarda datos de topología en la base de datos."""
        try:
            conn = self._get_connection()
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
            
            # Limpiar datos antiguos si es necesario
            self._cleanup_old_data()
            logger.debug(f"Datos de topología guardados correctamente ({len(json_data)} bytes)")
            return True
        except Exception as e:
            logger.error(f"Error al guardar datos de topología: {e}")
            return False
    
    def _periodic_cleanup(self):
        """Ejecuta limpieza periódica en un hilo separado."""
        cleanup_interval = 3600  # Una vez por hora
        
        while not self.stop_event.is_set():
            try:
                self._cleanup_old_data()
            except Exception as e:
                logger.error(f"Error en limpieza periódica: {e}")
            
            # Esperar hasta la próxima limpieza, comprobando periódicamente si debemos detenernos
            for _ in range(cleanup_interval):
                if self.stop_event.is_set():
                    break
                time.sleep(1)
    
    def _cleanup_old_data(self):
        """Elimina datos antiguos para conservar espacio."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            # 1. Eliminar registros antiguos basados en retention_days
            cutoff_date = (datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - 
                          datetime.timedelta(days=self.retention_days)).isoformat()
            
            cursor.execute(
                "DELETE FROM topology_data WHERE timestamp < ?", 
                (cutoff_date,)
            )
            
            # 2. Si hay más del máximo de registros, eliminar los más antiguos
            cursor.execute("SELECT COUNT(*) FROM topology_data")
            count = cursor.fetchone()[0]
            
            if count > self.max_records:
                cursor.execute("""
                DELETE FROM topology_data 
                WHERE id IN (
                    SELECT id FROM topology_data 
                    ORDER BY timestamp ASC 
                    LIMIT ?
                )
                """, (count - self.max_records,))
            
            conn.commit()
            conn.close()
            
            if count > self.max_records:
                logger.info(f"Limpieza completada: eliminados {count - self.max_records} registros antiguos")
        except Exception as e:
            logger.error(f"Error en limpieza de datos antiguos: {e}")
    
    def get_latest_topology(self):
        """Obtiene los datos de topología más recientes."""
        try:
            conn = self._get_connection()
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
        except Exception as e:
            logger.error(f"Error al obtener topología más reciente: {e}")
            return None
    
    def get_topology_history(self, limit=24):
        """Obtiene el historial de datos de topología."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
            SELECT timestamp, data FROM topology_data 
            ORDER BY timestamp DESC 
            LIMIT ?
            """, (limit,))
            
            history = [
                {
                    'timestamp': row[0],
                    'data': json.loads(row[1])
                }
                for row in cursor.fetchall()
            ]
            
            conn.close()
            return history
        except Exception as e:
            logger.error(f"Error al obtener historial de topología: {e}")
            return []
    
    def add_agent(self, address, name=None, group_name=None):
        """Añade un nuevo agente para monitoreo."""
        if not name:
            name = address
        
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            timestamp = datetime.now().isoformat()
            cursor.execute(
                "INSERT INTO agents (address, name, group_name, added_timestamp) VALUES (?, ?, ?, ?)",
                (address, name, group_name, timestamp)
            )
            
            conn.commit()
            conn.close()
            logger.info(f"Agente añadido: {address} (grupo: {group_name})")
            return True
        except sqlite3.IntegrityError:
            # Ya existe, actualizar información
            try:
                conn = self._get_connection()
                cursor = conn.cursor()
                
                cursor.execute(
                    "UPDATE agents SET name = ?, group_name = ? WHERE address = ?",
                    (name, group_name, address)
                )
                
                conn.commit()
                conn.close()
                logger.info(f"Agente actualizado: {address} (grupo: {group_name})")
                return True
            except Exception as e:
                logger.error(f"Error al actualizar agente existente {address}: {e}")
                return False
        except Exception as e:
            logger.error(f"Error al añadir agente {address}: {e}")
            return False
    
    def remove_agent(self, address):
        """Elimina un agente del monitoreo."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM agents WHERE address = ?", (address,))
            
            affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            if affected > 0:
                logger.info(f"Agente eliminado: {address}")
                return True
            else:
                logger.warning(f"Intento de eliminar un agente inexistente: {address}")
                return False
        except Exception as e:
            logger.error(f"Error al eliminar agente {address}: {e}")
            return False
    
    def get_all_agents(self, enabled_only=True, group=None):
        """
        Obtiene todos los agentes.
        
        Args:
            enabled_only: Si solo se deben devolver agentes habilitados
            group: Filtrar por grupo específico
        """
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            query = "SELECT address, name, group_name, enabled, last_scan_timestamp, last_scan_success FROM agents"
            params = []
            
            where_clauses = []
            if enabled_only:
                where_clauses.append("enabled = 1")
            
            if group:
                where_clauses.append("group_name = ?")
                params.append(group)
            
            if where_clauses:
                query += " WHERE " + " AND ".join(where_clauses)
            
            cursor.execute(query, params)
            
            agents = [
                {
                    'address': row[0],
                    'name': row[1],
                    'group': row[2],
                    'enabled': bool(row[3]),
                    'last_scan': row[4],
                    'last_scan_success': bool(row[5])
                }
                for row in cursor.fetchall()
            ]
            
            conn.close()
            return agents
        except Exception as e:
            logger.error(f"Error al obtener agentes: {e}")
            return []
    
    def get_groups(self):
        """Obtiene todos los grupos de agentes disponibles."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute("SELECT DISTINCT group_name FROM agents WHERE group_name IS NOT NULL")
            
            groups = [row[0] for row in cursor.fetchall()]
            conn.close()
            return groups
        except Exception as e:
            logger.error(f"Error al obtener grupos: {e}")
            return []
    
    def enable_agent(self, address, enabled=True):
        """Habilita o deshabilita un agente."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            cursor.execute(
                "UPDATE agents SET enabled = ? WHERE address = ?",
                (1 if enabled else 0, address)
            )
            
            affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            if affected > 0:
                logger.info(f"Agente {'habilitado' if enabled else 'deshabilitado'}: {address}")
                return True
            else:
                logger.warning(f"Intento de modificar un agente inexistente: {address}")
                return False
        except Exception as e:
            logger.error(f"Error al actualizar estado del agente {address}: {e}")
            return False
    
    def update_agent_scan_status(self, address, success):
        """Actualiza el estado del último escaneo de un agente."""
        try:
            conn = self._get_connection()
            cursor = conn.cursor()
            
            timestamp = datetime.now().isoformat()
            cursor.execute(
                "UPDATE agents SET last_scan_timestamp = ?, last_scan_success = ? WHERE address = ?",
                (timestamp, 1 if success else 0, address)
            )
            
            affected = cursor.rowcount
            conn.commit()
            conn.close()
            
            return affected > 0
        except Exception as e:
            logger.error(f"Error al actualizar estado de escaneo para {address}: {e}")
            return False
    
    def discover_from_telegraf(self, telegraf_path="/etc/telegraf/telegraf.d/"):
        """
        Descubre agentes a partir de archivos de configuración de Telegraf.
        Busca archivos que contienen 'icmp' y extrae URLs para monitorear.
        """
        try:
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
                    logger.error(f"Error al analizar {conf_file}: {e}")
            
            # Añadir agentes descubiertos a la base de datos
            added_count = 0
            for agent in agents:
                if self.add_agent(agent['address'], agent['name'], agent['group']):
                    added_count += 1
            
            logger.info(f"Agentes descubiertos en Telegraf: {len(agents)}, añadidos/actualizados: {added_count}")
            return agents
        except Exception as e:
            logger.error(f"Error al descubrir agentes desde Telegraf: {e}")
            return []
    
    def shutdown(self):
        """Cierra los recursos del almacenamiento."""
        logger.info("Cerrando almacenamiento...")
        self.stop_event.set()
        if self.cleanup_thread.is_alive():
            self.cleanup_thread.join(timeout=5)
        logger.info("Almacenamiento cerrado correctamente")
