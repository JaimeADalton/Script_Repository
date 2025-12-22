# NOC-ISP Stack

Sistema completo de monitorización de red basado en **LibreNMS**, **Oxidized**, **Syslog-ng**, **SNMP Trapd** y **Nginx**.

## 🎯 Características

- **LibreNMS** - Sistema de monitorización de red con autodiscovery
- **MariaDB** - Base de datos optimizada para LibreNMS
- **Redis** - Cache y gestión de colas
- **Dispatcher** - Poller distribuido para escalabilidad
- **Syslog-ng** - Receptor centralizado de logs (puerto 514)
- **SNMP Trapd** - Receptor de traps SNMP (puerto 162)
- **Oxidized** - Backup automático de configuraciones de red
- **Nginx** - Reverse proxy con HTTPS y certificados SSL

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET / LAN                                  │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
              ┌─────────┐    ┌─────────┐    ┌─────────┐
              │  :443   │    │  :514   │    │  :162   │
              │  Nginx  │    │ Syslog  │    │  SNMP   │
              │ (HTTPS) │    │   -ng   │    │ Trapd   │
              └────┬────┘    └────┬────┘    └────┬────┘
                   │              │              │
                   └──────────────┼──────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          noc-internal (172.20.0.0/24)                        │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         LibreNMS (Web)                               │   │
│   │                          :8000 interno                               │   │
│   └───────────────────────────────┬─────────────────────────────────────┘   │
│                                   │                                          │
│          ┌────────────────────────┼────────────────────────┐                │
│          │                        │                        │                │
│          ▼                        ▼                        ▼                │
│   ┌────────────┐          ┌────────────┐          ┌────────────┐           │
│   │  MariaDB   │          │   Redis    │          │ Dispatcher │           │
│   │   :3306    │          │   :6379    │          │  (Poller)  │           │
│   └────────────┘          └────────────┘          └────────────┘           │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     Oxidized :8888                                   │   │
│   │              (Network Configuration Backup)                          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 📋 Requisitos

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| **Sistema Operativo** | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| **Docker** | 24.0+ | Última versión |
| **Docker Compose** | v2.20+ | Última versión |
| **RAM** | 4 GB | 8 GB+ |
| **Disco** | 20 GB | 100 GB+ SSD |
| **CPU** | 2 cores | 4+ cores |

### Puertos Requeridos

| Puerto | Protocolo | Servicio |
|--------|-----------|----------|
| 80 | TCP | HTTP (redirect a HTTPS) |
| 443 | TCP | HTTPS (Web UI) |
| 514 | TCP/UDP | Syslog |
| 162 | TCP/UDP | SNMP Traps |
| 8888 | TCP | Oxidized API |

## 🚀 Instalación Rápida

```bash
# 1. Clonar o copiar los archivos del proyecto
git clone <repo> noc-isp
cd noc-isp

# 2. Ejecutar instalación
chmod +x install.sh
./install.sh

# 3. Acceder a la web
# https://<IP-DEL-SERVIDOR>
# Usuario: admin
# Password: Admin123!
```

## 📁 Estructura de Archivos

```
noc-isp/
├── docker-compose.yml          # Definición de servicios
├── .env                        # Variables principales (generado automáticamente)
├── librenms.env               # Variables específicas de LibreNMS
├── install.sh                  # Script de instalación automática
├── configure-oxidized-api.sh   # Script para integrar Oxidized con API
├── README.md                   # Este archivo
│
├── config/                     # Configuraciones
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── ssl/
│   │       ├── cert.pem       # Generado automáticamente
│   │       └── key.pem        # Generado automáticamente
│   └── oxidized/
│       ├── config             # Plantilla de configuración
│       └── router.db          # Plantilla de dispositivos
│
└── data/                       # Datos persistentes (volúmenes)
    ├── db/                     # MariaDB
    ├── redis/                  # Redis
    ├── librenms/              # LibreNMS (RRDs, logs, etc.)
    └── oxidized/              # Oxidized (configuración activa + backups)
        ├── config             # Configuración activa
        ├── router.db          # Lista de dispositivos
        ├── configs/           # Backups de configuraciones
        └── crashes/           # Logs de errores
```

## ⚙️ Configuración Post-Instalación

### 1. Cambiar Contraseña de Admin

1. Accede a `https://<IP>/`
2. Ve a **Settings** → **Manage Users** → **admin**
3. Cambia la contraseña

### 2. Añadir Dispositivos

**Via Web:**
1. Ve a **Devices** → **Add Device**
2. Introduce hostname/IP
3. Configura SNMP (v2c o v3)

**Via CLI:**
```bash
docker exec librenms php /opt/librenms/lnms device:add <IP> -c <community> -v 2c
```

### 3. Configurar Integración con Oxidized

```bash
# 1. En LibreNMS web:
#    Settings → API → API Settings → Create API access token
#    Copia el token generado

# 2. Ejecutar script de configuración
./configure-oxidized-api.sh <TU_TOKEN_API>

# 3. En LibreNMS web:
#    Settings → External → Oxidized Integration
#    - Enable Oxidized support: ✓
#    - Oxidized URL: http://librenms_oxidized:8888
```

### 4. Configurar Syslog en Dispositivos

