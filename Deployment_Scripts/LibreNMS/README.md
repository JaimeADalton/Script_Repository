# NOC-ISP Stack v4.0.0

Sistema completo de monitorización de red basado en **LibreNMS**, **Oxidized**, **Syslog-ng**, **SNMP Trapd** y **Nginx**.

## 🎯 Características

- **LibreNMS** - Sistema de monitorización de red con autodiscovery
- **MariaDB** - Base de datos optimizada para LibreNMS
- **Redis** - Cache y gestión de colas
- **Dispatcher** - Poller distribuido para escalabilidad
- **Syslog-ng** - Receptor centralizado de logs (puerto 514) - **IPs reales preservadas**
- **SNMP Trapd** - Receptor de traps SNMP (puerto 162) - **IPs reales preservadas**
- **Oxidized** - Backup automático de configuraciones de red
- **Nginx** - Reverse proxy con HTTPS y certificados SSL

## ⚠️ Solución al problema de Source NAT

Esta versión soluciona el problema de **Source NAT de Docker** que enmascara las IPs reales de los dispositivos que envían logs/traps.

**Problema original:**
- Docker por defecto hace SNAT en las conexiones entrantes
- Todos los logs/traps aparecen como si vinieran de `172.20.0.1` (gateway Docker)
- LibreNMS no puede identificar el dispositivo origen real

**Solución implementada:**
- Syslog-ng y SNMPTrapd usan `network_mode: host`
- Los servicios escuchan directamente en la interfaz del host
- Las IPs reales de los dispositivos se preservan

## 🚀 Instalación Rápida

```bash
# 1. Descomprimir
tar -xzvf noc-isp-stack-v4.tar.gz
cd noc-isp-final

# 2. Ejecutar instalación
chmod +x install.sh
./install.sh

# 3. Acceder
# https://<IP-DEL-SERVIDOR>
# Usuario: admin
# Password: Admin123!
```

### Instalación Limpia (borra datos anteriores)

```bash
./install.sh --clean
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

| Puerto | Protocolo | Servicio | Modo |
|--------|-----------|----------|------|
| 80 | TCP | HTTP (redirect) | Bridge |
| 443 | TCP | HTTPS (Web UI) | Bridge |
| 514 | TCP/UDP | Syslog | **Host** |
| 162 | TCP/UDP | SNMP Traps | **Host** |
| 8888 | TCP | Oxidized API | Bridge |

**Nota:** Los puertos 514 y 162 deben estar libres en el host ya que usan `network_mode: host`.

## 📁 Estructura de Archivos

```
noc-isp-final/
├── docker-compose.yml          # Definición de servicios
├── .env                        # Variables (generado automáticamente)
├── librenms.env               # Variables de LibreNMS
├── install.sh                  # Script de instalación
├── configure-oxidized-api.sh   # Configurar Oxidized con API
├── README.md
├── config/
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── ssl/               # Certificados (generados)
│   └── oxidized/
│       ├── config
│       └── router.db
└── data/                       # Datos persistentes
    ├── db/
    ├── redis/
    ├── librenms/
    └── oxidized/
```

## ⚙️ Configuración Post-Instalación

### Configurar dispositivos para enviar Syslog

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

### Configurar SNMP Traps

**Cisco IOS:**
```
snmp-server host <IP-SERVIDOR> version 2c <community>
snmp-server enable traps
```

### Integrar Oxidized con LibreNMS API

```bash
# 1. En LibreNMS: Settings → API → Create Token
# 2. Ejecutar:
./configure-oxidized-api.sh <TOKEN>
```

## 🔧 Comandos Útiles

```bash
# Estado de contenedores
docker compose ps

# Ver logs
docker compose logs -f
docker compose logs -f syslogng
docker compose logs -f dispatcher

# Reiniciar
docker compose restart

# Validar LibreNMS
docker exec -u librenms librenms php /opt/librenms/validate.php

# Añadir dispositivo
docker exec librenms php /opt/librenms/lnms device:add <IP> -c <community> -v 2c

# Ver syslogs recientes
docker exec librenms_db mysql -u librenms -p"..." \
    -e "SELECT * FROM syslog ORDER BY timestamp DESC LIMIT 10;" librenms
```

## 🔍 Troubleshooting

### Los logs aparecen con IP incorrecta

Si los logs aparecen con IP `172.x.x.x`:
1. Verifica que syslogng usa `network_mode: host` en docker-compose.yml
2. Reinicia: `docker compose restart syslogng`
3. Verifica que el puerto 514 está escuchando: `ss -tuln | grep 514`

### LibreNMS no arranca

```bash
docker compose logs librenms
docker compose restart librenms
```

### Oxidized no carga dispositivos

```bash
docker compose logs oxidized
curl http://localhost:8888/nodes
```

## 📄 Licencias

- **LibreNMS**: GPL v3
- **Oxidized**: Apache 2.0
- **Nginx**: BSD-like
- **MariaDB**: GPL v2
- **Redis**: BSD

---

**Versión**: 4.0.0  
**Última actualización**: Diciembre 2024
