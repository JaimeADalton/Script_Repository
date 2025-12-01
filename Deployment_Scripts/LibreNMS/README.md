# NOC-ISP Stack

Sistema completo de monitorización de red para ISP basado en **LibreNMS**, **Oxidized** y **Nginx**.

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           NOC-ISP Stack                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────┐    ┌─────────────┐    ┌──────────────┐                    │
│   │  Nginx  │───▶│  LibreNMS   │───▶│   MariaDB    │                    │
│   │  :443   │    │   (Web)     │    │              │                    │
│   └─────────┘    └──────┬──────┘    └──────────────┘                    │
│                         │                                                │
│         ┌───────────────┼───────────────┐                               │
│         │               │               │                               │
│         ▼               ▼               ▼                               │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐            │
│   │Dispatcher│   │ Syslog-NG│   │SNMPTrapd │   │  Redis  │            │
│   │ (Poller) │   │  :514    │   │  :162    │   │ (Cache) │            │
│   └──────────┘   └──────────┘   └──────────┘   └─────────┘            │
│                                                                          │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                      Oxidized :8888                               │  │
│   │              (Network Configuration Backup)                       │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Requisitos

- **Sistema Operativo**: Ubuntu 22.04/24.04 LTS (o similar)
- **Docker**: 24.0+ con Docker Compose v2
- **RAM**: 4GB mínimo (8GB recomendado para >500 dispositivos)
- **Disco**: 50GB+ (SSD recomendado)
- **Puertos**: 80, 443, 514 (TCP/UDP), 162 (TCP/UDP), 8888

## Instalación Rápida

### Opción 1: Script Todo-en-Uno

```bash
# Descargar y ejecutar
curl -sSL https://raw.githubusercontent.com/tu-repo/noc-isp/main/install.sh | sudo bash

# O con parámetros personalizados
NOC_INSTALL_DIR=/opt/mi-noc NOC_ADMIN_PASSWORD=MiPassword123 sudo -E bash install.sh
```

### Opción 2: Instalación Manual

```bash
# 1. Clonar/Copiar archivos
sudo mkdir -p /opt/noc-isp
cd /opt/noc-isp

# 2. Copiar todos los archivos del proyecto aquí

# 3. Ejecutar despliegue
sudo ./deploy.sh
```

## Acceso

| Servicio | URL/Puerto | Credenciales por defecto |
|----------|------------|-------------------------|
| Web UI | https://IP:443 | admin / Admin123! |
| Syslog | IP:514 (TCP/UDP) | - |
| SNMP Traps | IP:162 (TCP/UDP) | - |
| Oxidized API | http://IP:8888 | - |

## Configuración Post-Instalación

### 1. Cambiar Contraseña Admin

1. Accede a https://tu-servidor
2. Ve a **Settings** > **My Settings**
3. Cambia la contraseña

### 2. Configurar Oxidized (Backup de Configuraciones)

1. En LibreNMS, ve a **Settings** > **API** > **API Settings**
2. Crea un nuevo token API
3. Edita `/opt/noc-isp/oxidized/config`:

```yaml
# Cambiar source de:
source:
  default: csv
  csv:
    file: "/home/oxidized/.config/oxidized/router.db"
    ...

# A:
source:
  default: http
  http:
    url: http://librenms:8000/api/v0/oxidized
    map:
      name: hostname
      model: os
      group: group
    headers:
      X-Auth-Token: 'TU_TOKEN_API_AQUI'
```

4. Reinicia Oxidized:
```bash
cd /opt/noc-isp && docker compose restart oxidized
```

5. En LibreNMS, ve a **Settings** > **External** > **Oxidized**:
   - Enable Oxidized support: ✓
   - URL: `http://librenms_oxidized:8888`

### 3. Añadir Dispositivos

1. Ve a **Devices** > **Add Device**
2. Introduce el hostname/IP
3. Configura SNMP:
   - Community: `public` (por defecto)
   - Version: v2c o v3 según tu red

### 4. Configurar Syslog en Dispositivos

Configura tus routers/switches para enviar syslog a la IP del servidor, puerto 514.

Ejemplo para Cisco IOS:
```
logging host X.X.X.X transport udp port 514
logging trap informational
```

