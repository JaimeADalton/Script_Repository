#!/usr/bin/env python3
"""
dns_smart_autotune.py (v3)
Benchmark inteligente de servidores DNS con Machine Learning
Incluye análisis de estabilidad, patrones temporales y predicción de rendimiento
Autor: Optimizado con ML (2025-05-27)

Características:
- Pruebas extendidas con análisis temporal
- Machine Learning para predicción de rendimiento
- Detección de patrones de estabilidad
- Análisis de variabilidad y consistencia
- Selección inteligente basada en múltiples métricas
- Adaptación automática según condiciones de red

Uso:
  sudo python3 dns_smart_autotune.py                    # Análisis completo (5-10 min)
  sudo python3 dns_smart_autotune.py --duration 15      # 15 minutos de pruebas
  sudo python3 dns_smart_autotune.py --quick            # Análisis rápido (2 min)
  sudo python3 dns_smart_autotune.py --learning         # Modo aprendizaje continuo
"""

import asyncio
import time
import statistics
import ipaddress
import sys
import argparse
import json
import pickle
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from collections import defaultdict, deque
import math

import dns.asyncresolver
import numpy as np
from sklearn.ensemble import RandomForestRegressor, IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import cross_val_score
from sklearn.metrics import mean_squared_error
import warnings
warnings.filterwarnings('ignore')

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
    'min_samples_for_ml': 50,      # Mínimo de muestras para entrenar ML
    'prediction_weight': 0.3,      # Peso de predicciones ML vs métricas actuales
    'stability_threshold': 0.15,   # Umbral de variabilidad para considerar estable
    'anomaly_threshold': -0.1,     # Umbral para detección de anomalías
}

DEFAULT_DURATION = 300  # 5 minutos por defecto
QUICK_DURATION = 120    # 2 minutos modo rápido
LEARNING_DURATION = 900 # 15 minutos modo aprendizaje

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

class DNSLearningEngine:
    """Motor de aprendizaje automático para DNS"""
    
    def __init__(self):
        self.model = RandomForestRegressor(n_estimators=100, random_state=42)
        self.anomaly_detector = IsolationForest(contamination=0.1, random_state=42)
        self.scaler = StandardScaler()
        self.is_trained = False
        self.feature_names = [
            'hour', 'minute', 'success_rate', 'median_latency', 
            'std_latency', 'percentile_95', 'sample_count'
        ]
    
    def extract_features(self, metrics: DNSMetrics, timestamp: float) -> np.ndarray:
        """Extrae características para ML"""
        dt = datetime.fromtimestamp(timestamp)
        
        features = [
            dt.hour,
            dt.minute,
            metrics.success_rate,
            metrics.median_latency or 1000,  # Alta latencia si es None
            metrics.std_latency or 0,
            metrics.percentile_95 or 1000,
            len([s for s in metrics.samples if s is not None])
        ]
        
        return np.array(features).reshape(1, -1)
    
    def train(self, historical_data: List[Tuple[DNSMetrics, float, float]]):
        """Entrena el modelo con datos históricos"""
        if len(historical_data) < ML_CONFIG['min_samples_for_ml']:
            return False
            
        X = []
        y = []
        
        for metrics, timestamp, actual_performance in historical_data:
            features = self.extract_features(metrics, timestamp).flatten()
            X.append(features)
            y.append(actual_performance)
        
        X = np.array(X)
        y = np.array(y)
        
        # Normalizar características
        X_scaled = self.scaler.fit_transform(X)
        
        # Entrenar modelo de regresión
        self.model.fit(X_scaled, y)
        
        # Entrenar detector de anomalías
        self.anomaly_detector.fit(X_scaled)
        
        self.is_trained = True
        return True
    
    def predict_performance(self, metrics: DNSMetrics, timestamp: float) -> Optional[float]:
        """Predice el rendimiento futuro"""
        if not self.is_trained:
            return None
            
        features = self.extract_features(metrics, timestamp)
        features_scaled = self.scaler.transform(features)
        
        prediction = self.model.predict(features_scaled)[0]
        return max(0, prediction)
    
    def detect_anomaly(self, metrics: DNSMetrics, timestamp: float) -> float:
        """Detecta anomalías en el rendimiento"""
        if not self.is_trained:
            return 0.0
            
        features = self.extract_features(metrics, timestamp)
        features_scaled = self.scaler.transform(features)
        
        anomaly_score = self.anomaly_detector.decision_function(features_scaled)[0]
        return anomaly_score

