**Guía de iptables: Teoría y Práctica**

**Tabla de Contenidos**

1.  [Introducción a iptables y Netfilter](#1-introducción-a-iptables-y-netfilter)
    *   ¿Qué es un Filtro de Paquetes?
    *   ¿Por qué usar iptables?
    *   iptables vs ipchains/ipfwadm (Breve Historia)
2.  [Arquitectura de Netfilter](#2-arquitectura-de-netfilter)
    *   Hooks de Netfilter (Puntos de Enganche)
    *   Cómo viajan los paquetes a través de Netfilter
3.  [Conceptos Fundamentales de iptables](#3-conceptos-fundamentales-de-iptables)
    *   Tablas (`filter`, `nat`, `mangle`, `raw`, `security`)
    *   Cadenas (Chains)
        *   Cadenas Incorporadas (INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING)
        *   Cadenas Definidas por el Usuario
    *   Reglas (Rules)
    *   Concordancias (Matches)
    *   Objetivos (Targets) y Saltos (Jumps)
    *   Políticas (Policies) por Defecto
4.  [Seguimiento de Conexiones (Connection Tracking)](#4-seguimiento-de-conexiones-connection-tracking)
    *   Introducción al Seguimiento de Conexiones (Stateful Firewall)
    *   Estados de Conexión (`NEW`, `ESTABLISHED`, `RELATED`, `INVALID`, `UNTRACKED`)
    *   Cómo ver las conexiones rastreadas (`/proc/net/nf_conntrack`, `conntrack -L`)
    *   Estados en Conexiones TCP
    *   Estados en Conexiones UDP
    *   Estados en Conexiones ICMP
    *   Conexiones por Defecto (Otros Protocolos)
    *   Conexiones No Rastreadas (Tabla `raw` y `NOTRACK`)
    *   Ayudantes de Seguimiento de Conexiones (Helpers para FTP, IRC, etc.)
5.  [Traducción de Direcciones de Red (NAT)](#5-traducción-de-direcciones-de-red-nat)
    *   ¿Qué es NAT y por qué usarlo?
    *   Tipos de NAT en iptables
        *   SNAT (Source NAT)
        *   DNAT (Destination NAT)
        *   Masquerading (Enmascaramiento)
        *   Redirect
    *   NAT y Seguimiento de Conexiones
    *   Consideraciones sobre NAT (Helpers, Protocolos Complejos)
6.  [El Comando `iptables`: Uso Práctico](#6-el-comando-iptables-uso-práctico)
    *   Sintaxis Básica
    *   Especificación de Tablas (`-t`)
    *   Operaciones sobre Cadenas
        *   Listar reglas (`-L`, `-v`, `-n`, `-x`, `--line-numbers`)
        *   Vaciar cadenas (`-F`)
        *   Poner contadores a cero (`-Z`)
        *   Crear cadenas (`-N`)
        *   Borrar cadenas (`-X`)
        *   Renombrar cadenas (`-E`)
        *   Establecer políticas por defecto (`-P`)
    *   Operaciones sobre Reglas
        *   Añadir reglas (`-A`)
        *   Insertar reglas (`-I`)
        *   Reemplazar reglas (`-R`)
        *   Borrar reglas (`-D`)
    *   Especificaciones de Concordancia (Matches)
        *   Genéricos (`-p`, `-s`, `-d`, `-i`, `-o`, `-f`)
        *   Implícitos (TCP, UDP, ICMP)
            *   TCP: `--sport`, `--dport`, `--tcp-flags`, `--syn`, `--tcp-option`
            *   UDP: `--sport`, `--dport`
            *   ICMP: `--icmp-type`
        *   Explícitos (Carga con `-m`)
            *   `state`: `--state` (NEW, ESTABLISHED, RELATED, INVALID)
            *   `conntrack`: `--ctstate`, `--ctproto`, `--ctorigsrc`, etc.
            *   `limit`: `--limit`, `--limit-burst` (Limitación de tasa)
            *   `multiport`: `--sports`, `--dports`, `--ports` (Múltiples puertos)
            *   `mac`: `--mac-source` (Dirección MAC)
            *   `owner`: `--uid-owner`, `--gid-owner` (Propietario del proceso local)
            *   `comment`: `--comment` (Añadir comentarios a las reglas)
            *   `string`: `--string` (Buscar cadenas en el paquete - ¡con precaución!)
            *   `recent`: `--set`, `--rcheck`, `--update`, `--remove`, `--seconds`, `--hitcount` (Listas dinámicas de IPs)
            *   `time`: `--timestart`, `--timestop`, `--days` (Basado en hora/fecha)
            *   `connmark`: `--mark` (Basado en la marca de la conexión)
            *   `mark`: `--mark` (Basado en la marca del paquete)
            *   `iprange`: `--src-range`, `--dst-range` (Rangos de IP)
            *   `length`: `--length` (Longitud del paquete)
            *   `tcpmss`: `--mss` (Tamaño máximo de segmento TCP)
            *   `tos`: `--tos` (Type of Service)
            *   `dscp`: `--dscp`, `--dscp-class` (Differentiated Services)
            *   `helper`: `--helper` (Basado en el helper de conntrack)
            *   Otros (ah, esp, condition, addrtype, etc.)
    *   Especificaciones de Objetivo (Targets/Jumps)
        *   Terminantes: `ACCEPT`, `DROP`, `REJECT` (`--reject-with`), `RETURN`
        *   Modificadores/Informativos: `LOG` (`--log-prefix`, `--log-level`, etc.), `ULOG`
        *   Modificadores de Paquetes (Tabla `mangle`): `MARK` (`--set-mark`), `CONNMARK` (`--set-mark`, `--save-mark`, `--restore-mark`), `TOS` (`--set-tos`), `DSCP` (`--set-dscp`, `--set-dscp-class`), `TTL` (`--ttl-set`, `--ttl-dec`, `--ttl-inc`), `TCPMSS` (`--set-mss`, `--clamp-mss-to-pmtu`)
        *   NAT (Tabla `nat`): `SNAT` (`--to-source`), `DNAT` (`--to-destination`), `MASQUERADE` (`--to-ports`), `REDIRECT` (`--to-ports`)
        *   Otros: `QUEUE` / `NFQUEUE` (A espacio de usuario), `CLASSIFY`, `SECMARK`, `CONNSECMARK`, `NOTRACK` (Tabla `raw`)
        *   Saltos a cadenas definidas por el usuario (`-j nombre_cadena`)
7.  [Gestión de Conjuntos de Reglas](#7-gestión-de-conjuntos-de-reglas)
    *   Guardar reglas (`iptables-save`)
    *   Restaurar reglas (`iptables-restore`)
    *   Hacer las reglas permanentes (Scripts de inicio, servicios)
8.  [Ejemplos Prácticos](#8-ejemplos-prácticos)
    *   Firewall Stateful Básico (Permitir salida, bloquear entrada no solicitada)
    *   Configuración de Gateway con Masquerading/SNAT
    *   Redirección de Puertos (Port Forwarding / DNAT)
    *   Permitir servicios específicos (SSH, HTTP, etc.)
    *   Bloquear IPs específicas
    *   Registro (Logging) básico y con limitación de tasa
    *   Protección básica contra DoS (SYN floods, Ping of Death) usando `limit`
    *   Uso de cadenas personalizadas para organizar reglas
9.  [Optimización y Buenas Prácticas](#9-optimización-y-buenas-prácticas)
    *   Usar `iptables-restore` para conjuntos grandes
    *   Orden de las reglas: lo más específico/frecuente primero
    *   Minimizar reglas redundantes
    *   Uso eficiente del seguimiento de conexiones
    *   Uso de cadenas personalizadas
    *   Consideraciones sobre el rendimiento
10. [Uso Seguro de Helpers (Ayudantes)](#10-uso-seguro-de-helpers-ayudantes)
    *   Riesgos inherentes al parseo de datos
    *   Filtrado estricto del tráfico `RELATED`
    *   Uso del objetivo `CT --helper` para asignación específica
    *   Desactivar la asignación automática de helpers (`nf_conntrack_helper=0`)
11. [Herramientas y Técnicas de Debugging](#11-herramientas-y-técnicas-de-debugging)
    *   Usar `LOG` para rastrear paquetes
    *   Verificar contadores (`iptables -L -v -n`)
    *   Verificar la tabla de `conntrack`
    *   Mensajes de error comunes de `iptables`
    *   Herramientas externas (`tcpdump`, `nmap`)
12. [Apéndices](#12-apéndices)
    *   Tipos y Códigos ICMP Comunes
    *   Flags TCP Comunes
13. [Referencias](#13-referencias)

---

## 1. Introducción a iptables y Netfilter

`iptables` es la herramienta de espacio de usuario que permite configurar las reglas del firewall incorporado en el kernel de Linux, conocido como **Netfilter**. Netfilter es un framework dentro del kernel que permite interceptar y manipular paquetes de red en varios puntos de su recorrido. `iptables` es la interfaz para interactuar con este framework para tareas como filtrado de paquetes, NAT y manipulación de cabeceras.

### ¿Qué es un Filtro de Paquetes?

Un filtro de paquetes examina las cabeceras de los paquetes de red (y a veces parte de sus datos) a medida que pasan por un sistema. Basándose en un conjunto de reglas predefinidas, decide qué hacer con cada paquete:

*   **ACCEPT (Aceptar):** Permite que el paquete continúe su camino.
*   **DROP (Descartar):** Descarta silenciosamente el paquete, como si nunca hubiera llegado. No se envía ninguna notificación.
*   **REJECT (Rechazar):** Descarta el paquete, pero envía un mensaje de error (normalmente ICMP) al remitente.
*   **Otras acciones:** Registrar el paquete, modificarlo, ponerlo en cola, etc.

`iptables` opera principalmente en las capas de Red (IP) y Transporte (TCP, UDP, ICMP) del modelo TCP/IP, aunque tiene capacidades limitadas para inspeccionar datos de la capa de Aplicación (con precaución).

### ¿Por qué usar iptables?

1.  **Seguridad:** Es la principal razón. Permite proteger un sistema individual o una red completa contra accesos no deseados, ataques, escaneos, etc., controlando qué tráfico puede entrar, salir o pasar a través del sistema.
2.  **Control de Acceso:** Definir qué servicios son accesibles desde dónde (Internet, LAN, hosts específicos).
3.  **NAT (Network Address Translation):** Permite compartir una única dirección IP pública entre múltiples máquinas en una red privada (Masquerading/SNAT) o redirigir tráfico entrante a servidores internos (Port Forwarding/DNAT).
4.  **Monitorización y Registro:** Registrar intentos de conexión sospechosos o tráfico específico para análisis o depuración.
5.  **Manipulación de Paquetes:** Modificar campos de las cabeceras (TOS, TTL, MSS) para optimización de red o políticas de enrutamiento avanzado.

### iptables vs ipchains/ipfwadm (Breve Historia)

*   **ipfwadm:** Usado en kernels Linux 2.0.
*   **ipchains:** Usado en kernels Linux 2.2. Introdujo el concepto de cadenas.
*   **iptables:** Introducido en kernels Linux 2.4 (y usado en 2.6, 3.x, 4.x, 5.x, 6.x...). Se basa en el framework Netfilter. Es mucho más potente y flexible, destacando por su capacidad de **seguimiento de conexiones (stateful firewalling)**.

Aunque existen capas de compatibilidad (`ipchains.ko`, `ipfwadm.ko`), **`iptables` es la herramienta estándar y recomendada** para los kernels modernos.

## 2. Arquitectura de Netfilter

Netfilter proporciona puntos de enganche (hooks) en el stack de red del kernel. `iptables` utiliza estos hooks para insertar sus reglas.

### Hooks de Netfilter (Puntos de Enganche)

Hay 5 hooks definidos para IPv4:

1.  **NF_INET_PRE_ROUTING:** Justo después de que el paquete entra por la interfaz de red, antes de cualquier decisión de enrutamiento. Aquí se realiza DNAT y REDIRECT.
2.  **NF_INET_LOCAL_IN:** Para paquetes destinados a procesos locales en la propia máquina firewall, después de la decisión de enrutamiento. Aquí opera la cadena `INPUT` de `iptables`.
3.  **NF_INET_FORWARD:** Para paquetes que atraviesan la máquina firewall (no destinados localmente), después de la primera decisión de enrutamiento pero antes de la salida. Aquí opera la cadena `FORWARD` de `iptables`.
4.  **NF_INET_LOCAL_OUT:** Para paquetes generados localmente por procesos en la máquina firewall, justo después de ser generados y antes de la decisión de enrutamiento. Aquí opera la cadena `OUTPUT` de `iptables`.
5.  **NF_INET_POST_ROUTING:** Justo antes de que el paquete salga por la interfaz de red, después de la decisión de enrutamiento. Aquí se realiza SNAT y MASQUERADE.

### Cómo viajan los paquetes a través de Netfilter

El recorrido exacto depende del origen y destino del paquete:

*   **Paquetes Entrantes Destinados a la Máquina Local:**
    `Interfaz Entrada -> PRE_ROUTING -> Decisión de Ruta -> LOCAL_IN (Cadena INPUT) -> Proceso Local`
*   **Paquetes Entrantes a ser Reenviados (Forwarded):**
    `Interfaz Entrada -> PRE_ROUTING -> Decisión de Ruta -> FORWARD (Cadena FORWARD) -> POST_ROUTING -> Interfaz Salida`
*   **Paquetes Generados Localmente:**
    `Proceso Local -> LOCAL_OUT (Cadena OUTPUT) -> Decisión de Ruta -> POST_ROUTING -> Interfaz Salida`

Las tablas `nat`, `mangle` y `raw` también se enganchan en estos puntos (y a veces en otros) para realizar sus funciones específicas *antes* o *después* de las cadenas de la tabla `filter`. La tabla `filter` (con `INPUT`, `OUTPUT`, `FORWARD`) es donde se realiza el filtrado principal.

## 3. Conceptos Fundamentales de iptables

### Tablas (`filter`, `nat`, `mangle`, `raw`, `security`)

`iptables` organiza las reglas en tablas según su propósito. Las principales son:

1.  **`filter`:** Es la tabla por defecto y la más usada. Contiene las cadenas `INPUT`, `OUTPUT` y `FORWARD`. Se utiliza para permitir o denegar el paso de paquetes. **No modifica los paquetes**.
2.  **`nat`:** Se usa para la Traducción de Direcciones de Red. Contiene las cadenas `PREROUTING` (para DNAT/REDIRECT), `OUTPUT` (para DNAT/REDIRECT de tráfico local) y `POSTROUTING` (para SNAT/MASQUERADE). **Solo el primer paquete de una conexión atraviesa esta tabla**; la decisión NAT se aplica automáticamente al resto de paquetes de la misma conexión gracias al `conntrack`. **No se debe filtrar aquí**.
3.  **`mangle`:** Se usa para modificar campos específicos en la cabecera IP (como TOS/DSCP, TTL) o para marcar paquetes (MARK). Contiene las 5 cadenas (`PREROUTING`, `INPUT`, `FORWARD`, `OUTPUT`, `POSTROUTING`).
4.  **`raw`:** Se usa principalmente para marcar paquetes que **no** deben ser procesados por el sistema de seguimiento de conexiones (`conntrack`). Contiene las cadenas `PREROUTING` y `OUTPUT`. Se procesa antes que cualquier otra tabla.
5.  **`security`:** Usada para políticas de seguridad obligatorias (Mandatory Access Control - MAC), como las de SELinux. Contiene las cadenas `INPUT`, `OUTPUT` y `FORWARD`. Se consulta después de la tabla `filter`.

### Cadenas (Chains)

Una cadena es una lista ordenada de reglas.

#### Cadenas Incorporadas (INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING)

Cada tabla tiene cadenas predefinidas que se corresponden con los hooks de Netfilter o puntos específicos del flujo de paquetes. Su propósito depende de la tabla a la que pertenecen:

*   Tabla `filter`: `INPUT`, `OUTPUT`, `FORWARD`
*   Tabla `nat`: `PREROUTING`, `OUTPUT`, `POSTROUTING`
*   Tabla `mangle`: `PREROUTING`, `INPUT`, `FORWARD`, `OUTPUT`, `POSTROUTING`
*   Tabla `raw`: `PREROUTING`, `OUTPUT`
*   Tabla `security`: `INPUT`, `OUTPUT`, `FORWARD`

#### Cadenas Definidas por el Usuario

Puedes crear tus propias cadenas dentro de una tabla para organizar mejor las reglas. Se salta a estas cadenas desde otras (incorporadas o definidas por el usuario) usando el objetivo `-j nombre_cadena`. Cuando un paquete llega al final de una cadena definida por el usuario sin una decisión final (como `ACCEPT` o `DROP`), **retorna** a la cadena que la llamó, continuando con la regla siguiente a la del salto.

### Reglas (Rules)

Una regla consiste en:

1.  **Criterios de Concordancia (Matches):** Condiciones que el paquete debe cumplir (IP origen/destino, puerto, protocolo, estado de conexión, etc.).
2.  **Objetivo (Target) o Salto (Jump):** La acción a realizar si el paquete cumple *todos* los criterios.

### Concordancias (Matches)

Especifican las características que debe tener un paquete para que la regla se aplique. Pueden ser:

*   **Genéricas:** Aplicables a cualquier paquete (IP origen/destino, interfaz entrada/salida, protocolo).
*   **Implícitas:** Específicas de un protocolo (TCP, UDP, ICMP), disponibles automáticamente al especificar el protocolo (`-p tcp`, etc.).
*   **Explícitas:** Módulos que deben cargarse explícitamente con `-m nombre_match` (ej. `-m state`, `-m multiport`, `-m limit`).

### Objetivos (Targets) y Saltos (Jumps)

Especifican qué hacer con un paquete que coincide con la regla.

*   **Objetivos Terminantes:** Toman una decisión final sobre el paquete (`ACCEPT`, `DROP`, `REJECT`, `RETURN`). El paquete deja de procesarse en la cadena actual (y a veces en las llamantes, como con `ACCEPT`/`DROP`).
*   **Objetivos No Terminantes:** Realizan una acción sobre el paquete, pero este continúa procesándose por las reglas siguientes (`LOG`, `MARK`, `TOS`, etc.).
*   **Saltos (`-j nombre_cadena`):** Envían el paquete a una cadena definida por el usuario para continuar el procesamiento allí.

### Políticas (Policies) por Defecto

Cada cadena *incorporada* (`INPUT`, `OUTPUT`, `FORWARD`) tiene una política por defecto (`ACCEPT` o `DROP`). Esta política se aplica a cualquier paquete que llegue al final de la cadena sin haber coincidido con ninguna regla que tome una decisión terminante. Es una buena práctica de seguridad establecer la política por defecto a `DROP` y permitir explícitamente solo el tráfico deseado.

## 4. Seguimiento de Conexiones (Connection Tracking)

Esta es la característica clave que hace a `iptables` un firewall *stateful* (con estado). El módulo `nf_conntrack` (antes `ip_conntrack`) examina los paquetes para identificar a qué "conexión" o flujo pertenecen y mantiene una tabla con el estado de cada conexión activa.

### Introducción al Seguimiento de Conexiones (Stateful Firewall)

Un firewall stateful recuerda el estado de las conexiones que lo atraviesan. Esto permite tomar decisiones más inteligentes. Por ejemplo, si permites que una conexión TCP salga de tu red, puedes permitir automáticamente los paquetes de respuesta entrantes que pertenecen a *esa misma conexión* (`ESTABLISHED`), sin necesidad de abrir puertos específicos para el tráfico de retorno, lo cual es mucho más seguro.

*   El seguimiento se realiza principalmente en los hooks `PRE_ROUTING` (para tráfico entrante/forward) y `LOCAL_OUT` (para tráfico generado localmente).
*   La defragmentación de paquetes IP es **implícita y necesaria** para que `conntrack` funcione correctamente. No se puede desactivar si `conntrack` está activo.

### Estados de Conexión (`NEW`, `ESTABLISHED`, `RELATED`, `INVALID`, `UNTRACKED`)

Estos son los estados que puedes usar con el match `-m state --state`:

1.  **`NEW`:** El paquete inicia una nueva conexión, o pertenece a una conexión que aún no ha visto tráfico en ambas direcciones. Típicamente, el primer paquete SYN de una conexión TCP.
    *   **Advertencia:** Por defecto, `iptables` puede marcar como `NEW` paquetes TCP que no sean SYN (ej. un ACK solitario si la conexión original expiró del `conntrack`). Es común añadir una regla para bloquear `NEW` que no sean `SYN` (ver ejemplos).
2.  **`ESTABLISHED`:** El paquete pertenece a una conexión que ya ha visto tráfico en ambas direcciones. La mayoría del tráfico legítimo de respuesta pertenece a este estado.
3.  **`RELATED`:** El paquete está iniciando una nueva conexión, pero está asociada a una conexión `ESTABLISHED` existente. Ejemplos clásicos son las conexiones de datos FTP (relacionadas con la conexión de control FTP) o errores ICMP (como "Host Unreachable") relacionados con una conexión TCP o UDP existente. Requiere módulos "helper" específicos para protocolos complejos.
4.  **`INVALID`:** El paquete no pudo ser identificado o no pertenece a ninguna conexión conocida, o está malformado de alguna manera (ej. error ICMP sin conexión asociada, paquete TCP fuera de ventana). Generalmente, es seguro y recomendable usar `DROP` para estos paquetes.
5.  **`UNTRACKED`:** El paquete ha sido explícitamente marcado para no ser rastreado usando el objetivo `NOTRACK` en la tabla `raw`. El `conntrack` ignora estos paquetes. Útil para reducir la carga en firewalls/routers muy cargados donde no se necesita el estado para ciertos flujos (¡con precaución!).

### Cómo ver las conexiones rastreadas (`/proc/net/nf_conntrack`, `conntrack -L`)

El kernel mantiene una tabla con las conexiones activas. Puedes inspeccionarla:

```bash
# En kernels modernos (con IPv6)
cat /proc/net/nf_conntrack

# En kernels más antiguos (solo IPv4)
cat /proc/net/ip_conntrack

# Usando la herramienta conntrack (si está instalada, parte de conntrack-tools)
conntrack -L
```

Una entrada típica muestra: protocolo, tiempo de vida restante, estado interno del kernel, IPs y puertos origen/destino originales, flags (`[UNREPLIED]`, `[ASSURED]`), IPs y puertos esperados en la respuesta.

*   `[UNREPLIED]`: Solo se ha visto tráfico en una dirección.
*   `[ASSURED]`: Se ha visto tráfico en ambas direcciones. Estas conexiones son menos propensas a ser eliminadas si se alcanza el límite máximo de conexiones rastreadas (`nf_conntrack_max`).

El número máximo de conexiones se puede ver/ajustar vía `sysctl net.netfilter.nf_conntrack_max` o `/proc/sys/net/netfilter/nf_conntrack_max`.

### Estados en Conexiones TCP

Internamente, `conntrack` usa estados más detallados que siguen el ciclo de vida TCP (SYN_SENT, SYN_RECV, ESTABLISHED, FIN_WAIT, CLOSE_WAIT, LAST_ACK, TIME_WAIT, CLOSE). Sin embargo, para el match `-m state`, estos se mapean a los 4 estados principales:

1.  Llega el primer `SYN`: Estado `NEW`. (`SYN_SENT` interno).
2.  Llega el `SYN/ACK` de respuesta: Estado cambia a `ESTABLISHED`. (`SYN_RECV` interno).
3.  Llega el `ACK` final del handshake: Sigue `ESTABLISHED`. (`ESTABLISHED` interno).
4.  Intercambio de datos: Sigue `ESTABLISHED`.
5.  Intercambio de `FIN`/`ACK` para cerrar: Sigue `ESTABLISHED` hasta que la conexión pasa a `TIME_WAIT` o `CLOSE` internamente, momento en el cual la entrada de `conntrack` expira según sus timeouts específicos.

### Estados en Conexiones UDP

UDP es sin estado, pero `conntrack` le asigna estados basados en el tráfico visto:

1.  Llega el primer paquete UDP: Estado `NEW`. (`[UNREPLIED]` interno). Timeout corto (ej. 30s).
2.  Llega un paquete de respuesta válido (IPs/puertos invertidos): Estado cambia a `ESTABLISHED`. (`[ASSURED]` interno). Timeout más largo (ej. 180s). Cada paquete subsiguiente resetea el timeout.

### Estados en Conexiones ICMP

ICMP tampoco tiene estado, pero `conntrack` maneja ciertos tipos:

*   **Tipos de Petición/Respuesta** (Echo, Timestamp, Info, Address Mask):
    1.  Llega la Petición (ej. Echo Request, tipo 8): Estado `NEW`. Timeout corto (ej. 30s).
    2.  Llega la Respuesta (ej. Echo Reply, tipo 0) que coincide (IPs/puertos invertidos, mismo ID ICMP): Estado `ESTABLISHED`. La entrada `conntrack` se destruye poco después de que la respuesta pase.
*   **Tipos de Error** (Destination Unreachable, Time Exceeded, etc.): Si el error ICMP se puede asociar a una conexión TCP o UDP existente en la tabla `conntrack` (basándose en la cabecera IP+Transporte incluida en el mensaje ICMP), se marca como `RELATED`. Esto permite que los errores ICMP importantes lleguen al host origen. La entrada `conntrack` original puede ser destruida.

### Conexiones por Defecto (Otros Protocolos)

Para protocolos IP que `conntrack` no entiende específicamente (ej. GRE, ESP si no hay helpers), se aplica un seguimiento genérico similar al de UDP:

1.  Primer paquete: `NEW`.
2.  Paquete de respuesta: `ESTABLISHED`.
Utiliza un timeout genérico (`nf_conntrack_generic_timeout`, por defecto 600s).

### Conexiones No Rastreadas (Tabla `raw` y `NOTRACK`)

La tabla `raw` se procesa antes que `conntrack`. Su principal uso es con el objetivo `NOTRACK`.

```bash
iptables -t raw -A PREROUTING <match_criteria> -j NOTRACK
iptables -t raw -A OUTPUT <match_criteria> -j NOTRACK
```

*   Los paquetes que coinciden con una regla `NOTRACK` **no** serán procesados por `conntrack`.
*   En la tabla `filter` (u otras), estos paquetes coincidirán con `-m state --state UNTRACKED`.
*   **Precaución:** Usar `NOTRACK` deshabilita el seguimiento de estado para esos paquetes. Esto significa que:
    *   No funcionará NAT para ellos (ya que NAT depende de `conntrack`).
    *   No se identificarán conexiones `RELATED` (incluyendo errores ICMP).
    *   Debes gestionar manualmente el tráfico de respuesta si es necesario.
*   Útil para reducir la carga en routers/firewalls con tráfico muy alto donde el estado no es crítico (ej. tráfico de tránsito que no necesita NAT ni filtrado stateful complejo).

### Ayudantes de Seguimiento de Conexiones (Helpers para FTP, IRC, etc.)

Algunos protocolos (FTP, IRC DCC, SIP, H.323, TFTP, Amanda, PPTP, etc.) son difíciles de rastrear porque negocian direcciones IP y puertos para conexiones secundarias *dentro* de la carga útil (payload) de la conexión principal (de control).

*   Los **helpers de conntrack** (`nf_conntrack_*`, ej. `nf_conntrack_ftp`) son módulos del kernel que inspeccionan el payload de la conexión de control.
*   Cuando detectan la negociación de una conexión secundaria, crean una "expectativa" temporal en `conntrack`.
*   Cuando llega el primer paquete de esa conexión secundaria esperada, `conntrack` lo reconoce gracias a la expectativa y lo marca como `RELATED` a la conexión de control original.
*   Esto permite que reglas como `-m state --state RELATED -j ACCEPT` permitan estas conexiones secundarias dinámicas.

*   Los **helpers de NAT** (`nf_nat_*`, ej. `nf_nat_ftp`) hacen un trabajo adicional: no solo detectan la negociación, sino que también **reescriben** las direcciones IP y puertos dentro del payload para que funcionen correctamente a través de NAT.

*   **Carga de Módulos:** Los helpers normalmente deben cargarse explícitamente (`modprobe nf_conntrack_ftp`, `modprobe nf_nat_ftp`).
*   **Seguridad:** Los helpers pueden ser un riesgo de seguridad si no se configuran con cuidado, ya que abren agujeros dinámicamente basados en datos que podrían ser manipulados. Se recomienda encarecidamente restringir el tráfico `RELATED` tanto como sea posible (ver sección sobre Uso Seguro de Helpers).

## 5. Traducción de Direcciones de Red (NAT)

NAT permite modificar las direcciones IP de origen y/o destino de los paquetes, generalmente para permitir que redes privadas accedan a Internet usando una IP pública compartida, o para exponer servicios internos al exterior. Se configura en la tabla `nat`.

### ¿Qué es NAT y por qué usarlo?

*   **Superar escasez de IPv4:** Permite que múltiples dispositivos en una red privada (con IPs RFC1918 como 192.168.x.x) compartan una única IP pública para acceder a Internet.
*   **Seguridad (limitada):** Oculta la topología de la red interna (aunque no es un sustituto de un firewall).
*   **Flexibilidad:** Permite redirigir servicios a diferentes servidores internos sin cambiar la IP pública.

### Tipos de NAT en iptables

#### SNAT (Source NAT)

*   Modifica la **dirección IP de origen** de los paquetes salientes.
*   Se aplica en la cadena `POSTROUTING` (justo antes de salir).
*   Usado para permitir que una red interna salga a Internet a través del firewall.
*   Requiere especificar la IP pública a usar.
    ```bash
    # Ejemplo: Todo lo que sale de la LAN (192.168.1.0/24) por eth0 usa la IP pública 1.2.3.4
    iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -o eth0 -j SNAT --to-source 1.2.3.4
    ```
*   Se puede especificar un rango de IPs públicas para balanceo simple o un rango de puertos origen.

#### DNAT (Destination NAT)

*   Modifica la **dirección IP de destino** (y opcionalmente el puerto) de los paquetes entrantes.
*   Se aplica en la cadena `PREROUTING` (justo al entrar) y `OUTPUT` (para tráfico local).
*   Usado para redirigir tráfico destinado a la IP pública del firewall hacia un servidor interno (Port Forwarding).
    ```bash
    # Ejemplo: El tráfico TCP entrante por eth0 a la IP pública 1.2.3.4, puerto 80,
    # se redirige al servidor web interno 192.168.1.100, puerto 80.
    iptables -t nat -A PREROUTING -i eth0 -d 1.2.3.4 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.100:80
    ```
*   Se puede especificar un rango de IPs/puertos destino para balanceo simple.

#### Masquerading (Enmascaramiento)

*   Un caso especial de `SNAT`.
*   No requiere especificar la IP de origen; usa automáticamente la IP de la interfaz de salida.
*   Ideal para conexiones con **IP dinámica** (PPP, DHCP), ya que se adapta si la IP cambia.
*   Olvida las conexiones si la interfaz cae, lo cual es útil para IPs dinámicas.
*   Tiene un ligero overhead mayor que `SNAT`.
*   Solo válido en la cadena `POSTROUTING`.
    ```bash
    # Ejemplo: Todo lo que sale por ppp0 se enmascara
    iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
    ```
*   Puede usar `--to-ports` para especificar el rango de puertos origen.

#### Redirect

*   Un caso especial de `DNAT`.
*   Redirige el tráfico a la **propia máquina firewall**, cambiando el puerto destino.
*   Usado principalmente para **proxy transparente**.
*   Solo válido en las cadenas `PREROUTING` y `OUTPUT`.
    ```bash
    # Ejemplo: Redirigir el tráfico web entrante por eth1 al puerto 3128 (Squid) en el propio firewall
    iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j REDIRECT --to-ports 3128
    ```

### NAT y Seguimiento de Conexiones

*   NAT **depende fundamentalmente** del seguimiento de conexiones (`conntrack`).
*   `iptables` solo aplica la regla NAT al **primer paquete** de una conexión.
*   `conntrack` recuerda la decisión NAT (ej. qué IP/puerto se usó para SNAT, o a qué IP/puerto interno se redirigió con DNAT).
*   Todos los paquetes subsiguientes de la misma conexión (identificados por `conntrack`) son automáticamente modificados de la misma manera (y en la dirección inversa para las respuestas) **sin volver a pasar por la tabla `nat`**.
*   Por esto, **no se debe filtrar en la tabla `nat`**, ya que la mayoría de los paquetes la eluden. El filtrado se hace en la tabla `filter`.

### Consideraciones sobre NAT (Helpers, Protocolos Complejos)

*   **Necesidad de Helpers:** Protocolos como FTP, IRC DCC, SIP, H.323, PPTP, TFTP necesitan módulos `helper` de NAT (`nf_nat_*`) además de los de `conntrack` para reescribir las direcciones/puertos negociados dentro del payload. Sin ellos, estas conexiones secundarias fallarán a través de NAT.
*   **Rutas de Retorno:** Para SNAT, el mundo exterior debe saber cómo enrutar el tráfico de respuesta de vuelta a la IP pública usada por el SNAT. Para DNAT, el servidor interno debe usar el firewall como gateway para enviar las respuestas de vuelta, para que puedan ser "des-DNATeadas".
*   **NAT Loopback/Hairpin:** Acceder a un servicio DNATeado desde *dentro* de la misma LAN requiere una regla SNAT adicional para forzar que las respuestas pasen por el firewall. Alternativamente, usar DNS dividido (split DNS).
*   **NAT es un Hack:** Fue una solución a la escasez de IPv4. IPv6 elimina la necesidad de NAT para la mayoría de los casos de uso.

## 6. El Comando `iptables`: Uso Práctico

### Sintaxis Básica

```bash
iptables [-t tabla] <COMANDO> [cadena] [criterios/matches] [-j objetivo/salto]
```

*   `-t tabla`: Especifica la tabla (`filter`, `nat`, `mangle`, `raw`, `security`). Si se omite, se usa `filter`.
*   `COMANDO`: La acción a realizar sobre una cadena o regla (ver abajo).
*   `cadena`: El nombre de la cadena sobre la que operar (ej. `INPUT`, `FORWARD`, `mi_cadena`).
*   `criterios/matches`: Condiciones que debe cumplir el paquete (`-p`, `-s`, `-d`, `-m`, etc.).
*   `-j objetivo/salto`: La acción (`ACCEPT`, `DROP`, `LOG`, `SNAT`, etc.) o la cadena a la que saltar.

### Especificación de Tablas (`-t`)

Usar `-t filter`, `-t nat`, `-t mangle`, `-t raw`, `-t security` para operar sobre una tabla distinta a la `filter` por defecto.

### Operaciones sobre Cadenas

*   **`-L [cadena]`:** Listar las reglas de una cadena (o todas si se omite).
    *   `-v`: Modo verboso (muestra contadores de paquetes/bytes, interfaces, etc.).
    *   `-n`: Salida numérica (no resolver IPs/puertos a nombres).
    *   `-x`: Expandir números (mostrar contadores exactos sin K/M/G).
    *   `--line-numbers`: Mostrar número de línea de cada regla.
*   **`-F [cadena]`:** Flush (vaciar) todas las reglas de una cadena (o todas si se omite).
*   **`-Z [cadena]`:** Zero (poner a cero) los contadores de paquetes/bytes de una cadena (o todas si se omite).
*   **`-N cadena`:** Crear una Nueva cadena definida por el usuario.
*   **`-X [cadena]`:** Borrar una cadena definida por el usuario (debe estar vacía y sin referencias).
*   **`-E cadena_vieja cadena_nueva`:** Renombrar una cadena definida por el usuario.
*   **`-P cadena POLITICA`:** Establecer la Política por defecto (`ACCEPT` o `DROP`) para una cadena incorporada.

### Operaciones sobre Reglas

*   **`-A cadena [criterios] -j objetivo`:** Append (añadir) una regla al final de la cadena.
*   **`-I cadena [num_regla] [criterios] -j objetivo`:** Insertar una regla al principio (si se omite `num_regla`) o en la posición `num_regla` (empezando por 1).
*   **`-R cadena num_regla [criterios] -j objetivo`:** Reemplazar la regla en la posición `num_regla`.
*   **`-D cadena num_regla`:** Borrar la regla en la posición `num_regla`.
*   **`-D cadena [criterios] -j objetivo`:** Borrar la primera regla que coincida exactamente con los criterios y objetivo especificados.

### Especificaciones de Concordancia (Matches)

#### Genéricos (Siempre disponibles)

*   **`-p, --protocol [!] protocolo`:** Coincide con el protocolo (ej. `tcp`, `udp`, `icmp`, `gre`, `esp`, `ah`, `all`, o número).
*   **`-s, --source [!] dirección[/máscara]`:** Coincide con la IP de origen (ej. `192.168.1.1`, `192.168.1.0/24`, `! 10.0.0.8`).
*   **`-d, --destination [!] dirección[/máscara]`:** Coincide con la IP de destino.
*   **`-i, --in-interface [!] interfaz`:** Coincide con la interfaz de entrada (ej. `eth0`, `ppp+`, `! lo`). Válido en `INPUT`, `FORWARD`, `PREROUTING`.
*   **`-o, --out-interface [!] interfaz`:** Coincide con la interfaz de salida. Válido en `OUTPUT`, `FORWARD`, `POSTROUTING`.
*   **`-f, --fragment`:** Coincide con el segundo fragmento y subsiguientes de un paquete IP fragmentado. `! -f` coincide con el primer fragmento o paquetes no fragmentados. (Generalmente no necesario si se usa `conntrack`).

#### Implícitos (Cargados con `-p`)

*   **TCP (`-p tcp`):**
    *   `--sport, --source-port [!] puerto[:puerto]`: Puerto(s) origen TCP.
    *   `--dport, --destination-port [!] puerto[:puerto]`: Puerto(s) destino TCP.
    *   `--tcp-flags [!] mascara flags_comp`: Compara flags TCP (SYN, ACK, FIN, RST, URG, PSH, ALL, NONE). Ej: `--tcp-flags SYN,ACK,FIN,RST SYN` (solo SYN activo).
    *   `--syn`: Abreviatura para `--tcp-flags SYN,RST,ACK SYN`. Coincide con el inicio de conexión.
    *   `--tcp-option [!] num`: Coincide si la opción TCP especificada está presente.
*   **UDP (`-p udp`):**
    *   `--sport, --source-port [!] puerto[:puerto]`: Puerto(s) origen UDP.
    *   `--dport, --destination-port [!] puerto[:puerto]`: Puerto(s) destino UDP.
*   **ICMP (`-p icmp`):**
    *   `--icmp-type [!] tipo[/codigo]|nombre`: Coincide con el tipo/código ICMP (ej. `8`, `echo-request`, `3/3`). `iptables -p icmp -h` lista nombres.

#### Explícitos (Carga con `-m nombre_match`)

(Selección de los más comunes e importantes basados en el tutorial)

*   **`state`:**
    *   `--state [!] estado[,estado...]`: Coincide con el estado `conntrack` (`NEW`, `ESTABLISHED`, `RELATED`, `INVALID`, `UNTRACKED`). **Fundamental para firewalls stateful.**
        ```bash
        # Permitir tráfico establecido y relacionado entrante
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        # Bloquear paquetes inválidos
        iptables -A INPUT -m state --state INVALID -j DROP
        ```
*   **`conntrack`:** Versión extendida de `state`, permite granularidad.
    *   `--ctstate`, `--ctproto`, `--ctorigsrc`, `--ctorigdst`, `--ctreplsrc`, `--ctrepldst`, `--ctstatus`, `--ctexpire`.
*   **`limit`:** Limita la tasa de coincidencias. Útil para reducir logs o mitigar DoS simples.
    *   `--limit tasa`: Tasa promedio (ej. `5/minute`, `10/second`).
    *   `--limit-burst num`: Ráfaga inicial permitida (default 5).
        ```bash
        # Limitar logs de paquetes dropeados a 5 por minuto
        iptables -A INPUT ... -j LOG ...
        iptables -A INPUT ... -m limit --limit 5/minute --limit-burst 5 -j LOG ...
        # Limitar nuevas conexiones SYN a 1 por segundo
        iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 5 -j ACCEPT
        ```
*   **`multiport`:** Permite especificar múltiples puertos o rangos separados por comas (hasta 15).
    *   `--sports puerto[,puerto:puerto,...]`: Puertos origen.
    *   `--dports puerto[,puerto:puerto,...]`: Puertos destino.
    *   `--ports puerto[,puerto:puerto,...]`: Coincide si origen y destino son uno de los puertos listados.
        ```bash
        # Permitir entrada a SSH, HTTP, HTTPS
        iptables -A INPUT -p tcp -m multiport --dports 22,80,443 -j ACCEPT
        ```
*   **`mac`:**
    *   `--mac-source [!] dirección_mac`: Coincide con la dirección MAC de origen (formato `XX:XX:XX:XX:XX:XX`). Solo útil en `INPUT`, `FORWARD`, `PREROUTING`.
*   **`owner`:** Coincide con el propietario del socket local que generó el paquete. Solo útil en `OUTPUT`.
    *   `--uid-owner usuario`: ID de usuario.
    *   `--gid-owner grupo`: ID de grupo.
    *   (`--pid-owner`, `--sid-owner`, `--cmd-owner` están obsoletos/eliminados en kernels recientes).
*   **`comment`:**
    *   `--comment "texto"`: Adjunta un comentario a la regla (visible con `iptables-save`, útil para documentación). **No afecta al filtrado.**
        ```bash
        iptables -A INPUT -s 10.0.0.0/8 -j DROP -m comment --comment "Bloquear red interna antigua"
        ```
*   **Otros matches comunes:** `string` (con precaución), `recent`, `time`, `connmark`, `mark`, `iprange`, `length`, `tcpmss`, `tos`, `dscp`, `helper`.

### Especificaciones de Objetivo (Targets/Jumps)

#### Terminantes

*   **`ACCEPT`:** Acepta el paquete y deja de procesar reglas en la cadena actual y sus llamantes dentro de la misma tabla.
*   **`DROP`:** Descarta el paquete silenciosamente. Deja de procesar reglas.
*   **`REJECT`:** Descarta el paquete y envía un mensaje de error ICMP (o TCP RST).
    *   `--reject-with tipo_rechazo`: Especifica el error a enviar (ej. `icmp-port-unreachable` (default), `tcp-reset`, `icmp-net-unreachable`).
*   **`RETURN`:** Deja de procesar reglas en la cadena actual y retorna a la cadena llamante (o aplica la política por defecto si es una cadena incorporada).

#### Modificadores/Informativos (No terminantes)

*   **`LOG`:** Registra información del paquete en el log del kernel (syslog/dmesg).
    *   `--log-prefix "texto"`: Añade un prefijo al mensaje de log.
    *   `--log-level nivel`: Establece el nivel de log (ej. `warning`, `info`, `debug`).
    *   `--log-tcp-sequence`, `--log-tcp-options`, `--log-ip-options`: Incluye información adicional.
*   **`ULOG`:** Envía información del paquete a espacio de usuario a través de netlink (usado por `ulogd`). Más flexible que `LOG`.
    *   `--ulog-nlgroup grupo`: Grupo netlink (1-32).
    *   `--ulog-prefix "texto"`: Prefijo (hasta 32 chars).
    *   `--ulog-cprange bytes`: Cuántos bytes del paquete copiar (0 = todo).
    *   `--ulog-qthreshold num`: Cuántos paquetes encolar en kernel antes de enviar.

#### Modificadores de Paquetes (Tabla `mangle`)

*   **`MARK`:** Establece una marca (un valor entero) asociada al paquete *dentro del kernel*. No modifica el paquete en sí. Usado para enrutamiento avanzado (`ip rule`), QoS (`tc`).
    *   `--set-mark marca[/mascara]`: Establece la marca.
*   **`CONNMARK`:** Establece o recupera una marca asociada a la *conexión completa* en `conntrack`.
    *   `--set-mark marca[/mascara]`: Establece la marca de la conexión.
    *   `--save-mark [--mask mascara]`: Guarda la marca del paquete actual en la marca de la conexión.
    *   `--restore-mark [--mask mascara]`: Restaura la marca del paquete desde la marca de la conexión.
*   **`TOS`:** Modifica el campo Type of Service (8 bits) de la cabecera IP.
    *   `--set-tos valor|nombre`: Establece el TOS (ej. `Minimize-Delay`, `Maximize-Throughput`, `0x10`).
*   **`DSCP`:** Modifica el campo Differentiated Services Code Point (6 bits, parte del campo TOS) de la cabecera IP.
    *   `--set-dscp valor`: Establece el valor DSCP (decimal o hex).
    *   `--set-dscp-class clase`: Establece el DSCP usando nombres de clase (ej. `EF`, `AF11`, `CS1`).
*   **`TTL`:** Modifica el campo Time To Live de la cabecera IP.
    *   `--ttl-set valor`: Establece el TTL a un valor específico.
    *   `--ttl-dec valor`: Decrementa el TTL (además del decremento normal por cada salto).
    *   `--ttl-inc valor`: Incrementa el TTL.
*   **`TCPMSS`:** Modifica la opción Maximum Segment Size en paquetes TCP SYN. Útil para solucionar problemas de MTU con ISPs que bloquean ICMP.
    *   `--set-mss valor`: Establece el MSS a un valor fijo.
    *   `--clamp-mss-to-pmtu`: Ajusta el MSS automáticamente al MTU del camino (PMTU) menos 40 bytes.

#### NAT (Tabla `nat`)

*   **`SNAT`:** Source NAT.
    *   `--to-source ip[-ip][:puerto-puerto]`: Especifica la(s) IP(s) y opcionalmente puerto(s) origen a usar.
*   **`DNAT`:** Destination NAT.
    *   `--to-destination ip[-ip][:puerto-puerto]`: Especifica la(s) IP(s) y opcionalmente puerto(s) destino a usar.
*   **`MASQUERADE`:** Enmascaramiento (SNAT dinámico).
    *   `--to-ports puerto[-puerto]`: Opcional, especifica el rango de puertos origen.
*   **`REDIRECT`:** Redirección (DNAT a la propia máquina).
    *   `--to-ports puerto[-puerto]`: Especifica el puerto(s) local al que redirigir.

#### Otros Objetivos

*   **`QUEUE` / `NFQUEUE`:** Envía el paquete a una cola en espacio de usuario para ser procesado por otra aplicación (requiere `ip_queue` o `nfnetlink_queue`). `NFQUEUE` es más moderno y permite múltiples colas (`--queue-num`).
*   **`NOTRACK`:** (Tabla `raw`) Marca el paquete para que `conntrack` lo ignore.
*   **`CLASSIFY`:** (Tabla `mangle`, cadena `POSTROUTING`) Asigna una clase para QoS/`tc`.
    *   `--set-class MAYOR:MENOR`
*   **`SECMARK`:** (Tabla `mangle`) Establece una marca de seguridad SELinux en el paquete.
*   **`CONNSECMARK`:** (Tabla `mangle`) Guarda/restaura la marca de seguridad entre el paquete y la conexión.

#### Saltos a Cadenas Definidas por el Usuario

*   **`-j nombre_cadena`:** Envía el paquete al inicio de la cadena `nombre_cadena` (que debe existir en la misma tabla).

## 7. Gestión de Conjuntos de Reglas

### Guardar reglas (`iptables-save`)

Guarda el conjunto de reglas actual (de una o todas las tablas) a la salida estándar en un formato eficiente y restaurable.

```bash
# Guardar todas las tablas
iptables-save > /etc/iptables/rules.v4

# Guardar solo la tabla filter, incluyendo contadores
iptables-save -t filter -c > /tmp/filter-rules.txt
```

### Restaurar reglas (`iptables-restore`)

Lee un conjunto de reglas desde la entrada estándar y lo aplica atómicamente (tabla por tabla). Es mucho más rápido que ejecutar comandos `iptables` individuales para conjuntos grandes.

```bash
# Restaurar desde un archivo, manteniendo contadores si existen en el archivo
iptables-restore -c < /etc/iptables/rules.v4

# Restaurar sin borrar las reglas existentes (-n)
# CUIDADO: Esto puede llevar a reglas duplicadas o comportamiento inesperado
# iptables-restore -n < /tmp/nuevas-reglas.txt
```

### Hacer las reglas permanentes (Scripts de inicio, servicios)

`iptables` por sí solo no guarda las reglas entre reinicios. Métodos comunes:

1.  **Usar `iptables-save` y `iptables-restore`:**
    *   Guardar las reglas funcionales con `iptables-save > /etc/iptables/rules.v4` (y `ip6tables-save > /etc/iptables/rules.v6` para IPv6).
    *   Usar un servicio o script de inicio que ejecute `iptables-restore < /etc/iptables/rules.v4` al arrancar. Muchas distribuciones proporcionan paquetes como `iptables-persistent` (Debian/Ubuntu) o servicios systemd (`iptables.service`) que hacen esto automáticamente si los archivos existen en la ubicación esperada.
2.  **Scripts de Firewall Personalizados:** Escribir un script shell (`/etc/init.d/myfirewall` o un script ejecutado por systemd) que contenga todos los comandos `iptables` necesarios para configurar el firewall desde cero. Este script se ejecuta al inicio.
    *   **Ventaja:** Más flexible, permite lógica condicional, uso de variables, etc.
    *   **Desventaja:** Más lento de cargar para conjuntos de reglas muy grandes comparado con `iptables-restore`.

## 8. Ejemplos Prácticos

### Firewall Stateful Básico (Permitir salida, bloquear entrada no solicitada)

```bash
#!/bin/sh

IPT="/sbin/iptables"

# Interfaces
INET_IFACE="eth0"
LAN_IFACE="eth1"
LO_IFACE="lo"

# Flush existing rules and set default policies
$IPT -F
$IPT -X
$IPT -t nat -F
$IPT -t nat -X
$IPT -t mangle -F
$IPT -t mangle -X
$IPT -t raw -F
$IPT -t raw -X

# Default DROP policies
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT ACCEPT # Allow outgoing from firewall itself for simplicity

# Allow loopback traffic
$IPT -A INPUT -i ${LO_IFACE} -j ACCEPT
# $IPT -A OUTPUT -o ${LO_IFACE} -j ACCEPT # Covered by OUTPUT ACCEPT policy

# Allow established and related traffic (fundamental for stateful firewall)
$IPT -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow NEW connections FROM the LAN outwards (assuming LAN is trusted)
$IPT -A INPUT -i ${LAN_IFACE} -m state --state NEW -j ACCEPT
$IPT -A FORWARD -i ${LAN_IFACE} -m state --state NEW -j ACCEPT

# Optional: Allow specific NEW incoming connections to the firewall (e.g., SSH from LAN)
$IPT -A INPUT -i ${LAN_IFACE} -p tcp --dport 22 -m state --state NEW -j ACCEPT

# Optional: Log dropped packets (rate-limited)
$IPT -A INPUT -m limit --limit 5/minute -j LOG --log-prefix "Denied INPUT: " --log-level 7
$IPT -A FORWARD -m limit --limit 5/minute -j LOG --log-prefix "Denied FORWARD: " --log-level 7

# (NAT rules would go in the nat table - see next example)
```

### Configuración de Gateway con Masquerading/SNAT

(Añadir a las reglas anteriores, y ajustar políticas si es necesario)

```bash
# Enable IP Forwarding (crucial for a gateway)
echo 1 > /proc/sys/net/ipv4/ip_forward

# --- NAT Table Rules ---

# If using dynamic IP (e.g., PPPoE on ppp0 or DHCP on eth0)
$IPT -t nat -A POSTROUTING -o ${INET_IFACE} -j MASQUERADE

# If using static IP (replace 1.2.3.4 with your static public IP)
# $IPT -t nat -A POSTROUTING -o ${INET_IFACE} -j SNAT --to-source 1.2.3.4

# --- Filter Table Rules (adjust FORWARD policy) ---
# We already allowed NEW from LAN outwards and ESTABLISHED/RELATED back in.
# Default FORWARD policy is DROP, so this is a basic secure setup.
```

### Redirección de Puertos (Port Forwarding / DNAT)

(Añadir a las reglas anteriores)

```bash
# Variables for internal server
INTERNAL_WEB_SERVER="192.168.1.100"
FIREWALL_PUBLIC_IP="1.2.3.4"

# --- NAT Table Rule ---
# Redirect incoming HTTP traffic to internal server
$IPT -t nat -A PREROUTING -i ${INET_IFACE} -d ${FIREWALL_PUBLIC_IP} -p tcp --dport 80 -j DNAT --to-destination ${INTERNAL_WEB_SERVER}:80

# --- Filter Table Rule ---
# Allow the forwarded traffic to reach the internal server
$IPT -A FORWARD -i ${INET_IFACE} -o ${LAN_IFACE} -d ${INTERNAL_WEB_SERVER} -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
# (The ESTABLISHED,RELATED rule already allows the return traffic)
```

### Permitir servicios específicos (SSH, HTTP, etc.)

Añadir reglas a la cadena `INPUT` (para servicios en el firewall) o `FORWARD` (para servicios internos detrás del firewall via DNAT).

```bash
# Allow incoming SSH to the firewall itself from anywhere
$IPT -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT

# Allow incoming HTTP to the firewall itself from anywhere
$IPT -A INPUT -p tcp --dport 80 -m state --state NEW -j ACCEPT
```

### Bloquear IPs específicas

```bash
# Block all traffic from a specific bad IP
$IPT -A INPUT -s 198.51.100.10 -j DROP
$IPT -A FORWARD -s 198.51.100.10 -j DROP

# Block a specific IP from accessing SSH only
$IPT -A INPUT -p tcp --dport 22 -s 198.51.100.11 -j DROP
```

### Registro (Logging) básico y con limitación de tasa

```bash
# Log all dropped INPUT packets (can be noisy!)
# $IPT -A INPUT -j LOG --log-prefix "Dropped INPUT: "

# Log dropped INPUT packets, limited to 5 per minute
$IPT -A INPUT -m limit --limit 5/minute -j LOG --log-prefix "Dropped INPUT: "

# Log accepted SSH connections
$IPT -A INPUT -p tcp --dport 22 -m state --state NEW -j LOG --log-prefix "Accepted SSH: "
$IPT -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT
```

### Protección básica contra DoS (SYN floods, Ping of Death) usando `limit`

```bash
# Limit incoming SYN packets (adjust limit/burst as needed)
$IPT -A INPUT -p tcp --syn -m limit --limit 10/s --limit-burst 20 -j ACCEPT
$IPT -A INPUT -p tcp --syn -j DROP

# Limit incoming ICMP Echo Requests (ping)
$IPT -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT
$IPTABLES -A INPUT -p icmp --icmp-type echo-request -j DROP
```
**Nota:** Estas son medidas muy básicas. La protección DoS real es mucho más compleja.

### Uso de cadenas personalizadas para organizar reglas

```bash
# Create custom chains
$IPT -N TCP_WAN_IN
$IPT -N UDP_WAN_IN
$IPT -N ICMP_WAN_IN

# Jump from INPUT to custom chains for traffic from WAN
$IPT -A INPUT -i ${INET_IFACE} -p tcp -j TCP_WAN_IN
$IPT -A INPUT -i ${INET_IFACE} -p udp -j UDP_WAN_IN
$IPT -A INPUT -i ${INET_IFACE} -p icmp -j ICMP_WAN_IN

# Populate custom chains
$IPT -A TCP_WAN_IN -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A TCP_WAN_IN -p tcp --dport 80 -m state --state NEW -j ACCEPT # Allow HTTP
$IPT -A TCP_WAN_IN -p tcp --dport 443 -m state --state NEW -j ACCEPT # Allow HTTPS
# ... add other allowed TCP ports ...
$IPT -A TCP_WAN_IN -j LOG --log-prefix "Denied TCP_WAN_IN: " # Log rest
$IPT -A TCP_WAN_IN -j DROP # Drop rest

$IPT -A UDP_WAN_IN -m state --state ESTABLISHED,RELATED -j ACCEPT
# ... add allowed UDP ports (e.g., VPN) ...
$IPT -A UDP_WAN_IN -j LOG --log-prefix "Denied UDP_WAN_IN: "
$IPT -A UDP_WAN_IN -j DROP

$IPT -A ICMP_WAN_IN -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A ICMP_WAN_IN -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT # Allow ping
# ... add other allowed ICMP types ...
$IPT -A ICMP_WAN_IN -j LOG --log-prefix "Denied ICMP_WAN_IN: "
$IPT -A ICMP_WAN_IN -j DROP
```

## 9. Optimización y Buenas Prácticas

(Basado en las ideas de Jan Engelhardt y Oskar Andreasson)

1.  **Usar `iptables-restore`:** Para conjuntos de reglas grandes (>100 reglas), `iptables-restore` es significativamente más rápido que ejecutar comandos `iptables` individuales en un script, ya que carga las reglas en el kernel en menos operaciones.
2.  **Orden de las Reglas:**
    *   Coloca las reglas que coinciden con el tráfico más frecuente **cerca del principio** de la cadena.
    *   La regla `-m state --state ESTABLISHED,RELATED -j ACCEPT` casi siempre debe ser una de las primeras en `INPUT` y `FORWARD`, ya que coincide con la gran mayoría del tráfico legítimo.
    *   Coloca reglas más específicas antes que reglas más generales si se solapan.
3.  **Usar Cadenas Personalizadas:** Divide conjuntos de reglas grandes y complejos en cadenas definidas por el usuario para mejorar la legibilidad y, potencialmente, el rendimiento (evitando que los paquetes atraviesen reglas irrelevantes).
4.  **Evitar Reglas Redundantes:** Simplifica. No uses `-s 0.0.0.0/0` si omitir `-s` tiene el mismo efecto.
5.  **Combinar Reglas:** Usa el match `multiport` para combinar reglas que solo difieren en el puerto TCP/UDP. Para conjuntos grandes de IPs o puertos, considera usar `ipset`, que es mucho más eficiente que múltiples reglas `iptables`.
6.  **Filtrado `INVALID`:** Siempre ten una regla para descartar (`DROP`) el tráfico `-m state --state INVALID` temprano en las cadenas `INPUT` y `FORWARD`.
7.  **Políticas `DROP` por Defecto:** Para mayor seguridad, usa `-P DROP` en `INPUT` y `FORWARD` y permite explícitamente solo el tráfico necesario. Para `OUTPUT`, `ACCEPT` puede ser más práctico en estaciones de trabajo, pero `DROP` es más seguro en servidores/firewalls dedicados (aunque requiere más reglas explícitas para permitir la salida necesaria).
8.  **No Filtrar en Tabla `nat`:** Realiza todo el filtrado en la tabla `filter`. La tabla `nat` es solo para traducción de direcciones y la mayoría de los paquetes la evitan después del primero.
9.  **Optimización de `conntrack`:**
    *   Ajusta `nf_conntrack_max` si es necesario (monitoriza `/proc/sys/net/netfilter/nf_conntrack_count`).
    *   Ajusta los timeouts de `conntrack` (`nf_conntrack_*_timeout_*` vía `sysctl`) si los valores por defecto no son adecuados (raramente necesario).
    *   Considera usar `NOTRACK` en la tabla `raw` para tráfico de muy alto volumen que no necesita seguimiento de estado (ej. en un router de núcleo), pero sé consciente de las implicaciones.
10. **Ser Específico:** Evita reglas demasiado generales si puedes ser más específico (ej. especifica interfaz, IPs origen/destino siempre que sea posible).
11. **Comentarios:** Usa el match `-m comment --comment "..."` para documentar reglas complejas directamente en el ruleset (visible con `iptables-save`).

## 10. Uso Seguro de Helpers (Ayudantes)

Los helpers de `conntrack` y `NAT` son necesarios para protocolos complejos, pero introducen riesgos porque interpretan datos de la aplicación para abrir puertos dinámicamente.

1.  **Riesgo:** Un atacante podría intentar enviar datos manipulados en la conexión de control para engañar al helper y hacer que abra puertos no deseados hacia hosts internos o externos.
2.  **Filtrado Estricto de `RELATED`:** **Nunca** uses una regla genérica como `-m state --state RELATED -j ACCEPT`. Siempre restringe las reglas `RELATED` tanto como sea posible:
    *   Especifica el protocolo (`-p`).
    *   Especifica la interfaz (`-i`, `-o`).
    *   Especifica las IPs origen/destino esperadas si las conoces (ej. el rango de IPs del servidor de datos FTP, o los servidores RTP del proveedor VoIP).
    *   Usa el match `-m helper --helper nombre_helper` para asegurarte de que el tráfico `RELATED` fue generado por el helper esperado.
    ```bash
    # Ejemplo: Permitir tráfico RELATED de datos FTP *solo* hacia el servidor FTP interno
    iptables -A FORWARD -i $INET_IFACE -o $LAN_IFACE -d $INTERNAL_FTP_SERVER \
        -p tcp -m state --state RELATED -m helper --helper ftp -j ACCEPT

    # Ejemplo: Permitir tráfico RELATED RTP/UDP *solo* hacia los servidores RTP del proveedor VoIP
    iptables -A FORWARD -i $LAN_IFACE -o $INET_IFACE -d $VOIP_PROVIDER_RTP_NET \
        -p udp -m state --state RELATED -m helper --helper sip -j ACCEPT
    ```
3.  **Uso del Objetivo `CT --helper` (Kernels >= 2.6.34):** En lugar de dejar que los helpers se asocien automáticamente a los puertos estándar (ej. FTP al puerto 21), es más seguro desactivar la asignación automática y asignar explícitamente un helper a un flujo específico usando el objetivo `CT` en la tabla `raw`.
    *   **Desactivar Asignación Automática (Kernels >= 3.5):**
        ```bash
        # Al cargar el módulo
        modprobe nf_conntrack nf_conntrack_helper=0
        # O en tiempo de ejecución
        echo 0 > /proc/sys/net/netfilter/nf_conntrack_helper
        ```
    *   **Asignar Helper Explícitamente:**
        ```bash
        # Asignar el helper FTP al tráfico TCP destinado al puerto 21 del servidor 1.2.3.4
        iptables -t raw -A PREROUTING -d 1.2.3.4 -p tcp --dport 21 -j CT --helper ftp
        ```
    *   Esto asegura que el helper solo inspeccione el tráfico que tú quieres que inspeccione.

4.  **Carga Módulos Necesarios:** Carga solo los módulos helper (`nf_conntrack_*`, `nf_nat_*`) que realmente necesites.

## 11. Herramientas y Técnicas de Debugging

Depurar reglas de `iptables` puede ser frustrante. Aquí algunas técnicas:

1.  **Objetivo `LOG`:** Es tu mejor amigo. Inserta reglas `LOG` temporalmente para ver qué paquetes están llegando a cierto punto de tu ruleset y qué características tienen.
    *   Usa `--log-prefix` para identificar fácilmente de qué regla proviene el log.
    *   Combínalo con `-m limit` para no inundar tus logs.
    *   Coloca reglas `LOG` justo antes de una regla `DROP` para ver qué se está bloqueando.
    *   Coloca reglas `LOG` al final de las cadenas (antes de la política `DROP`) para ver qué paquetes no coincidieron con ninguna regla.
2.  **Contadores:** Usa `iptables -L -v -n` para ver cuántos paquetes y bytes han coincidido con cada regla. Resetea los contadores con `-Z` antes de probar algo específico. Si el contador de una regla que esperas que funcione no aumenta, el paquete no está llegando a esa regla o no cumple los criterios.
3.  **Verificar `conntrack`:** Usa `cat /proc/net/nf_conntrack` o `conntrack -L` para ver si las conexiones están siendo rastreadas como esperas y qué estado tienen. Busca entradas `[UNREPLIED]` o `INVALID`.
4.  **Simplificar:** Comenta temporalmente secciones grandes de tu ruleset para aislar dónde está el problema. Empieza con políticas `ACCEPT` y ve añadiendo reglas `DROP` (o viceversa) hasta que encuentres la que causa el problema.
5.  **Mensajes de Error:** Presta atención a los mensajes de `iptables` al cargar las reglas. "Unknown arg" suele significar un error de sintaxis, un match/target no disponible (módulo no cargado o no compilado), o la falta de una precondición (como `-p tcp` antes de `--dport`). "No chain/target/match by that name" indica que el módulo necesario no está cargado/compilado o el nombre está mal escrito.
6.  **Herramientas Externas:**
    *   `tcpdump` o `wireshark`: Para capturar paquetes en diferentes interfaces y ver exactamente qué está pasando a nivel de red antes, durante y después del firewall.
    *   `nmap`: Para escanear puertos desde fuera y dentro de la red y verificar si el firewall bloquea/permite lo que esperas.
    *   `ping`, `traceroute`: Para pruebas básicas de conectividad y rutas.
7.  **Verificar Módulos:** Usa `lsmod | grep nf_` o `lsmod | grep ip_` para ver qué módulos de Netfilter/iptables están cargados. Verifica en `/lib/modules/$(uname -r)/kernel/net/ipv4/netfilter/` (o `ipv6/`, `netfilter/`) si los archivos `.ko` existen.

## 12. Apéndices

### Tipos y Códigos ICMP Comunes

| Tipo | Código | Nombre             | Descripción                                     |
| :--- | :----- | :----------------- | :---------------------------------------------- |
| 0    | 0      | echo-reply         | Respuesta a Ping                                |
| 3    | 0      | net-unreachable    | Red de destino inalcanzable                     |
| 3    | 1      | host-unreachable   | Host de destino inalcanzable                    |
| 3    | 2      | protocol-unreachable | Protocolo no soportado en destino             |
| 3    | 3      | port-unreachable   | Puerto no abierto en destino (UDP/otros)        |
| 3    | 4      | fragmentation-needed | Paquete necesita fragmentarse pero DF bit está |
| 3    | 9      | net-prohibited     | Red destino prohibida administrativamente     |
| 3    | 10     | host-prohibited    | Host destino prohibido administrativamente    |
| 3    | 13     | communication-prohibited | Comunicación prohibida por filtro (firewall) |
| 4    | 0      | source-quench      | Petición de reducir velocidad (obsoleto)        |
| 5    | 0      | net-redirect       | Redirección de ruta para una red                |
| 5    | 1      | host-redirect      | Redirección de ruta para un host                |
| 8    | 0      | echo-request       | Petición de Ping                                |
| 11   | 0      | time-exceeded      | TTL expiró durante el tránsito                  |
| 11   | 1      | reassembly-timeout | TTL expiró durante el reensamblado              |

### Flags TCP Comunes

*   **SYN** (Synchronize): Inicia una conexión.
*   **ACK** (Acknowledge): Confirma la recepción de datos. Presente en casi todos los paquetes después del SYN inicial.
*   **FIN** (Finish): Indica que el emisor ha terminado de enviar datos. Usado para cerrar conexiones.
*   **RST** (Reset): Resetea la conexión abruptamente (ej. puerto cerrado, error irrecuperable).
*   **PSH** (Push): Indica al receptor que entregue los datos en buffer a la aplicación inmediatamente.
*   **URG** (Urgent): Indica que el campo "Urgent Pointer" es significativo (datos urgentes).

## 13. Referencias

*   Man pages: `iptables(8)`, `iptables-extensions(8)`, `iptables-save(8)`, `iptables-restore(8)`
*   Netfilter project website: [https://www.netfilter.org/](https://www.netfilter.org/)
*   Oskar Andreasson's Iptables Tutorial (fuente principal para esta guía)
*   RFCs relevantes (791-IP, 793-TCP, 768-UDP, 792-ICMP, etc.)
*   Documentación del kernel de Linux (`Documentation/networking/` en el código fuente)
