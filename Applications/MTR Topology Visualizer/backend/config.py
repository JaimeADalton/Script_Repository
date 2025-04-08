#!/usr/bin/env python3
"""
Configuración central para mtr-topology.
Define parámetros globales y configuración para todos los componentes.
"""

import os
import sys
import logging
import json
from typing import Dict, Any, Optional

# Configuración de logging
def setup_logging(
    log_file: str = None,
    log_level: str = "INFO",
    console: bool = True
) -> None:
    """
    Configura el sistema de logging.
    
    Args:
        log_file: Ruta al archivo de log (opcional).
        log_level: Nivel de logging (DEBUG, INFO, WARNING, ERROR, CRITICAL).
        console: Si es True, también se loguea a la consola.
    """
    # Convertir string de nivel a constante de logging
    numeric_level = getattr(logging, log_level.upper(), None)
    if not isinstance(numeric_level, int):
        raise ValueError(f'Nivel de log inválido: {log_level}')
    
    # Configuración básica
    handlers = []
    
    # Handler de consola
    if console:
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        ))
        handlers.append(console_handler)
    
    # Handler de archivo
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        ))
        handlers.append(file_handler)
    
    # Configurar root logger
    logging.basicConfig(
        level=numeric_level,
        handlers=handlers,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

# Clase de configuración
class Config:
    """Clase para manejar la configuración global."""
    
    def __init__(self, config_file: Optional[str] = None):
        """
        Inicializa la configuración.
        
        Args:
            config_file: Ruta al archivo de configuración (opcional).
        """
        # Valores por defecto
        self.config = {
            # Configuración general
            'app_name': 'mtr-topology',
            'debug': False,
            
            # Configuración de logging
            'logging': {
                'log_file': '/opt/mtr-topology/mtr_topology.log',
                'log_level': 'INFO',
                'console': True
            },
            
            # Configuración de MTR
            'mtr': {
                'count': 3,                # Número de pings por hop
                'timeout': 1.0,            # Timeout por ping (segundos)
                'interval': 0.1,           # Intervalo entre pings (segundos)
                'max_hops': 30,            # Número máximo de hops
                'max_unknown_hops': 3,     # Número máximo de hops desconocidos consecutivos
                'hop_sleep': 0.05,         # Tiempo entre hops distintos (segundos)
                'parallel_jobs': 10        # Número máximo de trabajos paralelos
            },
            
            # Configuración de almacenamiento (InfluxDB)
            'storage': {
                'host': 'localhost',
                'port': 8086,
                'username': None,
                'password': None,
                'database': 'mtr_topology',
                'ssl': False,
                'verify_ssl': False,
                'default_tags': {}
            },
            
            # Configuración de la API web
            'web': {
                'host': '0.0.0.0',
                'port': 5000,
                'debug': False
            },
            
            # Configuración de escaneo
            'scan': {
                'auto_start': True,        # Iniciar bucle de escaneo automáticamente
                'scan_on_start': True,     # Escanear agentes al iniciar
                'discover_telegraf': True, # Descubrir agentes de Telegraf al iniciar
                'telegraf_config_dir': '/etc/telegraf/telegraf.d',
                'scan_interval': 300       # Intervalo entre escaneos (segundos)
            }
        }
        
        # Cargar archivo de configuración si se proporciona
        if config_file:
            self.load_from_file(config_file)
    
    def load_from_file(self, config_file: str) -> None:
        """
        Carga la configuración desde un archivo JSON.
        
        Args:
            config_file: Ruta al archivo de configuración.
        """
        try:
            with open(config_file, 'r') as f:
                file_config = json.load(f)
            
            # Actualizar configuración
            self._update_dict(self.config, file_config)
            
            logging.info(f"Configuración cargada desde {config_file}")
        
        except Exception as e:
            logging.error(f"Error al cargar configuración desde {config_file}: {str(e)}")
    
    def _update_dict(self, base_dict: Dict[str, Any], update_dict: Dict[str, Any]) -> None:
        """
        Actualiza un diccionario anidado de forma recursiva.
        
        Args:
            base_dict: Diccionario base a actualizar.
            update_dict: Diccionario con las actualizaciones.
        """
        for key, value in update_dict.items():
            if key in base_dict and isinstance(base_dict[key], dict) and isinstance(value, dict):
                # Actualizar recursivamente para diccionarios anidados
                self._update_dict(base_dict[key], value)
            else:
                # Actualizar valor directamente
                base_dict[key] = value
    
    def get(self, key: str, default: Any = None) -> Any:
        """
        Obtiene un valor de configuración.
        
        Args:
            key: Clave de configuración (puede ser anidada con puntos, por ejemplo 'web.port').
            default: Valor por defecto si la clave no existe.
            
        Returns:
            Valor de configuración.
        """
        # Dividir clave por puntos para acceder a diccionarios anidados
        keys = key.split('.')
        value = self.config
        
        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default
    
    def set(self, key: str, value: Any) -> None:
        """
        Establece un valor de configuración.
        
        Args:
            key: Clave de configuración (puede ser anidada con puntos).
            value: Valor a establecer.
        """
        # Dividir clave por puntos para acceder a diccionarios anidados
        keys = key.split('.')
        
        # Navegar hasta el último nivel
        config = self.config
        for k in keys[:-1]:
            if k not in config or not isinstance(config[k], dict):
                config[k] = {}
            config = config[k]
        
        # Establecer valor
        config[keys[-1]] = value
    
    def to_dict(self) -> Dict[str, Any]:
        """
        Devuelve la configuración completa como un diccionario.
        
        Returns:
            Diccionario con la configuración.
        """
        return self.config.copy()

# Instancia global de configuración
config = Config()

# Función para cargar configuración desde argumentos de línea de comandos
def load_from_args(args=None) -> None:
    """
    Carga configuración desde argumentos de línea de comandos.
    
    Args:
        args: Argumentos de línea de comandos (si no se proporciona, se usa sys.argv).
    """
    import argparse
    
    parser = argparse.ArgumentParser(description='MTR Topology Service')
    
    parser.add_argument('--config', '-c', type=str, help='Ruta al archivo de configuración')
    parser.add_argument('--debug', '-d', action='store_true', help='Modo debug')
    parser.add_argument('--log-file', '-l', type=str, help='Ruta al archivo de log')
    parser.add_argument('--scan-interval', '-i', type=int, help='Intervalo entre escaneos (segundos)')
    parser.add_argument('--max-hops', '-m', type=int, help='Número máximo de hops')
    parser.add_argument('--port', '-p', type=int, help='Puerto para la API web')
    
    parsed_args = parser.parse_args(args)
    
    # Cargar archivo de configuración si se proporciona
    if parsed_args.config:
        config.load_from_file(parsed_args.config)
    
    # Actualizar configuración con argumentos
    if parsed_args.debug:
        config.set('debug', True)
        config.set('logging.log_level', 'DEBUG')
        config.set('web.debug', True)
    
    if parsed_args.log_file:
        config.set('logging.log_file', parsed_args.log_file)
    
    if parsed_args.scan_interval:
        config.set('scan.scan_interval', parsed_args.scan_interval)
    
    if parsed_args.max_hops:
        config.set('mtr.max_hops', parsed_args.max_hops)
    
    if parsed_args.port:
        config.set('web.port', parsed_args.port)
    
    # Configurar logging
    setup_logging(
        log_file=config.get('logging.log_file'),
        log_level=config.get('logging.log_level'),
        console=config.get('logging.console')
    )

if __name__ == "__main__":
    # Ejemplo de uso
    load_from_args()
    
    print("Configuración actual:")
    print(json.dumps(config.to_dict(), indent=2))
