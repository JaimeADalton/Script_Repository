#!/usr/bin/env python3
"""
dns_smart_autotune.py (v4)
Benchmark inteligente de servidores DNS con Machine Learning persistente
Incluye verdadero aprendizaje continuo con datos históricos
Autor: Optimizado con ML Persistente (2025-05-27)

Características:
- Aprendizaje continuo con persistencia de datos
- Base de datos SQLite para históricos
- Modelo ML que mejora con cada ejecución
- Predicción de rendimiento basada en patrones temporales
- Detección inteligente de anomalías
- Análisis de tendencias a largo plazo

Uso:
  sudo python3 dns_smart_autotune.py                    # Análisis normal con aprendizaje
  sudo python3 dns_smart_autotune.py --duration 15      # 15 minutos de pruebas
  sudo python3 dns_smart_autotune.py --quick            # Análisis rápido (2 min)
  sudo python3 dns_smart_autotune.py --learning         # Modo aprendizaje intensivo
  sudo python3 dns_smart_autotune.py --reset-learning   # Reiniciar datos de aprendizaje
"""

import asyncio
import time
import statistics
import ipaddress
import sys
import argparse
import json
import pickle
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, asdict
from collections import defaultdict, deque
import math
import logging

import dns.asyncresolver
import numpy as np
from sklearn.ensemble import RandomForestRegressor, IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import cross_val_score, TimeSeriesSplit
from sklearn.metrics import mean_squared_error, mean_absolute_error
import warnings

# Configurar logging
logging.basicConfig(level=logging.WARNING)
# Suprimir solo advertencias específicas de sklearn
warnings.filterwarnings('ignore', category=UserWarning, module='sklearn')

# ───────────────────────────────── Configuración ──────────────────────────────

DNS_CANDIDATES = [
    # Tier 1 - Principales
    "8.8.8.8", "8.8.4.4",                # Google
    "1.1.1.1", "1.0.0.1",                # Cloudflare
    "9.9.9.9", "149.112.112.112",        # Quad9
    "208.67.222.222", "208.67.220.220",  # OpenDNS
    
    # Tier 2 - Alternativos
    "84.200.69.80", "84.200.70.40",      # DNS.Watch
    "185.228.168.9", "185.228.169.9",    # CleanBrowsing
    "76.76.19.19", "76.223.100.101",     # Alternate DNS
    "94.140.14.14", "94.140.15.15",      # AdGuard
    "8.20.247.20", "8.26.56.26",         # Comodo
    "77.88.8.8", "77.88.8.1",            # Yandex
    
    # Tier 3 - Locales/Regionales
    "156.154.70.1", "156.154.71.1",      # Neustar
    "199.85.126.10", "199.85.127.10",    # Norton
    "81.218.119.11", "209.244.0.3",      # GreenTeam
    "195.46.39.39", "195.46.39.40",      # SafeDNS
    
    # Ejemplos internos (ajustar según tu red)
    "192.168.1.1", "192.168.0.1",
    "10.0.0.1", "172.16.0.1",
]

# Dominios diversificados para pruebas exhaustivas
TEST_DOMAINS = [
    # Tier 1 - CDN globales
    "google.com", "cloudflare.com", "amazon.com", "microsoft.com",
    "facebook.com", "apple.com", "netflix.com", "twitter.com",
    
    # Tier 2 - Sitios populares
    "github.com", "wikipedia.org", "reddit.com", "stackoverflow.com",
    "linkedin.com", "instagram.com", "yahoo.com", "bing.com",
    
    # Tier 3 - Contenido multimedia
    "youtube.com", "vimeo.com", "twitch.tv", "spotify.com",
    "discord.com", "zoom.us", "dropbox.com", "wordpress.com",
    
    # Tier 4 - Servicios especializados
    "openai.com", "cnn.com", "bbc.co.uk", "nytimes.com",
    "baidu.com", "mozilla.org", "kernel.org", "ubuntu.com",
    
    # Tier 5 - Dominios técnicos y variados
    "arxiv.org", "docker.com", "kubernetes.io", "tensorflow.org",
    "pytorch.org", "jupyter.org", "anaconda.com", "nvidia.com"
]

# Configuración de Machine Learning
ML_CONFIG = {
    'min_samples_for_ml': 30,      # Mínimo de muestras para entrenar ML
    'prediction_weight': 0.25,     # Peso de predicciones ML vs métricas actuales
    'stability_threshold': 0.15,   # Umbral de variabilidad para considerar estable
    'anomaly_threshold': -0.05,    # Umbral para detección de anomalías (IsolationForest)
    'history_days': 30,            # Días de histórico a mantener
    'validation_split': 0.2,       # Porcentaje para validación
}