## Estructura de Archivos

```
/opt/noc-isp/
├── .env                    # Variables de entorno (DB password, etc)
├── librenms.env            # Configuración específica de LibreNMS
├── docker-compose.yml      # Definición de servicios
├── deploy.sh               # Script de despliegue
├── install.sh              # Script de instalación completa
├── configure-oxidized.sh   # Script para configurar Oxidized
├── librenms/               # Datos de LibreNMS (RRDs, logs, etc)
├── db/                     # Datos de MariaDB
├── redis/                  # Datos de Redis
├── nginx/
│   ├── nginx.conf          # Configuración del proxy
│   └── ssl/
│       ├── cert.pem        # Certificado SSL
│       └── key.pem         # Clave privada SSL
└── oxidized/
    ├── config              # Configuración de Oxidized
    └── router.db           # Lista de dispositivos (si no usas API)
```

## Comandos Útiles

```bash
cd /opt/noc-isp

# Ver estado de contenedores
docker compose ps

# Ver logs en tiempo real
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f librenms
docker compose logs -f oxidized

# Reiniciar todos los servicios
docker compose restart

# Reiniciar un servicio específico
docker compose restart librenms

# Detener todo
docker compose down

# Iniciar todo
docker compose up -d

# Actualizar imágenes
docker compose pull && docker compose up -d

# Entrar al contenedor de LibreNMS
docker compose exec librenms bash

# Ejecutar comandos de LibreNMS
docker compose exec librenms lnms device:add 192.168.1.1
docker compose exec librenms lnms config:get
```

## Troubleshooting

### LibreNMS no arranca

```bash
# Ver logs detallados
docker compose logs librenms

# Verificar que la DB está healthy
docker compose ps db
docker compose exec db mysqladmin ping -u librenms -p
```

### Oxidized no conecta a LibreNMS

1. Verifica que LibreNMS esté healthy:
```bash
docker compose exec librenms curl -s http://localhost:8000/api/v0 -H "X-Auth-Token: TU_TOKEN"
```

2. Verifica la configuración de Oxidized:
```bash
docker compose exec oxidized cat /home/oxidized/.config/oxidized/config
```

### No recibo logs de syslog

1. Verifica que el contenedor esté escuchando:
```bash
docker compose exec syslogng ss -tuln | grep 514
```

2. Prueba enviar un log manualmente:
```bash
logger -n localhost -P 514 -t TEST "Prueba de log"
```

### Certificado SSL no válido

Para producción, reemplaza los certificados autofirmados:

```bash
# Usando Let's Encrypt (requiere dominio público)
certbot certonly --standalone -d tu-dominio.com

# Copiar certificados
cp /etc/letsencrypt/live/tu-dominio.com/fullchain.pem nginx/ssl/cert.pem
cp /etc/letsencrypt/live/tu-dominio.com/privkey.pem nginx/ssl/key.pem

docker compose restart nginx
```

## Escalabilidad

Para entornos con >1000 dispositivos:

1. **Añadir más dispatchers**:
```yaml
# En docker-compose.yml, añade:
dispatcher2:
  <<: *dispatcher
  container_name: librenms_dispatcher2
  environment:
    ...
    DISPATCHER_NODE_ID: dispatcher-node-02
```

2. **Aumentar recursos de MariaDB**:
```yaml
# En docker-compose.yml:
db:
  ...
  command:
    - "--innodb-buffer-pool-size=2G"
    - "--max-connections=500"
```

3. **Externalizar Redis** para alta disponibilidad.

## Seguridad en Producción

1. **Cambiar todas las contraseñas** en `.env`
2. **Configurar firewall** para limitar acceso
3. **Usar certificados SSL válidos**
4. **Habilitar HSTS** en nginx.conf
5. **Configurar SNMP v3** en lugar de v2c con community "public"
6. **Hacer backups regulares** de `/opt/noc-isp/db` y `/opt/noc-isp/librenms`

## Licencia

Este proyecto utiliza software open source:
- LibreNMS: GPL v3
- Oxidized: Apache 2.0
- Nginx: BSD-like
- MariaDB: GPL v2
- Redis: BSD
