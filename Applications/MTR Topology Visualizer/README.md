# Manual de Usuario: MTR Topology Visualizer

## Índice

1. [Introducción](#1-introducción)
2. [Requisitos del Sistema](#2-requisitos-del-sistema)
3. [Instalación](#3-instalación)
4. [Arquitectura de la Aplicación](#4-arquitectura-de-la-aplicación)
5. [Interfaz de Usuario](#5-interfaz-de-usuario)
6. [Gestión de Agentes](#6-gestión-de-agentes)
7. [Visualización de Topología](#7-visualización-de-topología)
8. [Funciones Avanzadas](#8-funciones-avanzadas)
9. [Solución de Problemas](#9-solución-de-problemas)
10. [Referencia Técnica](#10-referencia-técnica)

## 1. Introducción

MTR Topology Visualizer es una aplicación Python avanzada que proporciona una visualización interactiva de la topología de red. Combina las funcionalidades de traceroute y ping (similar a la herramienta MTR) para analizar la conectividad de red, monitorear puntos intermedios (hops) y visualizar gráficamente las rutas de red.

### Características Principales

- **Análisis de red tipo MTR**: Monitorea rutas completas entre origen y destino
- **Visualización gráfica interactiva**: Presenta los datos en un mapa de topología usando D3.js
- **Monitoreo de múltiples destinos**: Capacidad para gestionar hasta 1000 IPs de destino
- **Detección de problemas**: Identifica pérdida de paquetes y latencia elevada
- **Gestión de agentes**: Interfaz para añadir, editar y organizar destinos de monitoreo
- **Descubrimiento automático**: Integración con Telegraf para descubrir agentes

## 2. Requisitos del Sistema

### Hardware Recomendado

- CPU: 2 núcleos o más
- Memoria RAM: Mínimo 2GB (4GB recomendado para >500 agentes)
- Almacenamiento: 500MB para la instalación y base de datos

### Software Requerido

- Sistema Operativo: Linux (probado en Ubuntu/Debian)
- Python 3.6 o superior
- Privilegios de administrador (root) para la instalación y ejecución de ICMP
- Navegador web moderno para la visualización (Chrome, Firefox, Edge)

### Puertos y Permisos

- Puerto 8088 TCP (predeterminado) para la interfaz web
- Permisos para enviar/recibir paquetes ICMP raw (requiere privilegios de root)
- Acceso de red a los destinos a monitorear

## 3. Instalación

### Método Automático (Recomendado)

1. Descargue los archivos del proyecto:
   ```bash
   git clone https://github.com/usuario/mtr-topology.git
   cd mtr-topology
   ```

2. Ejecute el script de instalación:
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

3. Verifique que el servicio esté en ejecución:
   ```bash
   sudo systemctl status mtr-topology
   ```

### Instalación Manual

1. Cree la estructura de directorios:
   ```bash
   sudo mkdir -p /opt/mtr-topology/{core,web,web/static/js,web/static/css,web/templates}
   ```

2. Instale las dependencias necesarias:
   ```bash
   sudo apt-get update
   sudo apt-get install -y python3 python3-pip python3-venv wget
   ```

3. Cree y active un entorno virtual:
   ```bash
   sudo python3 -m venv /opt/mtr-topology/venv
   source /opt/mtr-topology/venv/bin/activate
   ```

4. Instale las dependencias Python:
   ```bash
   pip install flask requests
   ```

5. Descargue D3.js:
   ```bash
   wget -q https://d3js.org/d3.v7.min.js -O /opt/mtr-topology/web/static/js/d3.v7.min.js
   ```

6. Copie los archivos fuente (todos los archivos Python, HTML, CSS y JS) a las ubicaciones correspondientes.

7. Configure el servicio systemd:
   ```bash
   sudo nano /etc/systemd/system/mtr-topology.service
   ```
   Contenido del archivo:
   ```
   [Unit]
   Description=MTR Topology Visualizer
   After=network.target

   [Service]
   ExecStart=/opt/mtr-topology/venv/bin/python3 /opt/mtr-topology/main.py
   Restart=on-failure
   User=root
   Group=root
   WorkingDirectory=/opt/mtr-topology
   StandardOutput=journal
   StandardError=journal

   [Install]
   WantedBy=multi-user.target
   ```

8. Habilite e inicie el servicio:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable mtr-topology
   sudo systemctl start mtr-topology
   ```

## 4. Arquitectura de la Aplicación

MTR Topology Visualizer se compone de los siguientes módulos principales:

### Módulo ICMP (core/icmp.py)
Proporciona funcionalidades para enviar y recibir paquetes ICMP, permitiendo el descubrimiento de rutas y la medición de latencia y pérdida de paquetes.

### Motor MTR (core/mtr.py)
Coordina el análisis de múltiples destinos, recopilando estadísticas sobre cada salto en las rutas y construyendo la topología de red.

### Almacenamiento (core/storage.py)
Gestiona la persistencia de datos, almacenando información sobre agentes y topologías en una base de datos SQLite.

### Aplicación Web (web/app.py)
Implementa la interfaz de usuario basada en Flask, proporcionando endpoints API para acceder a los datos y controlar la aplicación.

### Visualización (web/static/js/topology.js)
Utiliza D3.js para crear una representación gráfica interactiva de la topología de red, con capacidades de zoom, arrastre y filtrado.

## 5. Interfaz de Usuario

### Acceso a la Interfaz Web

Después de la instalación, acceda a la interfaz web a través de un navegador:
```
http://[dirección-ip-servidor]:8088
```

### Elementos Principales

**Cabecera**
- Título de la aplicación
- Selector de Grupo: Filtra la visualización por grupo de agentes
- Selector de Agente: Filtra para mostrar solo un agente específico
- Botón de Actualización: Refresca los datos de topología
- Botón de Gestión: Abre el panel de gestión de agentes

**Área Principal**
- Visualización de la topología: Representación gráfica interactiva de la red
- Leyenda: Explicación de los elementos visuales
- Mensajes de carga/error: Indicadores de estado durante la operación

**Panel de Gestión de Agentes**
- Formulario para añadir nuevos agentes
- Función de descubrimiento desde configuración de Telegraf
- Tabla de agentes configurados

## 6. Gestión de Agentes

Los agentes son los destinos que la aplicación monitorea para construir la topología de red.

### Añadir un Nuevo Agente

1. Haga clic en el botón "Gestionar" en la cabecera
2. En el panel de gestión, complete el formulario "Añadir nuevo agente":
   - Dirección IP: La dirección IP o nombre de host del agente
   - Nombre (opcional): Un nombre descriptivo para el agente
   - Grupo: Una categoría para organizar agentes (ej. "Datacenter", "Oficinas")
3. Haga clic en "Añadir"

### Descubrimiento Automático desde Telegraf

Si utiliza Telegraf para monitorear sus sistemas, puede descubrir automáticamente agentes:

1. En el panel de gestión, ingrese la ruta de configuración de Telegraf (predeterminado: `/etc/telegraf/telegraf.d/`)
2. Haga clic en "Descubrir"
3. La aplicación buscará archivos de configuración que contengan 'icmp' y extraerá las URLs configuradas

### Administrar Agentes Existentes

La tabla de agentes muestra todos los agentes configurados y proporciona las siguientes acciones:

- **Escanear**: Inicia un escaneo inmediato del agente seleccionado
- **Habilitar/Deshabilitar**: Activa o desactiva el monitoreo para el agente
- **Eliminar**: Quita permanentemente el agente de la configuración

### Organización por Grupos

Los grupos permiten organizar agentes según su ubicación, función u otros criterios. Esto facilita:

- Filtrar la visualización para enfocarse en segmentos específicos de la red
- Organizar grandes cantidades de destinos
- Identificar patrones de conectividad específicos de cada grupo

## 7. Visualización de Topología

La visualización de topología es el componente central de la aplicación, proporcionando una representación gráfica interactiva de la red.

### Elementos de la Visualización

- **Nodos**: Representan dispositivos en la red
  - **Origen** (azul): El servidor donde se ejecuta la aplicación
  - **Routers/Hops** (gris): Puntos intermedios en las rutas
  - **Destinos** (verde): Los agentes monitoreados

- **Enlaces**: Conexiones entre dispositivos
  - El color indica el nivel de pérdida de paquetes:
    - Verde: Sin pérdida
    - Amarillo: Pérdida baja (0.1-1%)
    - Naranja: Pérdida moderada (1-5%)
    - Rojo: Pérdida alta (>5%)
  - El grosor representa el número de destinos que utilizan esa conexión

### Interacción con la Visualización

- **Zoom**: Use la rueda del ratón para acercar o alejar
- **Arrastrar**: Haga clic y arrastre para mover la visualización
- **Información detallada**: Pase el cursor sobre nodos o enlaces para ver detalles
- **Resaltado**: Al pasar el cursor sobre un nodo, se resaltan sus conexiones

### Filtrado de la Visualización

Para gestionar grandes topologías, utilice los filtros en la cabecera:

- **Filtro de Grupo**: Muestra solo agentes de un grupo específico
- **Filtro de Agente**: Enfoca la visualización en un único agente y su ruta

## 8. Funciones Avanzadas

### Personalización del Intervalo de Escaneo

Para modificar cada cuánto tiempo se actualiza la topología:

```bash
sudo systemctl stop mtr-topology
sudo /opt/mtr-topology/venv/bin/python3 /opt/mtr-topology/main.py --scan-interval 600
```

Este ejemplo configura un intervalo de 10 minutos (600 segundos) entre escaneos.

### Configuración de Parámetros MTR

Los parámetros del motor MTR se pueden ajustar en el archivo `web/app.py`:

```python
# Inicializar gestor MTR
mtr_options = {
    'timeout': 1.0,          # Tiempo de espera para cada paquete (segundos)
    'interval': 0.1,         # Intervalo entre paquetes (segundos)
    'hop_sleep': 0.05,       # Pausa entre saltos (segundos)
    'max_hops': 30,          # Número máximo de saltos a sondear
    'max_unknown_hops': 3,   # Saltos desconocidos permitidos antes de terminar
    'ring_buffer_size': 5,   # Número de paquetes para estadísticas
    'ptr_lookup': False      # Resolución DNS inversa (puede ralentizar el escaneo)
}
```

### Integración con Sistemas de Monitoreo

La aplicación puede complementar otras herramientas como:

- **Telegraf**: Puede importar objetivos ICMP de configuraciones existentes
- **Grafana**: Los datos de latencia y pérdida se pueden exportar para visualización avanzada
- **Alertas**: Puede configurar alertas basadas en umbrales de pérdida o latencia

## 9. Solución de Problemas

### Problemas Comunes y Soluciones

| Problema | Posible Causa | Solución |
|----------|---------------|----------|
| La aplicación no inicia | Permisos insuficientes | Verifique que se ejecuta como root (`sudo`) |
| No se ven datos en la interfaz | Firewall bloqueando ICMP | Configure el firewall para permitir ICMP (entrada/salida) |
| Mensaje "Error en MTR" | Resolución de nombres fallida | Verifique DNS y/o use direcciones IP directamente |
| Visualización lenta con muchos agentes | Sobrecarga de recursos | Aumente el `scan_interval` o reduzca el número de agentes |
| Agentes aparecen pero sin datos | Tiempo de espera demasiado corto | Aumente el valor de `timeout` en las opciones del MTR |

### Consulta de Logs

Para revisar los logs de la aplicación:
```bash
sudo journalctl -u mtr-topology -f
```

Para obtener mensajes de debug más detallados:
```bash
sudo systemctl stop mtr-topology
sudo /opt/mtr-topology/venv/bin/python3 /opt/mtr-topology/main.py --debug
```

### Reinicio de la Aplicación

Para reiniciar la aplicación después de cambios:
```bash
sudo systemctl restart mtr-topology
```

Para reiniciar la base de datos (borra todos los datos y agentes):
```bash
sudo systemctl stop mtr-topology
sudo rm /opt/mtr-topology/mtr_data.db
sudo systemctl start mtr-topology
```

## 10. Referencia Técnica

### Estructura de Directorios

```
/opt/mtr-topology/
├── core/                  # Componentes principales
│   ├── __init__.py
│   ├── icmp.py            # Funcionalidad ICMP
│   ├── mtr.py             # Motor MTR
│   └── storage.py         # Gestión de datos
├── web/                   # Interfaz web
│   ├── __init__.py
│   ├── app.py             # Aplicación Flask
│   ├── static/            # Archivos estáticos
│   │   ├── js/
│   │   │   ├── d3.v7.min.js
│   │   │   └── topology.js
│   │   └── css/
│   │       └── style.css
│   └── templates/         # Plantillas HTML
│       └── index.html
├── config.py              # Configuración global
├── main.py                # Punto de entrada
├── mtr_data.db            # Base de datos SQLite
├── mtr_topology.log       # Archivo de logs
└── venv/                  # Entorno virtual Python
```

### API REST

La aplicación expone los siguientes endpoints API:

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/topology` | GET | Obtiene datos de topología actual, opcionalmente filtrados |
| `/api/agents` | GET | Lista todos los agentes configurados |
| `/api/agent` | POST | Añade un nuevo agente |
| `/api/agent/<address>` | POST | Actualiza un agente existente (habilitar/deshabilitar/eliminar) |
| `/api/scan/<address>` | GET | Inicia un escaneo inmediato para un agente específico |
| `/api/discover-telegraf` | GET | Descubre agentes desde configuraciones de Telegraf |

### Modificaciones Personalizadas

Para personalizar el comportamiento de la aplicación, puede modificar:

- **Colores y estilos**: Edite `web/static/css/style.css`
- **Comportamiento de visualización**: Modifique `web/static/js/topology.js`
- **Lógica de servidor**: Actualice `web/app.py`
- **Parámetros de escaneo**: Ajuste las opciones en `core/mtr.py`

### Consideraciones de Rendimiento

Para redes grandes (>500 agentes):

1. **Aumente el intervalo de escaneo**: Use `--scan-interval 600` o más para reducir la carga
2. **Ajuste el procesamiento por lotes**: Modifique `chunk_size` en `scan_loop()` para controlar cuántos agentes se procesan simultáneamente
3. **Limite la profundidad de análisis**: Reduzca `max_hops` para escaneos más rápidos
4. **Filtrado activo**: Use los filtros de grupo/agente para visualizar secciones específicas de la red

---

© 2025 MTR Topology Visualizer - Desarrollado con Python y D3.js
