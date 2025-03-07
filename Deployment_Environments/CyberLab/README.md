# Toolkit de Ciberseguridad y Análisis de Sistemas

Esta es una imagen Docker personalizada con un conjunto completo de herramientas para ciberseguridad, análisis de sistemas, pentesting y laboratorios de prueba en entornos Linux. La imagen está basada en Kali Linux y contiene una amplia gama de herramientas preinstaladas.

## Características Principales

- **Imagen autocontenida**: Todas las herramientas necesarias preinstaladas
- **Persistencia de datos**: Configuración de volúmenes para mantener el trabajo y configuraciones
- **Fácil despliegue**: Mediante Docker Compose
- **Sistema limpio**: Posibilidad de reiniciar el contenedor para volver a un estado limpio
- **Seguridad**: Aislamiento del sistema host
- **Versátil**: Útil para pentesting, análisis forense, seguridad ofensiva y defensiva

## Requisitos Previos

- Docker instalado (versión 19.03 o superior)
- Docker Compose instalado (versión 1.27 o superior)
- Al menos 10GB de espacio libre en disco
- Conexión a Internet para la construcción inicial de la imagen

## Estructura de Directorios

```
.
├── Dockerfile              # Definición de la imagen Docker
├── docker-compose.yml      # Configuración de servicios
├── entrypoint.sh           # Script de inicio del contenedor
├── scripts/                # Scripts útiles
│   ├── setup-tools.sh      # Instalar herramientas adicionales
│   ├── update-system.sh    # Actualizar sistema y herramientas
│   └── backup-data.sh      # Realizar respaldos de datos
├── workspace/              # Directorio de trabajo persistente
├── reports/                # Directorio para informes y resultados
└── data/                   # Datos persistentes y configuraciones
```

## Instalación y Uso

### 1. Clonar o crear estructura de archivos

Crea los archivos necesarios según la estructura anterior. Todos los archivos necesarios están en este repositorio.

### 2. Construir la imagen

```bash
docker-compose build
```

Este proceso puede tardar varios minutos ya que instala muchas herramientas.

### 3. Iniciar el contenedor

```bash
docker-compose up -d
```

### 4. Conectarse al contenedor

Por SSH:
```bash
ssh security@localhost -p 2222
```
Contraseña: `security123`

O mediante acceso directo al contenedor:
```bash
docker exec -it security-toolkit /bin/zsh
```

## Directorios Persistentes

- **/home/security/workspace**: Para proyectos y trabajo diario
- **/home/security/reports**: Para almacenar informes y resultados
- **/home/security/data**: Para datos y configuraciones persistentes
- **/home/security/tools**: Para herramientas adicionales instaladas manualmente

## Herramientas Incluidas

La imagen incluye numerosas herramientas organizadas por categorías:

### Herramientas de Red
- Nmap, Wireshark, tcpdump, Netdiscover, Masscan, etc.

### Análisis Web
- Burp Suite, SQLMap, Nikto, Dirb, Dirbuster, WPScan, etc.

### Explotación
- Metasploit Framework, Responder, SET, etc.

### Fuerza Bruta y Contraseñas
- Hydra, John the Ripper, Hashcat, Crunch, CeWL, etc.

### Análisis Forense
- Volatility, Binwalk, Foremost, ExifTool, Steghide, etc.

### Ingeniería Inversa
- Ghidra, GDB, Radare2, LLDB, etc.

### Utilidades
- Python, Go, Ruby, scripts personalizados, etc.

## Escenarios de Uso

### Pentesting
```bash
# Escaneo de red
sudo nmap -sV -sC -p- 192.168.1.100

# Enumeración web
dirb http://objetivo.com

# Ataque con Metasploit
msfconsole
```

### Análisis Forense
```bash
# Análisis de memoria
volatility -f memoria.dump imageinfo

# Recuperación de archivos
foremost -i imagen.dd
```

### Desarrollo Seguro
```bash
# Análisis estático
python3 ~/tools/bandit/bandit -r proyecto/

# Fuzzeo de aplicaciones
ffuf -w ~/tools/wordlists/paths.txt -u http://objetivo.com/FUZZ
```

## Mantenimiento

### Actualizar Sistema y Herramientas
```bash
/home/security/scripts/update-system.sh
```

### Respaldo de Datos
```bash
/home/security/scripts/backup-data.sh
```

### Reinicio Limpio
Para reiniciar el contenedor a un estado limpio manteniendo los datos:
```bash
docker-compose down
docker-compose up -d
```

Para reiniciar completamente (borrando volúmenes):
```bash
docker-compose down -v
docker-compose up -d
```

## Personalización

Puedes personalizar la imagen añadiendo o modificando herramientas:

1. Edita el Dockerfile para añadir nuevos paquetes
2. Actualiza el script setup-tools.sh para añadir herramientas adicionales
3. Reconstruye la imagen:
   ```bash
   docker-compose build
   ```

## Solución de Problemas

### Error de permisos
Si encuentras errores de permisos en los volúmenes:
```bash
sudo chown -R $USER:$USER workspace reports data
```

### Problemas de red
Para problemas de acceso a la red desde el contenedor:
```bash
# En docker-compose.yml, descomenta:
# network_mode: host
```

## Seguridad

- Cambia la contraseña predeterminada de inmediato
- Limita los puertos expuestos a los necesarios
- No expongas el contenedor directamente a Internet
- Usa este entorno solo para fines legítimos y éticos

## Licencia

Este proyecto se distribuye bajo la licencia MIT.
