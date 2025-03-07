#!/bin/bash

# Iniciar el servicio SSH
service ssh start

# Mensaje de bienvenida
echo "==================================================================="
echo "      TOOLKIT DE CIBERSEGURIDAD Y ANÁLISIS DE SISTEMAS"
echo "==================================================================="
echo "   Acceso SSH: ssh security@<ip_host> -p <puerto_mapeado>"
echo "   Usuario: security"
echo "   Contraseña: security123"
echo "==================================================================="
echo "   Directorios principales:"
echo "   - /home/security/workspace  (directorio de trabajo)"
echo "   - /home/security/tools      (herramientas adicionales)"
echo "   - /home/security/scripts    (scripts útiles)"
echo "   - /home/security/reports    (informes y resultados)"
echo "   - /home/security/data       (datos persistentes)"
echo "==================================================================="

# Mantener el contenedor ejecutándose
tail -f /dev/null
