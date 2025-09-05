#!/usr/bin/env python3
"""Telegraf HTTP/ICMP Configuration Manager for Dockerized Environments

Este script gestiona la creación y eliminación de configuraciones de monitoreo
HTTP e ICMP para un servicio Telegraf que se ejecuta en un contenedor Docker.

Funcionalidades:
- Genera configuraciones HTTP para monitoreo de URLs
- Genera configuraciones ICMP (ping) para las IPs resueltas de las URLs
- Gestión automática de permisos para contenedores Docker
"""

import argparse
import configparser
import logging
import os
import re
import socket
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("telegraf_manager")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
_IP_PATTERN = re.compile(r"^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$")

def is_valid_ip(ip: str) -> bool:
    """Valida si una cadena de texto es una dirección IPv4 válida."""
    return _IP_PATTERN.match(ip) is not None

def is_valid_url(url: str) -> bool:
    """Valida si una cadena de texto es una URL válida."""
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except:
        return False

def resolve_domain_to_ip(url: str) -> str | None:
    """Resuelve un dominio de una URL a su dirección IP."""
    try:
        parsed = urlparse(url)
        hostname = parsed.hostname
        if not hostname:
            return None
        ip = socket.gethostbyname(hostname)
        logger.debug(f"Resuelto {hostname} -> {ip}")
        return ip
    except Exception as exc:
        logger.error(f"Error al resolver {url}: {exc}")
        return None

def prompt_yes_no(question: str) -> bool:
    """Muestra un prompt y/n que se bloquea hasta recibir una respuesta válida."""
    while True:
        answer = input(f"{question} (y/n): ").strip().lower()
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Por favor, responde 'y' o 'n'.")

_SANITIZE = re.compile(r"[^\w\-.]")

def sanitize(text: str) -> str:
    """Limpia una cadena para que sea segura como nombre de archivo."""
    return _SANITIZE.sub("_", text)

