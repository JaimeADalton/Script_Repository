#!/usr/bin/env python3
import http.server
import socketserver
import threading
import secrets
import os
import sys
import time
import shutil
import html
from urllib.parse import urlparse, parse_qs

# --- Configuración ---
PORT = 8080 # Usar un puerto > 1024 para no necesitar root inicialmente
TOKEN_EXPIRY_SECONDS = 90 * 60 # 90 minutos
BASE_TEMP_DIR = "/tmp/secure_ssh_download" # Directorio base seguro
SERVER_ADDRESS = "0.0.0.0" # Escuchar en todas las interfaces

# --- Estado Global (Protegido por Lock) ---
# Diccionario para almacenar información de tokens activos
# Formato: { "token": { "username": "...", "temp_dir": "...", "expiry_time": ..., "used": False, "files": ["file1.key", "file2.ppk"] } }
TOKENS_DATA = {}
TOKENS_LOCK = threading.Lock()

# --- Funciones Auxiliares ---

def log_message(level, message):
    """Función de logging simple a stderr."""
    sys.stderr.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [{level}] {message}\n")
    sys.stderr.flush()

def generate_token_string(length=32):
    """Genera un token URL-safe aleatorio y seguro."""
    return secrets.token_urlsafe(length)

def cleanup_token_data(token):
    """Elimina los datos y el directorio temporal de un token."""
    with TOKENS_LOCK:
        token_info = TOKENS_DATA.pop(token, None) # Elimina de forma segura

    if token_info:
        log_message("INFO", f"Limpiando datos para el token {token} (Usuario: {token_info['username']})")
        temp_dir_to_remove = token_info['temp_dir']
        # Eliminar el directorio temporal de forma segura fuera del lock
        try:
            if os.path.isdir(temp_dir_to_remove):
                shutil.rmtree(temp_dir_to_remove)
                log_message("DEBUG", f"Directorio temporal eliminado: {temp_dir_to_remove}")
        except OSError as e:
            log_message("ERROR", f"No se pudo eliminar el directorio temporal {temp_dir_to_remove}: {e}")
    else:
        log_message("DEBUG", f"Intento de limpiar token {token} que ya no existe.")

def periodic_cleanup():
    """Hilo que se ejecuta periódicamente para limpiar tokens expirados."""
    while True:
        time.sleep(60) # Comprobar cada minuto
        now = time.time()
        tokens_to_cleanup = []

        with TOKENS_LOCK:
            # Iterar sobre una copia de las claves para poder modificar el diccionario
            for token, info in list(TOKENS_DATA.items()):
                # Limpiar si ha expirado O si ha sido usado (con un pequeño margen por si acaso)
                # Ajustamos la lógica: limpiar si expira. La marca 'used' invalida el acceso futuro.
                if now > info['expiry_time']:
                    log_message("INFO", f"Token {token} expirado.")
                    tokens_to_cleanup.append(token)
                elif info.get('cleanup_scheduled', False) and now > info.get('cleanup_at', 0):
                     log_message("INFO", f"Token {token} usado y tiempo de gracia para descarga finalizado.")
                     tokens_to_cleanup.append(token)


        # Limpiar fuera del lock principal para evitar bloqueos largos
        for token in tokens_to_cleanup:
            cleanup_token_data(token)

