# Instalador Automatizado de GitLab para Ubuntu Server 24.04

## Índice
- [Introducción](#introducción)
- [Características](#características)
- [Requisitos del Sistema](#requisitos-del-sistema)
- [Guía de Instalación](#guía-de-instalación)
  - [Descarga e Instalación Inicial](#descarga-e-instalación-inicial)
  - [Configuración](#configuración)
  - [Instalación Final](#instalación-final)
- [Variables de Configuración](#variables-de-configuración)
  - [Configuración Básica](#configuración-básica)
  - [Configuración SSL/TLS](#configuración-ssltls)
  - [Configuración de Hardware](#configuración-de-hardware)
  - [Configuración de Correo Electrónico](#configuración-de-correo-electrónico)
  - [Configuración de Backup](#configuración-de-backup)
  - [Configuración de Base de Datos](#configuración-de-base-de-datos)
  - [Configuración de Rendimiento](#configuración-de-rendimiento)
  - [Configuración de Almacenamiento](#configuración-de-almacenamiento)
- [Guía del Administrador](#guía-del-administrador)
  - [Primer Inicio y Configuración Inicial](#primer-inicio-y-configuración-inicial)
  - [Comandos Básicos de Administración](#comandos-básicos-de-administración)
  - [Gestión de Usuarios y Permisos](#gestión-de-usuarios-y-permisos)
  - [Monitorización y Logs](#monitorización-y-logs)
  - [Mantenimiento Rutinario](#mantenimiento-rutinario)
  - [Actualizaciones](#actualizaciones)
  - [Solución de Problemas Comunes](#solución-de-problemas-comunes)
- [Consideraciones de Seguridad](#consideraciones-de-seguridad)
- [Preguntas Frecuentes](#preguntas-frecuentes)
- [Licencia](#licencia)

## Introducción

Este script proporciona una solución automatizada para la instalación y configuración de GitLab en entornos empresariales que utilizan Ubuntu Server 24.04. Diseñado para simplificar el despliegue, permite personalizar todos los aspectos de la instalación a través de un archivo de configuración, eliminando la necesidad de intervención manual durante el proceso de instalación.

## Características

- **Instalación completamente automatizada**: Una vez configurado, el proceso es autónomo
- **Configuración flexible**: Personalización de todos los aspectos de GitLab mediante archivo de configuración
- **Optimización automática**: Ajustes basados en los recursos disponibles (CPU, RAM)
- **Soporte SSL/TLS integrado**: Configuración de certificados propios o Let's Encrypt
- **Configuración de correo completa**: Integración con servidores SMTP empresariales
- **Sistema de respaldo automático**: Configuración de copias de seguridad programadas
- **Optimización de rendimiento**: Ajustes avanzados según hardware disponible
- **Flexibilidad de almacenamiento**: Posibilidad de utilizar rutas personalizadas
- **Seguridad mejorada**: Configuración de firewall y hardening básico
- **Documentación automática**: Generación de información post-instalación

## Requisitos del Sistema

- **Sistema Operativo**: Ubuntu Server 24.04 LTS
- **CPU**: Mínimo 2 núcleos (4+ recomendado para entornos de producción)
- **RAM**: Mínimo 4GB (8GB+ recomendado para entornos de producción)
- **Almacenamiento**: Mínimo 10GB de espacio libre (SSD recomendado)
- **Conectividad**: Acceso a Internet para descarga de paquetes
- **Permisos**: Acceso root o sudo
- **Nombre de dominio**: Recomendado para acceso externo

## Guía de Instalación

### Descarga e Instalación Inicial

1. Descargue el script de instalación:
   ```bash
   wget https://ruta-al-script/gitlab-installer.sh
   ```

2. Haga el script ejecutable:
   ```bash
   chmod +x gitlab-installer.sh
   ```

3. Ejecute el script por primera vez para generar el archivo de configuración:
   ```bash
   sudo ./gitlab-installer.sh
   ```
   
   > **Nota**: En esta primera ejecución, el script solo creará el archivo de configuración `gitlab_config.conf` y terminará, permitiéndole editar los parámetros antes de la instalación real.

### Configuración

Edite el archivo de configuración generado:
```bash
nano gitlab_config.conf
```

Ajuste los parámetros según las necesidades de su entorno (consulte la sección [Variables de Configuración](#variables-de-configuración) para detalles sobre cada opción).

### Instalación Final

Una vez configurados los parámetros, ejecute el script nuevamente para iniciar la instalación:
```bash
sudo ./gitlab-installer.sh
```

El script realizará ahora la instalación completa sin intervención adicional, mostrando el progreso de cada paso. Al finalizar, se generará un archivo `gitlab_installation_info.txt` con toda la información relevante de la instalación.

## Variables de Configuración

El archivo `gitlab_config.conf` contiene todas las variables configurables. A continuación se detalla cada una de ellas:

### Configuración Básica

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `GITLAB_VERSION` | Edición de GitLab a instalar | `ce` | `ce` (Community Edition), `ee` (Enterprise Edition) |
| `EXTERNAL_URL` | URL completa para acceder a GitLab | `http://gitlab.miempresa.com` | Cualquier URL válida (http/https) |

> **IMPORTANTE**: `EXTERNAL_URL` debe ser una URL válida y accesible. Si planea usar SSL, debe comenzar con `https://`.

### Configuración SSL/TLS

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `USE_SSL` | Habilitar/deshabilitar SSL | `false` | `true` (habilitar), `false` (deshabilitar) |
| `SSL_CERT_PATH` | Ruta al certificado SSL existente | `""` (vacío) | Ruta absoluta al archivo de certificado (.crt/.pem) |
| `SSL_KEY_PATH` | Ruta a la clave privada SSL | `""` (vacío) | Ruta absoluta al archivo de clave (.key) |
| `USE_LETSENCRYPT` | Usar Let's Encrypt para certificados | `false` | `true` (usar Let's Encrypt), `false` (no usar) |
| `LETSENCRYPT_EMAIL` | Email para registro con Let's Encrypt | `""` (vacío) | Dirección de correo válida |

> **Nota sobre SSL**: Si `USE_SSL=true`, debe proporcionar certificados existentes O habilitar Let's Encrypt. Para Let's Encrypt, su servidor debe ser accesible desde Internet en el puerto 80.

### Configuración de Hardware

| Variable | Descripción | Detección |
|----------|-------------|-----------|
| `CPU_CORES` | Número de núcleos de CPU | Detectado automáticamente |
| `TOTAL_RAM_MB` | Memoria RAM total en MB | Detectado automáticamente |

> **Nota**: Estas variables se detectan automáticamente, pero pueden ser sobrescritas si es necesario para entornos virtualizados o contenedores.

### Configuración de Correo Electrónico

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `SMTP_ENABLED` | Activar/desactivar servicio de correo | `false` | `true` (activar), `false` (desactivar) |
| `SMTP_ADDRESS` | Servidor SMTP | `smtp.miempresa.com` | Dirección del servidor SMTP |
| `SMTP_PORT` | Puerto del servidor SMTP | `587` | Típicamente `587` (STARTTLS) o `465` (SSL) |
| `SMTP_USERNAME` | Usuario de autenticación SMTP | `gitlab@miempresa.com` | Usuario para autenticación |
| `SMTP_PASSWORD` | Contraseña SMTP | `password_seguro` | Contraseña para autenticación |
| `SMTP_DOMAIN` | Dominio SMTP | `miempresa.com` | Dominio para HELO SMTP |
| `SMTP_AUTHENTICATION` | Tipo de autenticación | `login` | `login`, `plain`, `cram_md5` o `none` |
| `SMTP_ENABLE_STARTTLS_AUTO` | Usar STARTTLS | `true` | `true` (usar), `false` (no usar) |
| `SMTP_TLS` | Usar TLS directo | `false` | `true` (usar), `false` (no usar) |
| `GITLAB_EMAIL_FROM` | Dirección remitente | `gitlab@miempresa.com` | Dirección de correo válida |
| `GITLAB_EMAIL_REPLY_TO` | Dirección de respuesta | `noreply@miempresa.com` | Dirección de correo válida |

> **Nota**: La configuración de correo es esencial para notificaciones, restablecimiento de contraseñas y alertas del sistema. Se recomienda configurarla correctamente.

### Configuración de Backup

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `BACKUP_ENABLED` | Activar/desactivar backups automáticos | `true` | `true` (activar), `false` (desactivar) |
| `BACKUP_PATH` | Directorio para backups | `/var/opt/gitlab/backups` | Ruta absoluta a directorio existente o que se creará |
| `BACKUP_KEEP_TIME` | Tiempo de retención de backups (segundos) | `604800` | Tiempo en segundos (604800 = 7 días) |

> **Recomendación**: Configure los backups para almacenarse en un volumen separado o NFS para mayor seguridad.

### Configuración de Base de Datos

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `DB_ADAPTER` | Motor de base de datos | `postgresql` | Solo `postgresql` es compatible actualmente |
| `DB_HOST` | Servidor de base de datos | `localhost` | Host de la BD (usar `localhost` para BD integrada) |
| `DB_PORT` | Puerto de la base de datos | `5432` | Puerto PostgreSQL (normalmente 5432) |
| `DB_USERNAME` | Usuario de base de datos | `gitlab` | Nombre de usuario para PostgreSQL |
| `DB_PASSWORD` | Contraseña de BD | `""` (se genera automáticamente) | Contraseña o vacío para generación automática |
| `DB_NAME` | Nombre de la base de datos | `gitlabhq_production` | Nombre de la BD a crear/usar |

> **Nota**: Para la mayoría de los despliegues, la configuración predeterminada de base de datos es suficiente. Use una BD externa solo para entornos de alta disponibilidad o despliegues a gran escala.

### Configuración de Rendimiento

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `GITLAB_UNICORN_WORKER_TIMEOUT` | Tiempo de espera para workers (segundos) | `60` | Valor recomendado: 60-300 |
| `GITLAB_UNICORN_WORKER_PROCESSES` | Número de procesos worker | `3` (ajustado según CPU) | Se ajusta automáticamente pero puede sobreescribirse |

> **Optimización**: El script ajusta automáticamente estos valores basados en los recursos disponibles. Los valores manuales solo son necesarios para casos específicos.

### Configuración de Almacenamiento

| Variable | Descripción | Valor Predeterminado | Opciones |
|----------|-------------|----------------------|----------|
| `STORAGE_PATH` | Ruta personalizada para datos | `/mnt/gitlab-data` | Ruta absoluta a directorio existente o que se creará |
| `USE_CUSTOM_STORAGE` | Activar almacenamiento personalizado | `false` | `true` (usar ruta personalizada), `false` (usar ruta por defecto) |

> **Recomendación**: Para entornos de producción, configure el almacenamiento en un volumen dedicado con alto rendimiento.

## Guía del Administrador

### Primer Inicio y Configuración Inicial

Después de completar la instalación:

1. Acceda a GitLab a través de la URL configurada (`EXTERNAL_URL`).

2. Inicie sesión con:
   - Usuario: `root`
   - Contraseña: (disponible en `/etc/gitlab/initial_root_password` o en `gitlab_installation_info.txt`)

3. Cambie inmediatamente la contraseña predeterminada (la contraseña inicial expira a las 24 horas).

4. Configure los ajustes básicos:
   - Navegue a **Admin Area** > **Settings**
   - Revise y ajuste la configuración general, apariencia, correo, etc.

5. Configure la primera estructura organizativa:
   - Cree grupos para departamentos/equipos
   - Configure políticas de visibilidad
   - Establezca plantillas de proyectos si es necesario

### Comandos Básicos de Administración

GitLab se administra principalmente mediante el comando `gitlab-ctl`:

```bash
# Ver estado de todos los servicios
sudo gitlab-ctl status

# Reiniciar todos los servicios
sudo gitlab-ctl restart

# Reiniciar un servicio específico
sudo gitlab-ctl restart nginx

# Reconfigurar GitLab después de cambios en gitlab.rb
sudo gitlab-ctl reconfigure

# Verificar la versión de GitLab
sudo gitlab-ctl version

# Verificar estado de salud de GitLab
sudo gitlab-rake gitlab:check

# Crear un backup manual
sudo gitlab-rake gitlab:backup:create

# Restaurar un backup (ejemplo con timestamp 1640289600_2021_12_24)
sudo gitlab-rake gitlab:backup:restore BACKUP=1640289600_2021_12_24
```

### Gestión de Usuarios y Permisos

La administración de usuarios se realiza principalmente a través de la interfaz web:

1. **Usuarios**:
   - Creación/desactivación: **Admin Area** > **Overview** > **Users**
   - Implementar autenticación LDAP/AD: **Admin Area** > **Settings** > **Sign-in Restrictions**

2. **Grupos**:
   - Creación/gestión: **Groups** > **Your Groups** > **New Group**
   - Roles de grupo: Owner, Maintainer, Developer, Reporter, Guest

3. **Permisos**:
   - Por proyecto: Navegar al proyecto > **Settings** > **Members**
   - Por grupo: Navegar al grupo > **Group Information** > **Members**

4. **Tokens de acceso**:
   - Personal: **User Settings** > **Access Tokens**
   - De proyecto: Navegar al proyecto > **Settings** > **Repository** > **Project Access Tokens**

### Monitorización y Logs

#### Acceso a Logs

Los logs se almacenan en `/var/log/gitlab/`:

```bash
# Ver logs del servicio Puma (servidor web)
sudo tail -f /var/log/gitlab/puma/current

# Ver logs de Sidekiq (procesamiento en segundo plano)
sudo tail -f /var/log/gitlab/sidekiq/current

# Ver logs de Nginx
sudo tail -f /var/log/gitlab/nginx/access.log
sudo tail -f /var/log/gitlab/nginx/error.log

# Ver logs de PostgreSQL
sudo tail -f /var/log/gitlab/postgresql/current

# Ver logs de Redis
sudo tail -f /var/log/gitlab/redis/current
```

#### Monitorización del Sistema

GitLab incluye Prometheus para monitorización interna:

1. Acceda a **Admin Area** > **Monitoring** > **Metrics Dashboard**
2. Instale y configure opciones de monitorización adicionales como Grafana si es necesario

### Mantenimiento Rutinario

#### Operaciones Periódicas

1. **Backups regulares**:
   - Verifique que los backups automáticos funcionan correctamente
   - Pruebe la restauración de backups periódicamente
   - Traslade los backups a almacenamiento externo

2. **Gestión de almacenamiento**:
   - Monitorice el uso de espacio: `df -h`
   - Administre artefactos antiguos: **Admin Area** > **Settings** > **Repository** > **Repository storage**

3. **Optimización de la base de datos**:
   ```bash
   # Ejecutar vacuum en la base de datos
   sudo gitlab-rake gitlab:db:vacuum
   ```

4. **Limpieza de caché**:
   ```bash
   # Limpiar caché
   sudo gitlab-rake gitlab:cache:clear
   ```

### Actualizaciones

#### Actualizando GitLab

Para actualizar GitLab a una nueva versión:

```bash
# Crear backup previo a la actualización
sudo gitlab-rake gitlab:backup:create

# Actualizar paquetes del sistema
sudo apt update

# Actualizar GitLab
sudo apt install gitlab-ce  # o gitlab-ee para Enterprise Edition

# Aplicar cambios
sudo gitlab-ctl reconfigure
```

> **IMPORTANTE**: Siempre revise las [notas de la versión](https://about.gitlab.com/releases/) antes de actualizar y realice un backup completo.

#### Actualización incremental

Para instalaciones que están varias versiones atrás, se recomienda actualizar incrementalmente:

```bash
# Ver versión actual
sudo gitlab-rake gitlab:env:info

# Actualizar a versión específica
sudo apt install gitlab-ce=15.0.0-ce.0  # ajuste el número de versión según necesite
```

### Solución de Problemas Comunes

#### GitLab no inicia

```bash
# Verificar estado
sudo gitlab-ctl status

# Ver logs específicos
sudo gitlab-ctl tail

# Verificar configuración
sudo gitlab-rake gitlab:check

# Reiniciar con verbose
sudo gitlab-ctl restart --verbose
```

#### Problemas de base de datos

```bash
# Verificar estado PostgreSQL
sudo gitlab-ctl status postgresql

# Logs de PostgreSQL
sudo gitlab-ctl tail postgresql

# Verificar integridad de la BD
sudo gitlab-rake gitlab:db:validate
```

#### Problemas de correo electrónico

```bash
# Probar configuración de correo
sudo gitlab-rake gitlab:incoming_email:check

# Ver configuración SMTP
sudo grep -A 20 'smtp_' /etc/gitlab/gitlab.rb
```

#### Problemas de espacio en disco

```bash
# Verificar uso de disco
df -h

# Identificar directorios grandes
sudo du -h --max-depth=1 /var/opt/gitlab/

# Limpiar artefactos temporales
sudo gitlab-ctl cleanup
```

## Consideraciones de Seguridad

### Hardening de Seguridad

1. **Actualizaciones regulares**:
   - Mantenga GitLab y Ubuntu Server actualizados
   - Configure notificaciones de actualizaciones de seguridad

2. **Firewall**:
   - Límite los puertos abiertos a SSH (22), HTTP (80) y HTTPS (443)
   - Implemente reglas de firewall más restrictivas según sea necesario

3. **SSL/TLS**:
   - Siempre use HTTPS en producción
   - Configure TLS 1.2+ y deshabilite protocolos antiguos

4. **Autenticación**:
   - Habilite 2FA para todos los usuarios
   - Establezca políticas de contraseñas fuertes
   - Considere integración con SSO corporativo

5. **Aislamiento del sistema**:
   - Use LXC/Docker o virtualización si es posible
   - Separe servicios críticos en hosts diferentes

### Auditoría y Cumplimiento

1. **Logs de auditoría**:
   - Habilite los logs de auditoría: **Admin Area** > **Settings** > **Network** > **Performance optimization**
   - Configure la retención de logs apropiada

2. **Gestión de secretos**:
   - Use las variables CI/CD protegidas para secretos
   - Implemente una estrategia de rotación de credenciales

3. **Compliance**:
   - Documente configuraciones para auditorías de seguridad
   - Implemente controles específicos para requisitos regulatorios (GDPR, HIPAA, etc.)

## Preguntas Frecuentes

### Generales

**P: ¿Puedo actualizar de Community Edition a Enterprise Edition?**
R: Sí, es posible. Consulte la [documentación oficial](https://docs.gitlab.com/ee/update/index.html#switching-between-editions).

**P: ¿Cuántos usuarios soporta esta instalación?**
R: Dependiendo del hardware, puede soportar desde decenas hasta miles de usuarios. Para despliegues grandes (>500 usuarios), considere una arquitectura distribuida.

**P: ¿Es seguro ejecutar este script en un servidor de producción existente?**
R: El script está diseñado para ser seguro, pero siempre es recomendable probarlo en un entorno de desarrollo primero o hacer un backup completo del sistema antes de ejecutarlo.

### Configuración

**P: ¿Puedo cambiar la URL externa después de la instalación?**
R: Sí, edite `/etc/gitlab/gitlab.rb`, cambie `external_url`, y ejecute `sudo gitlab-ctl reconfigure`.

**P: ¿Cómo integro GitLab con Active Directory/LDAP?**
R: Configure las opciones LDAP en `/etc/gitlab/gitlab.rb` y ejecute `sudo gitlab-ctl reconfigure`. Hay ejemplos en el archivo de configuración.

**P: ¿Cómo configuro GitLab para alta disponibilidad?**
R: La configuración de alta disponibilidad es compleja y requiere múltiples servidores. Consulte la [documentación de HA](https://docs.gitlab.com/ee/administration/reference_architectures/).

### Rendimiento

**P: GitLab se está ejecutando lentamente, ¿cómo lo optimizo?**
R: Verifique la utilización de recursos (`top`, `htop`), ajuste la configuración de unicorn/puma workers, aumente RAM y CPU, y considere separar servicios en diferentes servidores.

**P: ¿Dónde puedo encontrar métricas de rendimiento?**
R: En **Admin Area** > **Monitoring** > **Metrics Dashboard**, o use `gitlab-ctl status` y `htop` para métricas del sistema.

## Licencia

Este script se distribuye bajo la licencia MIT. Consulte el archivo LICENSE para más detalles.

GitLab Community Edition (CE) se distribuye bajo la licencia MIT.  
GitLab Enterprise Edition (EE) requiere una licencia comercial para funcionalidades premium.
