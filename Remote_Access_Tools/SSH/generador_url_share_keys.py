#!/usr/bin/env python3
import http.server
import socketserver
import threading
import secrets
import os
import sys

# Configuración
PORT = 80  # Nota: Para usar el puerto 80 probablemente necesites privilegios de root.
EXPIRY_SECONDS = 3600  # Duración en segundos (ej. 1 hora)

# Genera un token aleatorio
TOKEN = secrets.token_urlsafe(16)

# Directorio temporal basado en el token
SERVE_DIR = f"/tmp/{TOKEN}"
os.makedirs(SERVE_DIR, exist_ok=True)

# Crear un archivo index.html básico en el directorio
with open(os.path.join(SERVE_DIR, "index.html"), "w") as f:
    f.write(f"""<!DOCTYPE html>
<html>
<head>
    <title>Servidor Temporal</title>
</head>
<body>
    <h1>Servidor Temporal</h1>
    <p>Este es el contenido del directorio temporal: {SERVE_DIR}</p>
    <p>Token de acceso: {TOKEN}</p>
    <p>El servidor estará activo durante {EXPIRY_SECONDS} segundos.</p>
</body>
</html>""")

class TokenHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        """
        Redirige la raíz al directorio con token y maneja las demás solicitudes.
        """
        # Si el usuario accede a la raíz, redirigir a la URL con token
        if self.path == '/':
            self.send_response(302)  # Redirección temporal
            self.send_header('Location', f'/{TOKEN}/')
            self.end_headers()
            return
            
        # Para otras rutas, usar el comportamiento normal
        super().do_GET()
    
    def translate_path(self, path):
        """
        Traduce el path de la URL a una ruta en el sistema de archivos.
        Solo permite servir contenido si el path comienza con el token.
        """
        # Verifica que el path comience con /<TOKEN>
        if not path.startswith('/' + TOKEN):
            # En este caso, devolvemos una ruta que no existe
            # para que SimpleHTTPRequestHandler genere un 404
            return "/path/that/does/not/exist"
        
        # Extrae el path relativo (después del token)
        relative_path = path[len(TOKEN) + 1:]
        
        # Si el path está vacío después de quitar el token, servimos el directorio raíz
        if not relative_path:
            relative_path = '/'
        
        # Construye la ruta completa en el directorio SERVE_DIR
        result = os.path.join(SERVE_DIR, relative_path.lstrip('/'))
        return result
    
    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" %
                         (self.client_address[0],
                          self.log_date_time_string(),
                          format % args))

# Configuración del manejador para servir archivos
Handler = TokenHTTPRequestHandler
# Aseguramos que el manejador muestre el listado de directorios
Handler.directory = SERVE_DIR

# Permitir la reutilización inmediata del puerto
socketserver.TCPServer.allow_reuse_address = True

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Servidor iniciado en http://localhost/{TOKEN}/")
    print(f"Sirviendo contenido desde: {SERVE_DIR}")
    print(f"El servidor estará activo durante {EXPIRY_SECONDS} segundos.")
    
    # Configura un temporizador para detener el servidor tras EXPIRY_SECONDS
    def shutdown_server():
        print("Tiempo expirado. Apagando el servidor.")
        httpd.shutdown()
    
    timer = threading.Timer(EXPIRY_SECONDS, shutdown_server)
    timer.start()
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("Interrupción manual.")
    finally:
        timer.cancel()