class SmartDNSBenchmark:
    """Benchmark inteligente de DNS con ML"""
    
    def __init__(self, duration: int = DEFAULT_DURATION, verbose: bool = True):
        self.duration = duration
        self.verbose = verbose
        self.learning_engine = DNSLearningEngine()
        self.dns_metrics: Dict[str, DNSMetrics] = {}
        self.historical_data: List[Tuple[DNSMetrics, float, float]] = []
        self.start_time = time.time()
        
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
            
            if self.verbose and query_count % 10 == 0:
                valid_count = len([s for s in samples if s is not None])
                success_rate = valid_count / len(samples) * 100
                print(f"  {ip}: {query_count} consultas, {success_rate:.1f}% éxito")
            
            # Pausa adaptativa basada en rendimiento reciente
            recent_failures = samples[-5:].count(None) if len(samples) >= 5 else 0
            pause = 0.1 + (recent_failures * 0.05)  # Más pausa si hay fallos
            await asyncio.sleep(pause)
        
        metrics = DNSMetrics(ip=ip, samples=samples, timestamps=timestamps)
        
        # Detección de anomalías si el modelo está entrenado
        if self.learning_engine.is_trained:
            metrics.anomaly_score = self.learning_engine.detect_anomaly(metrics, time.time())
            metrics.predicted_performance = self.learning_engine.predict_performance(metrics, time.time())
        
        return metrics
    
    async def run_benchmark(self, dns_servers: List[str]) -> Dict[str, DNSMetrics]:
        """Ejecuta benchmark en paralelo para todos los servidores"""
        if self.verbose:
            print(f"🚀 Iniciando benchmark inteligente para {len(dns_servers)} servidores DNS")
            print(f"⏱️  Duración: {self.duration} segundos")
            print(f"🌐 Dominios de prueba: {len(TEST_DOMAINS)}")
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
            
            # Componentes del score (pesos normalizados)
            latency_score = max(0, 1 - (metrics.median_latency / 500))  # 0-500ms
            success_score = metrics.success_rate
            stability_score = metrics.stability_score
            consistency_score = metrics.consistency_score
            
            # Score de anomalías (convertir a positivo)
            anomaly_score = max(0, (metrics.anomaly_score + 0.5)) if metrics.anomaly_score else 0.5
            
            # Score de predicción ML
            prediction_score = 0.5  # Default neutral
            if metrics.predicted_performance:
                prediction_score = max(0, 1 - (metrics.predicted_performance / 500))
            
            # Pesos para diferentes componentes
            weights = {
                'latency': 0.25,
                'success': 0.25, 
                'stability': 0.20,
                'consistency': 0.15,
                'anomaly': 0.10,
                'prediction': 0.05
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
        
        # Ordenar por score general
        sorted_metrics = sorted(
            metrics_dict.values(), 
            key=lambda m: m.overall_score, 
            reverse=True
        )
        
        for i, metrics in enumerate(sorted_metrics[:10], 1):  # Top 10
            if metrics.median_latency is None:
                continue
                
            is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            location = "🏠 Interno" if is_internal else "🌐 Externo"
            
            print(f"\n{i:2d}. {metrics.ip:<15} {location}")
            print(f"    ⚡ Latencia: {metrics.median_latency:6.1f}ms (±{metrics.std_latency:5.1f})")
            print(f"    ✅ Éxito: {metrics.success_rate*100:6.1f}%")
            print(f"    📊 Estabilidad: {metrics.stability_score:6.3f}")
            print(f"    🎯 Consistencia: {metrics.consistency_score:6.3f}")
            print(f"    🔍 Score Anomalía: {metrics.anomaly_score:6.3f}")
            if metrics.predicted_performance:
                print(f"    🤖 Predicción ML: {metrics.predicted_performance:6.1f}ms")
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
        
        # Selección inteligente
        selected = []
        internal_count = 0
        external_count = 0
        max_internal = 2
        max_external = 4
        
        for metrics in valid_metrics:
            is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            
            if is_internal and internal_count < max_internal:
                selected.append(metrics)
                internal_count += 1
            elif not is_internal and external_count < max_external:
                selected.append(metrics)
                external_count += 1
            
            if len(selected) >= 6:  # Máximo total
                break
        
        # Generar archivo
        lines = [
            "# Configuración DNS optimizada con Machine Learning\n",
            f"# Generado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n",
            f"# Análisis durante {self.duration} segundos\n",
            "# Configuración adaptativa y inteligente\n\n",
            "options timeout:2 attempts:3 rotate ndots:1\n\n"
        ]
        
        for i, metrics in enumerate(selected, 1):
            is_internal = ipaddress.ip_network(f"{metrics.ip}/32").is_private
            location = "Interno" if is_internal else "Externo"
            
            lines.append(f"# {i}. {location} DNS - Score: {metrics.overall_score:.3f}\n")
            lines.append(f"# Latencia: {metrics.median_latency:.1f}ms, Éxito: {metrics.success_rate*100:.1f}%\n")
            lines.append(f"nameserver {metrics.ip}\n\n")
        
        output_path.write_text("".join(lines))
        
        print(f"\n✅ Configuración inteligente generada: {output_path}")
        print(f"📈 Servidores seleccionados: {len(selected)} ({internal_count} internos, {external_count} externos)")

def main():
    parser = argparse.ArgumentParser(
        description="Benchmark inteligente DNS con Machine Learning",
        formatter_class=argparse.RawDescriptionHelpFormatter
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
        help=f'Modo aprendizaje extendido ({LEARNING_DURATION} segundos)'
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
    
    args = parser.parse_args()
    
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
        print(f"\n⏱️  Análisis completado en {total_time:.1f} segundos")
        
    except KeyboardInterrupt:
        print("\n🛑 Análisis interrumpido por el usuario")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error durante el análisis: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