def add_user_download(username, key_file_path, ppk_file_path):
    """
    Esta es la función que el script de gestión de usuarios llamaría.
    Crea un token, copia los archivos a una ubicación temporal segura,
    y registra el token en el servidor.
    Devuelve la URL de descarga única.
    """
    if not os.path.exists(key_file_path):
        log_message("ERROR", f"Archivo .key no encontrado: {key_file_path}")
        return None
    if not os.path.exists(ppk_file_path):
        log_message("ERROR", f"Archivo .ppk no encontrado: {ppk_file_path}")
        return None

    token = generate_token_string()
    token_temp_dir = os.path.join(BASE_TEMP_DIR, token)

    try:
        os.makedirs(token_temp_dir, exist_ok=True)
        log_message("DEBUG", f"Directorio temporal creado para token {token}: {token_temp_dir}")

        # Copiar archivos al directorio temporal
        dest_key_file = os.path.join(token_temp_dir, os.path.basename(key_file_path))
        dest_ppk_file = os.path.join(token_temp_dir, os.path.basename(ppk_file_path))
        shutil.copy2(key_file_path, dest_key_file) # copy2 preserva metadatos como permisos
        shutil.copy2(ppk_file_path, dest_ppk_file)
        log_message("DEBUG", f"Archivos copiados a {token_temp_dir}")

        # Asegurar permisos (aunque copy2 debería ayudar)
        os.chmod(token_temp_dir, 0o700) # Solo el propietario (el servidor)
        os.chmod(dest_key_file, 0o600)
        os.chmod(dest_ppk_file, 0o600)

    except Exception as e:
        log_message("ERROR", f"Fallo al preparar directorio/archivos para token {token}: {e}")
        # Limpiar si algo falló durante la creación
        if os.path.isdir(token_temp_dir):
            shutil.rmtree(token_temp_dir, ignore_errors=True)
        return None

    expiry_time = time.time() + TOKEN_EXPIRY_SECONDS
    token_info = {
        "username": username,
        "temp_dir": token_temp_dir,
        "expiry_time": expiry_time,
        "used": False,
        "files": [os.path.basename(dest_key_file), os.path.basename(dest_ppk_file)],
        "cleanup_scheduled": False, # Marcar para limpieza después de primer uso
        "cleanup_at": 0 # Hora programada para la limpieza post-uso
    }

    with TOKENS_LOCK:
        TOKENS_DATA[token] = token_info

    # Construir la URL (asumiendo que el servidor es accesible en localhost:PORT)
    # En un escenario real, necesitarías la IP/hostname público/accesible.
    download_url = f"http://{socketserver.TCPServer.server_address[0]}:{PORT}/{token}/"
    # Nota: Si escuchas en 0.0.0.0, server_address[0] puede ser '0.0.0.0'.
    # Quizás necesites obtener la IP real de otra manera o configurarla.
    # Para pruebas locales, localhost suele funcionar. Asumimos localhost por simplicidad.
    local_download_url = f"http://localhost:{PORT}/{token}/"


    log_message("INFO", f"Token generado para usuario '{username}'. URL: {local_download_url}")
    return local_download_url

# --- Manejador HTTP Personalizado ---

class SecureDownloadHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):

    # Sobrescribir para cambiar el formato del log o desactivarlo
    def log_message(self, format, *args):
        log_message("ACCESS", f"{self.client_address[0]} - {format % args}")

    def do_GET(self):
        """Maneja solicitudes GET para la página de índice y descarga de archivos."""
        parsed_path = urlparse(self.path)
        path_components = [comp for comp in parsed_path.path.split('/') if comp] # Elimina vacíos

        if not path_components:
            # Acceso a la raíz del servidor - Podríamos mostrar un mensaje genérico o un 404
            self.send_error(404, "Not Found - Access via token URL")
            return

        token = path_components[0]
        filename = path_components[1] if len(path_components) > 1 else None

        token_info = None
        is_valid = False
        is_expired = False
        is_used = False
        temp_dir = None
        files_list = []

        with TOKENS_LOCK:
            if token in TOKENS_DATA:
                token_info = TOKENS_DATA[token]
                temp_dir = token_info['temp_dir']
                files_list = token_info['files']
                now = time.time()
                is_expired = now > token_info['expiry_time']
                is_used = token_info['used']

                if not is_expired and not is_used:
                    is_valid = True
                elif not is_expired and is_used and filename:
                    # Permitir descarga de archivos si el token fue usado recientemente
                    # pero sólo si la limpieza no ha ocurrido aún.
                    if not token_info.get('cleanup_scheduled', False) or now < token_info.get('cleanup_at', 0):
                         is_valid = True # Permitir descarga de archivos individuales temporalmente

                # Si es la primera vez que se accede al índice y es válido
                if is_valid and not filename and not is_used:
                    log_message("INFO", f"Primer acceso válido al índice para token {token}. Marcando como usado.")
                    token_info['used'] = True
                    # Programar limpieza para un poco más tarde para dar tiempo a descargar
                    token_info['cleanup_scheduled'] = True
                    token_info['cleanup_at'] = time.time() + 120 # 2 minutos de gracia para descargar

            # Fin del bloque with LOCK - token_info puede ser None si el token no existe

        if is_expired:
            log_message("WARN", f"Acceso denegado a token expirado: {token}")
            self.send_error(410, "Gone - Link has expired")
            # Asegurar que se limpie si el periodic cleanup aún no lo hizo
            if token in TOKENS_DATA: # Verificar si aún existe (puede haber race condition con cleanup)
                 cleanup_token_data(token)
            return

        if not token_info:
             log_message("WARN", f"Acceso denegado a token inválido o ya limpiado: {token}")
             self.send_error(404, "Not Found - Invalid or expired link")
             return

        if is_used and not filename:
            log_message("WARN", f"Acceso denegado a índice de token ya usado: {token}")
            self.send_error(410, "Gone - Link has already been used")
            return

        # --- Manejar solicitud ---

        if filename:
            # Solicitud de descarga de archivo específico
            if not is_valid: # Re-verificar validez aquí, especialmente para 'used'
                 log_message("WARN", f"Acceso denegado a archivo {filename} para token {token} (inválido/usado/expirado)")
                 self.send_error(404, "Not Found or Link Expired/Used")
                 return

            if filename not in files_list:
                log_message("WARN", f"Intento de acceso a archivo no listado '{filename}' para token {token}")
                self.send_error(404, "Not Found - File not available")
                return

            # Construir ruta completa segura
            file_path = os.path.abspath(os.path.join(temp_dir, filename))

            # Doble verificación de seguridad: ¿Está realmente dentro del directorio esperado?
            if not file_path.startswith(os.path.abspath(temp_dir) + os.sep):
                 log_message("ERROR", f"¡Intento de Path Traversal detectado! Token: {token}, Path: {filename}")
                 self.send_error(403, "Forbidden")
                 return

            if not os.path.isfile(file_path):
                log_message("ERROR", f"Archivo {file_path} no encontrado en disco aunque listado para token {token}")
                self.send_error(404, "Not Found - File missing")
                return

            # Servir el archivo usando la funcionalidad base pero sobre la ruta calculada
            # Necesitamos 'engañar' al SimpleHTTPRequestHandler para que use nuestro path
            # Guardamos el path original y lo restauramos después
            original_path = self.path
            # El path relativo que SimpleHTTPRequestHandler espera debe ser solo el nombre del archivo
            self.path = "/" + filename
            # Establecemos el directorio actual temporalmente al directorio del token
            # ¡PELIGROSO CONCURRENCIA! SimpleHTTPRequestHandler usa os.getcwd()
            # Necesitamos servir el archivo manualmente para seguridad en concurrencia.

            try:
                with open(file_path, 'rb') as f:
                    fs = os.fstat(f.fileno())
                    file_size = fs[6]
                    self.send_response(200)
                    self.send_header("Content-type", "application/octet-stream")
                    self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
                    self.send_header("Content-Length", str(file_size))
                    self.end_headers()
                    shutil.copyfileobj(f, self.wfile)
                    log_message("INFO", f"Archivo {filename} descargado para token {token}")

            except FileNotFoundError:
                 log_message("ERROR", f"FileNotFound justo antes de abrir {file_path}")
                 self.send_error(404, "Not Found - File missing")
            except Exception as e:
                 log_message("ERROR", f"Error sirviendo archivo {file_path}: {e}")
                 # No enviar error si los headers ya fueron enviados
                 if not self.headers_sent:
                     self.send_error(500, "Internal Server Error")

        else:
            # Solicitud de la página de índice (primer acceso válido)
            if not is_valid: # Debería haber sido capturado antes, pero por si acaso
                 log_message("ERROR", f"Lógica inválida: Acceso a índice para token {token} no válido.")
                 self.send_error(404, "Not Found or Invalid State")
                 return

            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()

            # Generar HTML simple
            html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>Descarga Segura de Claves</title>
    <meta charset="utf-8">
    <style>
        body {{ font-family: sans-serif; margin: 2em; }}
        .warning {{ color: red; font-weight: bold; border: 1px solid red; padding: 1em; margin-top: 1em; }}
        ul {{ list-style: none; padding: 0; }}
        li {{ margin-bottom: 0.5em; }}
        a {{ text-decoration: none; color: blue; }}
        a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <h1>Descarga Segura de Claves SSH</h1>
    <p>Usuario: <strong>{html.escape(token_info['username'])}</strong></p>
    <p>Estos enlaces son de <strong>un solo uso</strong> y expirarán pronto. Descargue ambos archivos ahora.</p>
    <ul>