**Cisco IOS:**
```
logging host <IP-SERVIDOR> transport udp port 514
logging trap informational
```

**MikroTik:**
```
/system logging action set remote=<IP-SERVIDOR> remote-port=514
/system logging add action=remote topics=info,warning,error
```

**Linux:**
```bash
# En /etc/rsyslog.conf añadir:
*.* @<IP-SERVIDOR>:514
```

### 5. Configurar SNMP Traps

**Cisco IOS:**
```
snmp-server host <IP-SERVIDOR> version 2c <community>
snmp-server enable traps
```

## 🔧 Comandos Útiles

```bash
cd /ruta/noc-isp

# Estado de contenedores
docker compose ps

# Ver logs en tiempo real
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f librenms
docker compose logs -f oxidized

# Reiniciar un servicio
docker compose restart librenms

# Reiniciar todo
docker compose restart

# Detener todo
docker compose down

# Actualizar imágenes
docker compose pull
docker compose up -d

# Validar LibreNMS
docker exec -u librenms librenms php /opt/librenms/validate.php

# Ejecutar polling manual
docker exec librenms php /opt/librenms/lnms device:poll <hostname>

# Añadir dispositivo
docker exec librenms php /opt/librenms/lnms device:add <IP> -c <community> -v 2c

# Ver syslogs recientes
docker exec librenms_db mysql -u librenms -p"$(grep DB_PASSWORD .env | cut -d= -f2)" \
    -e "SELECT * FROM syslog ORDER BY timestamp DESC LIMIT 10;" librenms

# Probar envío de syslog
logger -n <IP-SERVIDOR> -P 514 -t TEST "Mensaje de prueba"
```

## 🔍 Troubleshooting

### LibreNMS no arranca

```bash
# Ver logs detallados
docker compose logs librenms

# Verificar DB
docker compose exec db mysqladmin ping -u librenms -p

# Reiniciar
docker compose restart librenms
```

### Oxidized no carga dispositivos

```bash
# Ver logs
docker compose logs oxidized

# Verificar API
curl http://localhost:8888/nodes

# Verificar configuración
cat data/oxidized/config

# Reiniciar
docker compose restart oxidized
```

### No recibo syslogs

```bash
# Verificar que está escuchando
docker exec librenms_syslogng ss -tuln | grep 514

# Verificar configuración
docker exec librenms php /opt/librenms/lnms config:get enable_syslog

# Probar envío
logger -n <IP-SERVIDOR> -P 514 -t TEST "Prueba"

# Ver mensajes en DB
docker exec librenms_db mysql -u librenms -p"..." \
    -e "SELECT COUNT(*) FROM syslog;" librenms
```

### Gráficos no se actualizan

```bash
# Verificar dispatcher
docker compose logs dispatcher

# Forzar polling
docker exec librenms php /opt/librenms/lnms device:poll <hostname>
```

### Certificado SSL no válido

Para producción, reemplaza los certificados autofirmados:

```bash
# Usando Let's Encrypt
certbot certonly --standalone -d tu-dominio.com

# Copiar certificados
cp /etc/letsencrypt/live/tu-dominio.com/fullchain.pem config/nginx/ssl/cert.pem
cp /etc/letsencrypt/live/tu-dominio.com/privkey.pem config/nginx/ssl/key.pem

docker compose restart nginx
```

## 💾 Backups

### Backup Manual

```bash
# Backup de datos
tar -czvf backup-noc-$(date +%Y%m%d).tar.gz data/

# Backup solo de base de datos
docker exec librenms_db mysqldump -u librenms -p"..." librenms > backup-db-$(date +%Y%m%d).sql
```

### Restauración

```bash
# Detener
docker compose down

# Restaurar datos
tar -xzvf backup-noc-YYYYMMDD.tar.gz

# Iniciar
docker compose up -d
```

## 📈 Escalabilidad

### Añadir más Dispatchers

Para entornos grandes (>500 dispositivos), añade dispatchers adicionales:

```yaml
# En docker-compose.yml añadir:
  dispatcher2:
    image: librenms/librenms:24.11.0
    container_name: librenms_dispatcher2
    # ... (copiar configuración de dispatcher)
    environment:
      - DISPATCHER_NODE_ID=dispatcher-node-02
      - SIDECAR_DISPATCHER=1
```

## 🔒 Seguridad para Producción

1. **Cambiar TODAS las contraseñas** en `.env`
2. **Usar SNMPv3** en lugar de v2c
3. **Certificados SSL válidos** de Let's Encrypt o CA
4. **Firewall** para limitar acceso a puertos
5. **Backups automatizados** y almacenamiento offsite
6. **Actualizar regularmente** las imágenes Docker

## 📄 Licencias

Este proyecto utiliza software open source:
- **LibreNMS**: GPL v3
- **Oxidized**: Apache 2.0
- **Nginx**: BSD-like
- **MariaDB**: GPL v2
- **Redis**: BSD

## 🆘 Soporte

- **LibreNMS Docs**: https://docs.librenms.org/
- **Oxidized Docs**: https://github.com/ytti/oxidized
- **Docker Docs**: https://docs.docker.com/

---

**Versión**: 3.1.0  
**Última actualización**: Diciembre 2024