# ---------------------------------------------------------------------------
# TelegrafManager
# ---------------------------------------------------------------------------
class TelegrafManager:
    """Crea/elimina configuraciones de HTTP e ICMP y recarga Telegraf."""

    DEFAULTS = {
        "telegraf_dir": "telegraf/telegraf.d",
        "ping_count": 10,
        "ping_interval": "60s",
        "http_interval": "60s",
        "http_timeout": "120s",
    }

    def __init__(self, config_file: str | None = None):
        self.config: dict[str, str | int] = self.DEFAULTS.copy()
        if config_file and os.path.exists(config_file):
            self._load_config(config_file)

        # UID/GID objetivo para la propiedad de los archivos (usuario telegraf en Docker)
        self._uid = 999
        self._gid = 999
        logger.debug(f"Usando UID={self._uid} y GID={self._gid} para los permisos de archivo.")

    def _load_config(self, path: str) -> None:
        try:
            cp = configparser.ConfigParser()
            cp.read(path)
            section = cp["TelegrafManager"] if "TelegrafManager" in cp else {}
            for k, v in section.items():
                self.config[k] = int(v) if v.isdigit() else v
            logger.info("Configuración cargada desde %s", path)
        except Exception as exc:
            logger.error("La lectura de %s falló: %s", path, exc)

    def _fix_perms(self, path: str | Path, directory: bool = False) -> None:
        mode = 0o755 if directory else 0o644
        try:
            os.chown(path, self._uid, self._gid)
            os.chmod(path, mode)
            logger.debug("Permisos de %s establecidos a %s (UID/GID: %d:%d)", path, oct(mode), self._uid, self._gid)
        except PermissionError:
            logger.error(
                "Error de permisos al intentar cambiar el propietario de %s. "
                "Ejecuta este script con 'sudo' para poder asignar los permisos correctos para Docker.",
                path
            )
        except Exception as exc:
            logger.error("Fallo al establecer permisos en %s: %s", path, exc)

    @property
    def tgf_dir(self) -> str:
        return str(self.config["telegraf_dir"])

    def list_sites(self) -> list[str]:
        path = Path(self.tgf_dir)
        try:
            if not path.exists():
                logger.info("Creando directorio de configuración %s", path)
                path.mkdir(parents=True, exist_ok=True)
                self._fix_perms(path, directory=True)
            return sorted([p.name for p in path.iterdir() if p.is_dir()])
        except Exception as exc:
            logger.error("Fallo al listar los sitios: %s", exc)
            return []

    def create_site(self, raw_name: str) -> str | None:
        name = sanitize(raw_name)
        site_path = Path(self.tgf_dir, name)
        if site_path.exists():
            logger.info("El sitio %s ya existe.", name)
            return name
        try:
            site_path.mkdir(parents=True, exist_ok=True)
            self._fix_perms(site_path, directory=True)
            logger.info("Sitio %s creado.", name)
            return name
        except Exception as exc:
            logger.error("Fallo al crear el sitio %s: %s", name, exc)
            return None

    def _http_cfg(self, urls: list[str], site: str) -> str:
        """Genera configuración HTTP para múltiples URLs."""
        measurement_name = sanitize(site)
        urls_formatted = ",\n    ".join([f'"{url}"' for url in urls])

        return f"""# Auto-generado por telegraf_manager – NO EDITAR MANUALMENTE
#
# Configuración de monitoreo HTTP para el sitio '{site}'
# URLs monitoreadas: {len(urls)} URLs
# Measurement en InfluxDB: {measurement_name}

[[inputs.http_response]]
  interval  = "{self.config['http_interval']}"
  precision = "60s"
  urls = [
    {urls_formatted}
  ]
  response_timeout   = "{self.config['http_timeout']}"
  follow_redirects   = true
  method             = "HEAD"
  name_override      = "{measurement_name}"
  insecure_skip_verify = true

  [inputs.http_response.headers]
    User-Agent       = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    Accept           = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    Accept-Language  = "es-ES,es;q=0.9"
    Connection       = "keep-alive"
    Cache-Control    = "max-age=0"

  [inputs.http_response.tags]
    service = "{measurement_name}"
"""

    def _icmp_cfg(self, target_ip: str, url: str, site: str) -> str:
        """Genera configuración ICMP para una IP específica."""
        measurement_name = sanitize(site)
        parsed_url = urlparse(url)
        hostname = parsed_url.hostname or url

        return f"""# Auto-generado por telegraf_manager – NO EDITAR MANUALMENTE
#
# Configuración de ping ICMP para '{hostname}'
# IP del objetivo: {target_ip}
# URL original: {url}
# Measurement en InfluxDB: {measurement_name}

[[inputs.ping]]
  urls = ["{target_ip}"]
  count = {self.config['ping_count']}
  interval = "{self.config['ping_interval']}"
  name_override = "{measurement_name}"

  [inputs.ping.tags]
    server = "{url}"
    location = "{site}"

[[processors.rename]]
  [[processors.rename.replace]]
    tag  = "url"
    dest = "source"
"""

    def _write_file(self, path: Path, content: str) -> None:
        try:
            path.write_text(content, encoding="utf-8")
            self._fix_perms(path)
            logger.info("Archivo escrito en %s", path)
        except Exception as exc:
            logger.error("Fallo al escribir %s: %s", path, exc)

    def add_target(self):
        """Añade objetivos HTTP/ICMP basados en URLs."""
        sites = self.list_sites()
        site: str | None = None

        print("\n=== SELECCIÓN DE MEASUREMENT/SITIO ===")
        print("El nombre del sitio será usado como 'measurement' en InfluxDB")
        print("(ej: 'Segovia', 'Madrid', 'Albacete', etc.)")

        if not sites:
            logger.info("No se encontraron sitios de monitoreo existentes.")
            site_name = input("\nNombre del measurement/sitio: ").strip()
            if site_name:
                site = self.create_site(site_name)
            if not site:
                logger.error("No se pudo crear el sitio.")
                return
        else:
            print(f"\nSitios/measurements existentes:")
            for i, s in enumerate(sites, 1):
                print(f"  {i}. {s}")
            print(f"  {len(sites)+1}. Crear nuevo measurement/sitio")
            print("  O escribe directamente el nombre del nuevo measurement")

            sel = input("\nElige una opción o escribe el nombre: ").strip()

            if sel.isdigit() and 1 <= int(sel) <= len(sites):
                site = sites[int(sel) - 1]
                print(f"Measurement seleccionado: {site}")
            elif sel.isdigit() and int(sel) == len(sites) + 1:
                site_name = input("Nombre del nuevo measurement/sitio: ").strip()
                site = self.create_site(site_name) if site_name else None
            else:
                # Tratar la entrada como un nombre directo de sitio
                if sel:
                    site = self.create_site(sel)
                    print(f"Creando nuevo measurement: {site}")

            if not site:
                logger.error("No se seleccionó o creó un sitio válido.")
                return

        # Pedir URLs
        print("\nIntroduce las URLs a monitorear (una por línea, línea vacía para terminar):")
        print("Ejemplo: https://example.com")
        urls = []
        while True:
            url = input("URL: ").strip()
            if not url:
                break
            if not is_valid_url(url):
                logger.error("URL inválida: %s", url)
                continue
            urls.append(url)

        if not urls:
            logger.error("No se proporcionaron URLs válidas.")
            return

        print(f"\nURLs a procesar para el measurement '{site}': {len(urls)}")
        for url in urls:
            print(f"  - {url}")

        if not prompt_yes_no(f"¿Proceder con la configuración para el measurement '{site}'?"):
            return

        site_dir = Path(self.tgf_dir, site)

        # Generar configuración HTTP
        http_config_path = site_dir / "http_monitoring.conf"
        if http_config_path.exists() and not prompt_yes_no(f"El archivo HTTP {http_config_path.name} ya existe. ¿Sobrescribir?"):
            logger.info("Saltando configuración HTTP.")
        else:
            self._write_file(http_config_path, self._http_cfg(urls, site))

        # Generar configuraciones ICMP
        icmp_configs_created = []
        for url in urls:
            ip = resolve_domain_to_ip(url)
            if not ip:
                logger.warning(f"No se pudo resolver la IP para {url}, saltando configuración ICMP.")
                continue

            parsed_url = urlparse(url)
            hostname = parsed_url.hostname or url
            safe_hostname = sanitize(hostname)
            icmp_config_name = f"icmp_{safe_hostname}_{ip}.conf"
            icmp_config_path = site_dir / icmp_config_name

            if icmp_config_path.exists():
                logger.info(f"El archivo ICMP {icmp_config_name} ya existe, saltando.")
                continue

            self._write_file(icmp_config_path, self._icmp_cfg(ip, url, site))
            icmp_configs_created.append(icmp_config_name)

        logger.info(f"Configuración completada:")
        logger.info(f"  - HTTP: {http_config_path.name}")
        logger.info(f"  - ICMP: {len(icmp_configs_created)} archivos creados")

    def list_measurements(self):
        """Lista todos los measurements/sitios disponibles con sus archivos."""
        sites = self.list_sites()
        if not sites:
            print("\nNo hay measurements/sitios configurados.")
            return

        print("\n=== MEASUREMENTS/SITIOS CONFIGURADOS ===")
        for site in sites:
            site_dir = Path(self.tgf_dir, site)
            http_files = list(site_dir.glob("http_*.conf"))
            icmp_files = list(site_dir.glob("icmp_*.conf"))

            print(f"\n📊 Measurement: {site}")
            print(f"   📁 Directorio: {site_dir}")
            if http_files:
                print(f"   🌐 HTTP: {len(http_files)} archivo(s)")
                for f in http_files:
                    print(f"       - {f.name}")
            if icmp_files:
                print(f"   📡 ICMP: {len(icmp_files)} archivo(s)")
                for f in icmp_files[:3]:  # Mostrar solo los primeros 3
                    print(f"       - {f.name}")
                if len(icmp_files) > 3:
                    print(f"       ... y {len(icmp_files)-3} más")

            if not http_files and not icmp_files:
                print("   ⚠️  Sin archivos de configuración")
        print()

    def delete_target(self):
        """Elimina configuraciones basadas en URLs."""
        sites = self.list_sites()
        if not sites:
            logger.info("No hay measurements/sitios disponibles.")
            return

        print("\n=== SELECCIÓN DE MEASUREMENT/SITIO ===")
        print("Selecciona el measurement/sitio del cual eliminar configuraciones:")
        for i, s in enumerate(sites, 1):
            print(f"  {i}. {s}")
        sel = input("Elige una opción: ").strip()
        if not sel.isdigit() or not (1 <= int(sel) <= len(sites)):
            logger.error("Selección inválida.")
            return
        site = sites[int(sel) - 1]
        print(f"Measurement seleccionado: {site}")

        site_dir = Path(self.tgf_dir, site)

        # Mostrar archivos disponibles
        http_files = list(site_dir.glob("http_*.conf"))
        icmp_files = list(site_dir.glob("icmp_*.conf"))

        if not http_files and not icmp_files:
            logger.warning(f"No se encontraron archivos de configuración en el sitio {site}")
            return

        print(f"\nArchivos encontrados en {site}:")
        if http_files:
            print("  HTTP:")
            for f in http_files:
                print(f"    - {f.name}")
        if icmp_files:
            print("  ICMP:")
            for f in icmp_files:
                print(f"    - {f.name}")

        print("\nOpciones de eliminación:")
        print("  1. Eliminar todo (HTTP + ICMP)")
        print("  2. Eliminar solo HTTP")
        print("  3. Eliminar solo ICMP")
        print("  4. Eliminar archivo específico")

        choice = input("Elige una opción: ").strip()
        files_to_delete = []

        if choice == "1":
            files_to_delete = http_files + icmp_files
        elif choice == "2":
            files_to_delete = http_files
        elif choice == "3":
            files_to_delete = icmp_files
        elif choice == "4":
            all_files = http_files + icmp_files
            print("\nArchivos disponibles:")
            for i, f in enumerate(all_files, 1):
                print(f"  {i}. {f.name}")
            file_sel = input("Selecciona el archivo a eliminar: ").strip()
            if file_sel.isdigit() and 1 <= int(file_sel) <= len(all_files):
                files_to_delete = [all_files[int(file_sel) - 1]]

        if not files_to_delete:
            logger.warning("No se seleccionaron archivos para eliminar.")
            return

        print("\nArchivos que se eliminarán:")
        for f in files_to_delete:
            print(f"  - {f.name}")

        if not prompt_yes_no("¿Proceder con la eliminación?"):
            return

        for f in files_to_delete:
            try:
                f.unlink()
                logger.info("Archivo eliminado: %s", f.name)
            except Exception as exc:
                logger.error("Fallo al eliminar %s: %s", f.name, exc)

        self._reload_telegraf()

        self._reload_telegraf()

    def _reload_telegraf(self) -> None:
        """Recarga el contenedor de Telegraf."""
        logger.info("Recargando el contenedor de Telegraf...")
        try:
            subprocess.run(["docker", "compose", "restart", "telegraf"], check=True, capture_output=True, text=True)
            logger.info("Telegraf recargado con éxito.")
        except FileNotFoundError:
            logger.error("Comando 'docker' no encontrado. ¿Está instalado y en el PATH?")
        except subprocess.CalledProcessError as exc:
            logger.error("El comando 'docker compose restart' falló: %s", exc.stderr.strip())
        except Exception as exc:
            logger.error("Fallo inesperado al recargar Telegraf: %s", exc)