"""
            for f in files_list:
                # El enlace apunta a la misma URL base del token + nombre de archivo
                file_link = f"{token}/{html.escape(f)}"
                html_content += f'        <li><a href="{file_link}" download="{html.escape(f)}">{html.escape(f)}</a></li>\n'

            html_content += f"""    </ul>
    <div class="warning">
        IMPORTANTE: Una vez que cierre esta página o pase un corto periodo de tiempo, este enlace dejará de funcionar permanentemente. Asegúrese de descargar los archivos necesarios AHORA. Si falla la descarga, contacte al administrador para generar un nuevo enlace.
    </div>
</body>
</html>"""
            self.wfile.write(html_content.encode('utf-8'))
            log_message("INFO", f"Página de índice servida para token {token}")


# --- Función Principal ---

def main():
    # Crear directorio base si no existe
    try:
        os.makedirs(BASE_TEMP_DIR, exist_ok=True)
        # Poner permisos estrictos por si acaso
        os.chmod(BASE_TEMP_DIR, 0o700)
        log_message("INFO", f"Directorio base temporal asegurado: {BASE_TEMP_DIR}")
    except OSError as e:
        log_message("ERROR", f"No se pudo crear o asegurar el directorio base {BASE_TEMP_DIR}: {e}")
        sys.exit(1)

    # Iniciar el hilo de limpieza periódica
    cleanup_thread = threading.Thread(target=periodic_cleanup, daemon=True)
    cleanup_thread.start()
    log_message("INFO", "Hilo de limpieza periódica iniciado.")

    # Configurar y arrancar el servidor HTTP
    # Usar ThreadingTCPServer para manejar múltiples solicitudes concurrentemente
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer((SERVER_ADDRESS, PORT), SecureDownloadHTTPRequestHandler)

    log_message("INFO", f"Servidor de descarga segura iniciado en http://{SERVER_ADDRESS}:{PORT}")
    log_message("INFO", f"Los tokens expirarán después de {TOKEN_EXPIRY_SECONDS / 60:.0f} minutos.")
    log_message("INFO", "Esperando conexiones... (Presiona Ctrl+C para detener)")

    # --- SIMULACIÓN: Añadir un usuario de prueba al inicio ---
    # En un uso real, esta parte sería llamada por tu script bash.
    test_user = "usuario_prueba"
    test_home = os.path.join(BASE_TEMP_DIR, test_user + "_home") # Simular home dir
    test_ssh_dir = os.path.join(test_home, ".ssh")
    os.makedirs(test_ssh_dir, exist_ok=True)
    test_key_file = os.path.join(test_ssh_dir, f"{test_user}_srvbastionssh.key")
    test_ppk_file = os.path.join(test_ssh_dir, f"{test_user}_srvbastionssh.ppk")
    try:
        with open(test_key_file, "w") as f: f.write("Contenido fake de la clave privada")
        with open(test_ppk_file, "w") as f: f.write("Contenido fake de la clave ppk")
        os.chmod(test_key_file, 0o600)
        os.chmod(test_ppk_file, 0o600)

        download_url = add_user_download(test_user, test_key_file, test_ppk_file)
        if download_url:
            log_message("INFO", f"URL de prueba generada para {test_user}: {download_url}")
            log_message("INFO", f" (Los archivos de prueba están en {test_ssh_dir} y copiados a su dir temporal)")
        else:
             log_message("ERROR", "Fallo al generar la URL de prueba.")

    except Exception as e:
        log_message("ERROR", f"Fallo al crear archivos de prueba: {e}")
    # --- FIN SIMULACIÓN ---

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        log_message("INFO", "Interrupción manual detectada. Apagando servidor...")
    finally:
        httpd.server_close() # Cierra el socket de escucha
        log_message("INFO", "Servidor detenido.")
        # La limpieza final de directorios ocurrirá si quedan tokens activos
        # Opcionalmente, podrías iterar y limpiar todo aquí, pero el daemon de limpieza debería encargarse eventualmente.
        # Considera limpiar BASE_TEMP_DIR si quieres que esté vacío al reiniciar.

if __name__ == "__main__":
    main()