DEFAULT_DURATION = 300  # 5 minutos por defecto
QUICK_DURATION = 120    # 2 minutos modo rápido
LEARNING_DURATION = 900 # 15 minutos modo aprendizaje

# Directorio para datos persistentes
DATA_DIR = Path.home() / ".dns_smart_autotune"
DB_PATH = DATA_DIR / "dns_history.db"
MODEL_PATH = DATA_DIR / "dns_model.pkl"

@dataclass
class DNSMetrics:
    """Métricas completas de un servidor DNS"""
    ip: str
    samples: List[Optional[int]]
    timestamps: List[float]
    median_latency: Optional[float] = None
    mean_latency: Optional[float] = None
    std_latency: Optional[float] = None
    percentile_95: Optional[float] = None
    success_rate: float = 0.0
    stability_score: float = 0.0
    consistency_score: float = 0.0
    anomaly_score: float = 0.0
    predicted_performance: Optional[float] = None
    overall_score: float = 0.0
    
    def __post_init__(self):
        self._calculate_metrics()
    
    def _calculate_metrics(self):
        valid_samples = [s for s in self.samples if s is not None]
        if not valid_samples:
            return
            
        self.success_rate = len(valid_samples) / len(self.samples)
        self.median_latency = statistics.median(valid_samples)
        self.mean_latency = statistics.mean(valid_samples)
        self.std_latency = statistics.stdev(valid_samples) if len(valid_samples) > 1 else 0
        self.percentile_95 = np.percentile(valid_samples, 95)
        
        # Calcular scores de estabilidad y consistencia
        self._calculate_stability()
        self._calculate_consistency()
    
    def _calculate_stability(self):
        """Calcula score de estabilidad basado en variabilidad temporal"""
        if len(self.samples) < 10:
            self.stability_score = 0.5
            return
            
        valid_samples = [s for s in self.samples if s is not None]
        if len(valid_samples) < 5:
            self.stability_score = 0.0
            return
            
        # Coeficiente de variación (CV)
        cv = self.std_latency / self.mean_latency if self.mean_latency > 0 else 1
        self.stability_score = max(0, 1 - cv)
    
    def _calculate_consistency(self):
        """Calcula score de consistencia basado en patrones temporales"""
        if len(self.samples) < 20:
            self.consistency_score = 0.5
            return
            
        # Analizar ventanas deslizantes de rendimiento
        window_size = min(10, len(self.samples) // 4)
        windows = []
        
        for i in range(0, len(self.samples) - window_size + 1, window_size):
            window = self.samples[i:i + window_size]
            valid_window = [s for s in window if s is not None]
            if valid_window:
                windows.append(statistics.median(valid_window))
        
        if len(windows) < 2:
            self.consistency_score = 0.5
            return
            
        # Variabilidad entre ventanas
        window_std = statistics.stdev(windows)
        window_mean = statistics.mean(windows)
        consistency = 1 - (window_std / window_mean) if window_mean > 0 else 0
        self.consistency_score = max(0, min(1, consistency))

class DNSHistoryDB:
    """Manejo de base de datos para datos históricos"""
    
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._init_db()
    
    def _init_db(self):
        """Inicializa la base de datos"""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS dns_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ip TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    median_latency REAL,
                    mean_latency REAL,
                    std_latency REAL,
                    percentile_95 REAL,
                    success_rate REAL,
                    stability_score REAL,
                    consistency_score REAL,
                    sample_count INTEGER,
                    hour INTEGER,
                    day_of_week INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Índices para mejor performance
            conn.execute("CREATE INDEX IF NOT EXISTS idx_ip_timestamp ON dns_metrics(ip, timestamp)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_timestamp ON dns_metrics(timestamp)")
    
    def save_metrics(self, metrics: DNSMetrics, timestamp: float):
        """Guarda métricas en la base de datos"""
        if metrics.median_latency is None:
            return
            
        dt = datetime.fromtimestamp(timestamp)
        
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO dns_metrics (
                    ip, timestamp, median_latency, mean_latency, std_latency,
                    percentile_95, success_rate, stability_score, consistency_score,
                    sample_count, hour, day_of_week
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                metrics.ip, timestamp, metrics.median_latency, metrics.mean_latency,
                metrics.std_latency, metrics.percentile_95, metrics.success_rate,
                metrics.stability_score, metrics.consistency_score,
                len([s for s in metrics.samples if s is not None]),
                dt.hour, dt.weekday()
            ))
    
    def load_historical_data(self, days: int = 30) -> List[Tuple[str, Dict[str, Any], float]]:
        """Carga datos históricos para training"""
        cutoff_time = time.time() - (days * 24 * 3600)
        
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT * FROM dns_metrics 
                WHERE timestamp > ? 
                ORDER BY ip, timestamp
            """, (cutoff_time,))
            
            records = cursor.fetchall()
        
        # Organizar por IP para crear secuencias temporales
        ip_sequences = defaultdict(list)
        for record in records:
            ip_sequences[record['ip']].append(dict(record))
        
        # Crear tuplas (features, target) con target siendo la latencia futura
        training_data = []
        for ip, sequence in ip_sequences.items():
            if len(sequence) < 2:
                continue
                
            # Usar cada registro como feature y el siguiente como target
            for i in range(len(sequence) - 1):
                current = sequence[i]
                next_record = sequence[i + 1]
                
                # Features del momento actual
                features = {
                    'hour': current['hour'],
                    'day_of_week': current['day_of_week'],
                    'success_rate': current['success_rate'],
                    'median_latency': current['median_latency'],
                    'std_latency': current['std_latency'],
                    'percentile_95': current['percentile_95'],
                    'sample_count': current['sample_count'],
                    'stability_score': current['stability_score'],
                    'consistency_score': current['consistency_score']
                }
                
                # Target es la latencia del siguiente período
                target = next_record['median_latency']
                
                training_data.append((ip, features, target))
        
        return training_data
    
    def cleanup_old_data(self, days: int = 90):
        """Limpia datos antiguos"""
        cutoff_time = time.time() - (days * 24 * 3600)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("DELETE FROM dns_metrics WHERE timestamp < ?", (cutoff_time,))
            print(f"🗑️  Eliminados {cursor.rowcount} registros antiguos")
    
    def get_statistics(self) -> Dict[str, Any]:
        """Obtiene estadísticas de la base de datos"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT 
                    COUNT(*) as total_records,
                    COUNT(DISTINCT ip) as unique_ips,
                    MIN(timestamp) as oldest_record,
                    MAX(timestamp) as newest_record
                FROM dns_metrics
            """)
            
            row = cursor.fetchone()
            
            stats = {
                'total_records': row[0],
                'unique_ips': row[1],
                'oldest_record': datetime.fromtimestamp(row[2]) if row[2] else None,
                'newest_record': datetime.fromtimestamp(row[3]) if row[3] else None
            }
            
            return stats

class DNSLearningEngine:
    """Motor de aprendizaje automático para DNS con persistencia"""
    
    def __init__(self, model_path: Path):
        self.model_path = model_path
        self.model = RandomForestRegressor(
            n_estimators=100, 
            random_state=42, 
            max_depth=10,
            min_samples_split=5
        )
        self.anomaly_detector = IsolationForest(
            contamination=0.1, 
            random_state=42,
            n_estimators=50
        )
        self.scaler = StandardScaler()
        self.is_trained = False
        self.training_score = 0.0
        self.feature_names = [
            'hour', 'day_of_week', 'success_rate', 'median_latency', 
            'std_latency', 'percentile_95', 'sample_count',
            'stability_score', 'consistency_score'
        ]
        
        self._load_model()
    
    def _load_model(self):
        """Carga el modelo entrenado si existe"""
        if self.model_path.exists():
            try:
                with open(self.model_path, 'rb') as f:
                    model_data = pickle.load(f)
                    
                self.model = model_data['model']
                self.anomaly_detector = model_data['anomaly_detector']
                self.scaler = model_data['scaler']
                self.is_trained = model_data['is_trained']
                self.training_score = model_data.get('training_score', 0.0)
                
                print(f"✅ Modelo ML cargado (score: {self.training_score:.3f})")
                
            except Exception as e:
                print(f"⚠️  Error cargando modelo: {e}")
                self.is_trained = False
    
    def _save_model(self):
        """Guarda el modelo entrenado"""
        self.model_path.parent.mkdir(parents=True, exist_ok=True)
        
        model_data = {
            'model': self.model,
            'anomaly_detector': self.anomaly_detector,
            'scaler': self.scaler,
            'is_trained': self.is_trained,
            'training_score': self.training_score,
            'trained_at': time.time()
        }
        
        try:
            with open(self.model_path, 'wb') as f:
                pickle.dump(model_data, f)
            print(f"💾 Modelo guardado en {self.model_path}")
            
        except Exception as e:
            print(f"❌ Error guardando modelo: {e}")
    
    def extract_features(self, features_dict: Dict[str, Any]) -> np.ndarray:
        """Extrae características para ML desde un diccionario"""
        feature_values = []
        for name in self.feature_names:
            value = features_dict.get(name, 0)
            # Manejar valores None
            if value is None:
                if 'latency' in name:
                    value = 1000  # Alta latencia por defecto
                else:
                    value = 0
            feature_values.append(value)
        
        return np.array(feature_values).reshape(1, -1)
    
    def train(self, training_data: List[Tuple[str, Dict[str, Any], float]]) -> bool:
        """Entrena el modelo con datos históricos"""
        if len(training_data) < ML_CONFIG['min_samples_for_ml']:
            print(f"⚠️  Insuficientes datos para ML ({len(training_data)} < {ML_CONFIG['min_samples_for_ml']})")
            return False
        
        print(f"🧠 Entrenando modelo ML con {len(training_data)} muestras...")
        
        X = []
        y = []
        
        for ip, features, target in training_data:
            feature_vector = self.extract_features(features).flatten()
            X.append(feature_vector)
            y.append(target)
        
        X = np.array(X)
        y = np.array(y)
        
        # Validar datos
        if len(X) == 0 or len(y) == 0:
            print("❌ No hay datos válidos para entrenar")
            return False
        
        # Normalizar características
        X_scaled = self.scaler.fit_transform(X)
        
        # División temporal para validación (TimeSeriesSplit es más apropiado)
        tscv = TimeSeriesSplit(n_splits=3)
        
        # Entrenar modelo de regresión con validación cruzada
        cv_scores = cross_val_score(self.model, X_scaled, y, cv=tscv, scoring='neg_mean_absolute_error')
        self.training_score = -cv_scores.mean()
        
        # Entrenar con todos los datos
        self.model.fit(X_scaled, y)
        
        # Entrenar detector de anomalías
        self.anomaly_detector.fit(X_scaled)
        
        # Evaluar modelo
        y_pred = self.model.predict(X_scaled)
        mae = mean_absolute_error(y, y_pred)
        rmse = np.sqrt(mean_squared_error(y, y_pred))
        
        print(f"📊 Modelo entrenado - MAE: {mae:.2f}ms, RMSE: {rmse:.2f}ms, CV Score: {self.training_score:.2f}ms")
        
        self.is_trained = True
        self._save_model()
        
        return True
    
    def predict_performance(self, features_dict: Dict[str, Any]) -> Optional[float]:
        """Predice el rendimiento futuro"""
        if not self.is_trained:
            return None
            
        try:
            features = self.extract_features(features_dict)
            features_scaled = self.scaler.transform(features)
            
            prediction = self.model.predict(features_scaled)[0]
            return max(0, prediction)
            
        except Exception as e:
            print(f"⚠️  Error en predicción: {e}")
            return None
    
    def detect_anomaly(self, features_dict: Dict[str, Any]) -> float:
        """Detecta anomalías en el rendimiento"""
        if not self.is_trained:
            return 0.0
            
        try:
            features = self.extract_features(features_dict)
            features_scaled = self.scaler.transform(features)
            
            # IsolationForest devuelve valores negativos para anomalías
            anomaly_score = self.anomaly_detector.decision_function(features_scaled)[0]
            return anomaly_score
            
        except Exception as e:
            print(f"⚠️  Error en detección de anomalías: {e}")
            return 0.0
    
    def get_feature_importance(self) -> Dict[str, float]:
        """Obtiene la importancia de las características"""
        if not self.is_trained or not hasattr(self.model, 'feature_importances_'):
            return {}
            
        importance_dict = {}
        for name, importance in zip(self.feature_names, self.model.feature_importances_):
            importance_dict[name] = importance
            
        return importance_dict

class SmartDNSBenchmark:
    """Benchmark inteligente de DNS con ML persistente"""
    
    def __init__(self, duration: int = DEFAULT_DURATION, verbose: bool = True):
        self.duration = duration
        self.verbose = verbose
        self.db = DNSHistoryDB(DB_PATH)
        self.learning_engine = DNSLearningEngine(MODEL_PATH)
        self.dns_metrics: Dict[str, DNSMetrics] = {}
        self.start_time = time.time()
        
        # Limpiar datos antiguos al iniciar
        self.db.cleanup_old_data()
        
        # Entrenar modelo con datos históricos
        self._train_from_history()
    
    def _train_from_history(self):
        """Entrena el modelo con datos históricos existentes"""
        historical_data = self.db.load_historical_data(ML_CONFIG['history_days'])
        
        if historical_data:
            print(f"📚 Cargando {len(historical_data)} registros históricos...")
            self.learning_engine.train(historical_data)
        else:
            print("📝 No hay datos históricos, comenzando aprendizaje desde cero")
    
    async def single_query(self, resolver: dns.asyncresolver.Resolver, domain: str, timeout: float = 0.5) -> Optional[int]:
        """Realiza una consulta DNS individual"""
        t0 = time.perf_counter()
        try:
            await resolver.resolve(domain, "A", lifetime=timeout)
            return int((time.perf_counter() - t0) * 1000)
        except Exception:
            return None
    
    async def benchmark_dns_continuous(self, ip: str) -> DNSMetrics:
        """Benchmark continuo de un servidor DNS"""
        resolver = dns.asyncresolver.Resolver(configure=False)
        resolver.nameservers = [ip]
        
        samples = []
        timestamps = []
        end_time = self.start_time + self.duration
        
        if self.verbose:
            print(f"🔍 Iniciando análisis continuo de {ip}...")
        
        query_count = 0
        while time.time() < end_time:
            # Seleccionar dominio aleatoriamente para mayor variabilidad
            domain = np.random.choice(TEST_DOMAINS)
            
            # Variar timeout según el progreso
            progress = (time.time() - self.start_time) / self.duration
            timeout = 0.3 + (0.7 * progress)  # De 0.3s a 1.0s
            
            latency = await self.single_query(resolver, domain, timeout)
            samples.append(latency)
            timestamps.append(time.time())
            query_count += 1
            
            if self.verbose and query_count % 20 == 0:
                valid_count = len([s for s in samples if s is not None])
                success_rate = valid_count / len(samples) * 100 if samples else 0
                recent_latency = statistics.median([s for s in samples[-10:] if s is not None]) if samples else None
                lat_str = f"{recent_latency:.0f}ms" if recent_latency else "N/A"
                print(f"  {ip}: {query_count} consultas, {success_rate:.1f}% éxito, lat: {lat_str}")
            
            # Pausa adaptativa basada en rendimiento reciente
            recent_failures = samples[-5:].count(None) if len(samples) >= 5 else 0
            pause = 0.1 + (recent_failures * 0.05)  # Más pausa si hay fallos
            await asyncio.sleep(pause)
        
        metrics = DNSMetrics(ip=ip, samples=samples, timestamps=timestamps)
        
        # Usar ML si está disponible
        if self.learning_engine.is_trained and metrics.median_latency is not None:
            dt = datetime.now()
            features = {
                'hour': dt.hour,
                'day_of_week': dt.weekday(),
                'success_rate': metrics.success_rate,
                'median_latency': metrics.median_latency,
                'std_latency': metrics.std_latency,
                'percentile_95': metrics.percentile_95,
                'sample_count': len([s for s in metrics.samples if s is not None]),
                'stability_score': metrics.stability_score,
                'consistency_score': metrics.consistency_score
            }
            
            metrics.predicted_performance = self.learning_engine.predict_performance(features)
            metrics.anomaly_score = self.learning_engine.detect_anomaly(features)
        
        # Guardar en base de datos para aprendizaje futuro
        self.db.save_metrics(metrics, time.time())
        
        return metrics
    
    async def run_benchmark(self, dns_servers: List[str]) -> Dict[str, DNSMetrics]:
        """Ejecuta benchmark en paralelo para todos los servidores"""
        if self.verbose:
            print(f"🚀 Iniciando benchmark inteligente para {len(dns_servers)} servidores DNS")
            print(f"⏱️  Duración: {self.duration} segundos")
            print(f"🌐 Dominios de prueba: {len(TEST_DOMAINS)}")
            
            # Mostrar estadísticas de aprendizaje
            stats = self.db.get_statistics()
            if stats['total_records'] > 0:
                print(f"🧠 Base de conocimiento: {stats['total_records']} registros, {stats['unique_ips']} IPs")
                if self.learning_engine.is_trained:
                    print(f"🎯 Modelo ML activo (precisión: {self.learning_engine.training_score:.2f}ms MAE)")
            print()
        
        # Ejecutar benchmarks en paralelo
        tasks = [self.benchmark_dns_continuous(ip) for ip in dns_servers]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Procesar resultados
        metrics_dict = {}
        for result in results:
            if isinstance(result, DNSMetrics):
                metrics_dict[result.ip] = result
            elif isinstance(result, Exception):
                print(f"❌ Error en benchmark: {result}")
        
        return metrics_dict
    
    def calculate_overall_scores(self, metrics_dict: Dict[str, DNSMetrics]):
        """Calcula scores generales basados en múltiples factores"""
        for metrics in metrics_dict.values():
            if metrics.median_latency is None:
                metrics.overall_score = 0.0
                continue
            
            # Componentes del score (pesos normalizados que suman 1.0)
            latency_score = max(0, 1 - (metrics.median_latency / 500))  # 0-500ms
            success_score = metrics.success_rate
            stability_score = metrics.stability_score
            consistency_score = metrics.consistency_score
            
            # Score de anomalías (normalizar IsolationForest output)
            # Valores > 0 son normales, < 0 son anómalas
            anomaly_score = max(0, min(1, (metrics.anomaly_score + 0.5) / 1.0)) if metrics.anomaly_score else 0.5
            
            # Score de predicción ML
            prediction_score = 0.5  # Default neutral
            if metrics.predicted_performance and self.learning_engine.is_trained:
                # Comparar predicción con latencia actual
                prediction_accuracy = 1 - abs(metrics.predicted_performance - metrics.median_latency) / max(metrics.median_latency, 1)
                prediction_score = max(0, min(1, prediction_accuracy))
            
            # Pesos normalizados que suman 1.0
            weights = {
                'latency': 0.30,     # Latencia es lo más importante
                'success': 0.25,     # Tasa de éxito
                'stability': 0.20,   # Estabilidad temporal
                'consistency': 0.15, # Consistencia
                'anomaly': 0.07,     # Detección de anomalías
                'prediction': 0.03   # Precisión de predicción ML
            }
            
            # Calcular score ponderado
            overall = (
                latency_score * weights['latency'] +
                success_score * weights['success'] +
                stability_score * weights['stability'] +
                consistency_score * weights['consistency'] +
                anomaly_score * weights['anomaly'] +
                prediction_score * weights['prediction']
            )
            
            metrics.overall_score = min(1.0, max(0.0, overall))
    
    def print_detailed_results(self, metrics_dict: Dict[str, DNSMetrics]):
        """Imprime resultados detallados"""
        if not self.verbose:
            return
            
        print("\n" + "="*80)
        print("📊 RESULTADOS DETALLADOS DEL ANÁLISIS DNS")
        print("="*80)
        
        # Mostrar importancia de características si el modelo está entrenado
        if self.learning_engine.is_trained:
            importance = self.learning_engine.get_feature_importance()
            if importance:
                print("\n🧠 Importancia de características en el modelo ML:")
                sorted_importance = sorted(importance.items(), key=lambda x: x[1], reverse=True)
                for feature, imp in sorted_importance[:5]:  # Top 5
                    print(f"   {feature}: {imp:.3f}")
        
        # Ordenar por score general
        sorted_metrics = sorted(
            [m for m in metrics_dict.values() if m.median_latency is not None], 
            key=lambda m: m.overall_score, 
            reverse=True
        )
        
        print(f"\n🏆 Top {min(10, len(sorted_metrics))} servidores DNS:")
        print("-" * 80)
        
        for i, metrics in enumerate(sorted_metrics[:10], 1):
            try:
                is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            except:
                is_internal = False
                
            location = "🏠 Interno" if is_internal else "🌐 Externo"
            
            print(f"\n{i:2d}. {metrics.ip:<15} {location}")
            print(f"    ⚡ Latencia: {metrics.median_latency:6.1f}ms (±{metrics.std_latency:5.1f}ms, P95: {metrics.percentile_95:6.1f}ms)")
            print(f"    ✅ Éxito: {metrics.success_rate*100:6.1f}% ({len([s for s in metrics.samples if s is not None])}/{len(metrics.samples)} consultas)")
            print(f"    📊 Estabilidad: {metrics.stability_score:6.3f}  🎯 Consistencia: {metrics.consistency_score:6.3f}")
            
            if metrics.anomaly_score:
                anomaly_status = "🔴 Anómalo" if metrics.anomaly_score < ML_CONFIG['anomaly_threshold'] else "🟢 Normal"
                print(f"    🔍 Anomalías: {metrics.anomaly_score:6.3f} ({anomaly_status})")
            
            if metrics.predicted_performance and self.learning_engine.is_trained:
                prediction_diff = abs(metrics.predicted_performance - metrics.median_latency)
                accuracy_emoji = "🎯" if prediction_diff < 50 else "📊"
                print(f"    🤖 Predicción ML: {metrics.predicted_performance:6.1f}ms {accuracy_emoji}")
            
            print(f"    🏆 Score General: {metrics.overall_score:6.3f}")
    
    def generate_smart_resolv_conf(self, metrics_dict: Dict[str, DNSMetrics], output_path: Path):
        """Genera configuración optimizada inteligentemente"""
        # Filtrar servidores válidos
        valid_metrics = [
            m for m in metrics_dict.values() 
            if m.median_latency is not None and m.success_rate > 0.6 and m.overall_score > 0.3
        ]
        
        if not valid_metrics:
            print("❌ No se encontraron servidores DNS válidos")
            return
        
        # Ordenar por score general
        valid_metrics.sort(key=lambda m: m.overall_score, reverse=True)
        
        # Selección inteligente balanceada
        selected = []
        internal_count = 0
        external_count = 0
        max_internal = 2
        max_external = 4
        
        for metrics in valid_metrics:
            try:
                is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            except:
                is_internal = False
            
            if is_internal and internal_count < max_internal:
                selected.append(metrics)
                internal_count += 1
            elif not is_internal and external_count < max_external:
                selected.append(metrics)
                external_count += 1
            
            if len(selected) >= 6:  # Máximo total
                break
        
        # Generar archivo de configuración
        lines = [
            "# Configuración DNS optimizada con Machine Learning Persistente\n",
            f"# Generado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n",
            f"# Análisis durante {self.duration} segundos\n",
            f"# Servidores analizados: {len(metrics_dict)}\n"
        ]
        
        if self.learning_engine.is_trained:
            lines.append(f"# Modelo ML activo (precisión: {self.learning_engine.training_score:.2f}ms MAE)\n")
        
        stats = self.db.get_statistics()
        lines.append(f"# Base de conocimiento: {stats['total_records']} registros históricos\n")
        lines.append("#\n")
        lines.append("# Configuración adaptativa e inteligente\n")
        lines.append("options timeout:2 attempts:3 rotate ndots:1 edns0\n\n")
        
        for i, metrics in enumerate(selected, 1):
            try:
                is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            except:
                is_internal = False
                
            location = "Interno" if is_internal else "Externo"
            
            lines.append(f"# {i}. {location} DNS - Score: {metrics.overall_score:.3f}\n")
            lines.append(f"# Latencia: {metrics.median_latency:.1f}ms (±{metrics.std_latency:.1f}), Éxito: {metrics.success_rate*100:.1f}%\n")
            lines.append(f"# Estabilidad: {metrics.stability_score:.3f}, Consistencia: {metrics.consistency_score:.3f}\n")
            
            if metrics.predicted_performance and self.learning_engine.is_trained:
                lines.append(f"# Predicción ML: {metrics.predicted_performance:.1f}ms\n")
            
            lines.append(f"nameserver {metrics.ip}\n\n")
        
        try:
            output_path.write_text("".join(lines))
            print(f"\n✅ Configuración inteligente generada: {output_path}")
            print(f"📈 Servidores seleccionados: {len(selected)} ({internal_count} internos, {external_count} externos)")
            
            if self.learning_engine.is_trained:
                print(f"🧠 Configuración basada en {stats['total_records']} registros históricos")
                
        except Exception as e:
            print(f"❌ Error escribiendo configuración: {e}")

def main():
    parser = argparse.ArgumentParser(
        description="Benchmark inteligente DNS con Machine Learning persistente",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ejemplos de uso:
  sudo python3 dns_smart_autotune.py                    # Análisis normal con aprendizaje
  sudo python3 dns_smart_autotune.py --duration 600     # 10 minutos de análisis
  sudo python3 dns_smart_autotune.py --quick            # Análisis rápido (2 min)
  sudo python3 dns_smart_autotune.py --learning         # Modo aprendizaje intensivo (15 min)
  sudo python3 dns_smart_autotune.py --reset-learning   # Reiniciar datos de aprendizaje
  sudo python3 dns_smart_autotune.py --stats            # Mostrar estadísticas del modelo
        """
    )
    
    parser.add_argument(
        '--duration', '-d', type=int, default=DEFAULT_DURATION,
        help=f'Duración en segundos (default: {DEFAULT_DURATION})'
    )
    
    parser.add_argument(
        '--quick', action='store_true',
        help=f'Análisis rápido ({QUICK_DURATION} segundos)'
    )
    
    parser.add_argument(
        '--learning', action='store_true', 
        help=f'Modo aprendizaje intensivo ({LEARNING_DURATION} segundos)'
    )
    
    parser.add_argument(
        '--quiet', '-q', action='store_true',
        help='Modo silencioso'
    )
    
    parser.add_argument(
        '--output', '-o', default='/etc/resolv.smart.conf',
        help='Archivo de salida (default: /etc/resolv.smart.conf)'
    )
    
    parser.add_argument(
        '--servers', nargs='+',
        help='Lista específica de servidores DNS a probar'
    )
    
    parser.add_argument(
        '--reset-learning', action='store_true',
        help='Reiniciar todos los datos de aprendizaje'
    )
    
    parser.add_argument(
        '--stats', action='store_true',
        help='Mostrar estadísticas del modelo y salir'
    )
    
    args = parser.parse_args()
    
    # Manejar reset de aprendizaje
    if args.reset_learning:
        if DB_PATH.exists():
            DB_PATH.unlink()
            print(f"🗑️  Base de datos eliminada: {DB_PATH}")
        if MODEL_PATH.exists():
            MODEL_PATH.unlink()
            print(f"🗑️  Modelo ML eliminado: {MODEL_PATH}")
        print("✅ Datos de aprendizaje reiniciados")
        return
    
    # Mostrar estadísticas y salir
    if args.stats:
        if not DB_PATH.exists():
            print("📝 No hay datos históricos disponibles")
            return
            
        db = DNSHistoryDB(DB_PATH)
        stats = db.get_statistics()
        learning_engine = DNSLearningEngine(MODEL_PATH)
        
        print("📊 Estadísticas del Sistema de Aprendizaje DNS")
        print("=" * 50)
        print(f"📚 Total de registros: {stats['total_records']}")
        print(f"🌐 IPs únicas analizadas: {stats['unique_ips']}")
        
        if stats['oldest_record']:
            print(f"📅 Registro más antiguo: {stats['oldest_record'].strftime('%Y-%m-%d %H:%M')}")
        if stats['newest_record']:
            print(f"📅 Registro más reciente: {stats['newest_record'].strftime('%Y-%m-%d %H:%M')}")
        
        if learning_engine.is_trained:
            print(f"🧠 Modelo ML: ✅ Entrenado (MAE: {learning_engine.training_score:.2f}ms)")
            
            importance = learning_engine.get_feature_importance()
            if importance:
                print("\n🔍 Características más importantes:")
                sorted_importance = sorted(importance.items(), key=lambda x: x[1], reverse=True)
                for feature, imp in sorted_importance:
                    print(f"   {feature}: {imp:.3f}")
        else:
            print("🧠 Modelo ML: ❌ No entrenado")
        
        return
    
    # Determinar duración
    if args.quick:
        duration = QUICK_DURATION
    elif args.learning:
        duration = LEARNING_DURATION
    else:
        duration = args.duration
    
    # Determinar servidores
    servers = args.servers if args.servers else DNS_CANDIDATES
    
    # Filtrar servidores válidos
    valid_servers = []
    for server in servers:
        try:
            ipaddress.ip_address(server)
            valid_servers.append(server)
        except ValueError:
            if not args.quiet:
                print(f"⚠️  IP inválida ignorada: {server}")
    
    if not valid_servers:
        print("❌ No hay servidores DNS válidos para probar")
        sys.exit(1)
    
    # Ejecutar benchmark
    benchmark = SmartDNSBenchmark(duration=duration, verbose=not args.quiet)
    
    try:
        start_time = time.time()
        
        if not args.quiet:
            print(f"🚀 Iniciando DNS Smart Autotune v4")
            print(f"📍 Datos almacenados en: {DATA_DIR}")
        
        # Ejecutar análisis
        metrics_dict = asyncio.run(benchmark.run_benchmark(valid_servers))
        
        # Calcular scores
        benchmark.calculate_overall_scores(metrics_dict)
        
        # Mostrar resultados
        benchmark.print_detailed_results(metrics_dict)
        
        # Generar configuración
        output_path = Path(args.output).expanduser()
        benchmark.generate_smart_resolv_conf(metrics_dict, output_path)
        
        total_time = time.time() - start_time
        
        if not args.quiet:
            print(f"\n⏱️  Análisis completado en {total_time:.1f} segundos")
            
            # Mostrar estadísticas finales
            stats = benchmark.db.get_statistics()
            print(f"💾 Total de registros en base: {stats['total_records']}")
            
            if benchmark.learning_engine.is_trained:
                print(f"🎯 Modelo ML mejorando continuamente (precisión actual: {benchmark.learning_engine.training_score:.2f}ms)")
        
    except KeyboardInterrupt:
        print("\n🛑 Análisis interrumpido por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error durante el análisis: {e}")
        import traceback
        if not args.quiet:
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