# ---------------------------------------------------------------------------
# Bucle principal de la CLI
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Gestor de configuración HTTP/ICMP para Telegraf en Docker")
    ap.add_argument("--debug", action="store_true", help="Activar logging detallado (DEBUG)")
    args = ap.parse_args()

    if args.debug:
        logger.setLevel(logging.DEBUG)

    if os.geteuid() != 0:
        logger.warning(
            "Este script necesita privilegios de superusuario (sudo) para "
            "cambiar el propietario de los archivos de configuración al UID del contenedor de Telegraf (999)."
        )

    mgr = TelegrafManager()

    MENU = {
        "1": ("Añadir Objetivo HTTP/ICMP", mgr.add_target),
        "2": ("Eliminar Objetivo HTTP/ICMP", mgr.delete_target),
        "3": ("Listar Measurements/Sitios", mgr.list_measurements),
        "4": ("Salir", None)
    }

    while True:
        print("\n=== GESTOR DE HTTP/ICMP PARA TELEGRAF ===")
        for key, (title, _) in MENU.items():
            print(f"{key}. {title}")
        choice = input("Selecciona una opción: ").strip()

        if choice in MENU and choice != "4":
            try:
                MENU[choice][1]()
            except Exception as e:
                logger.error("Ocurrió un error inesperado durante la operación: %s", e)
        elif choice == "4":
            logger.info("¡Adiós!")
            break
        else:
            print("Opción inválida. Inténtalo de nuevo.")

if __name__ == "__main__":
    main()
