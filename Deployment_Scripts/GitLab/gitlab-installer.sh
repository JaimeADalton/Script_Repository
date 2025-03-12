#!/bin/bash
#########################################################################
# Script de Instalación y Configuración Automatizada de GitLab
# Para Ubuntu Server 24.04
# Uso Empresarial
#########################################################################

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Archivo de configuración
CONFIG_FILE="gitlab_config.conf"

# Variables predeterminadas
DEFAULT_CONFIG="# Configuración de GitLab Installer
# Modificar según las necesidades de su entorno empresarial

# Versión de GitLab a instalar (ce = Community Edition, ee = Enterprise Edition)
GITLAB_VERSION=\"ce\"

# URL externa de GitLab (dominio completo para acceder a GitLab)
EXTERNAL_URL=\"http://gitlab.miempresa.com\"

# Configuración de SSL/TLS
USE_SSL=false
SSL_CERT_PATH=\"\"
SSL_KEY_PATH=\"\"
USE_LETSENCRYPT=false
LETSENCRYPT_EMAIL=\"\"

# Configuración de hardware
# Valores recomendados según CPU y RAM disponibles
CPU_CORES=$(nproc)
TOTAL_RAM_MB=$(free -m | grep Mem | awk '{print $2}')

# Configuración de correo electrónico
SMTP_ENABLED=false
SMTP_ADDRESS=\"smtp.miempresa.com\"
SMTP_PORT=587
SMTP_USERNAME=\"gitlab@miempresa.com\"
SMTP_PASSWORD=\"password_seguro\"
SMTP_DOMAIN=\"miempresa.com\"
SMTP_AUTHENTICATION=\"login\"
SMTP_ENABLE_STARTTLS_AUTO=true
SMTP_TLS=false
GITLAB_EMAIL_FROM=\"gitlab@miempresa.com\"
GITLAB_EMAIL_REPLY_TO=\"noreply@miempresa.com\"

# Configuración de backup
BACKUP_ENABLED=true
BACKUP_PATH=\"/var/opt/gitlab/backups\"
BACKUP_KEEP_TIME=604800  # 7 días en segundos

# Configuración de base de datos
DB_ADAPTER=\"postgresql\"
DB_HOST=\"localhost\"
DB_PORT=5432
DB_USERNAME=\"gitlab\"
DB_PASSWORD=\"\"  # Se generará automáticamente si está en blanco
DB_NAME=\"gitlabhq_production\"

# Opciones avanzadas
GITLAB_UNICORN_WORKER_TIMEOUT=60
GITLAB_UNICORN_WORKER_PROCESSES=3  # Se ajustará según CPU

# Configuración de almacenamiento
STORAGE_PATH=\"/mnt/gitlab-data\"
USE_CUSTOM_STORAGE=false"

#########################################################################
# Funciones
#########################################################################

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function log_step() {
    echo -e "\n${BLUE}[PASO]${NC} $1"
}

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

function check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "No se puede determinar el sistema operativo"
        exit 1
    fi
    
    source /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        log_error "Este script solo es compatible con Ubuntu"
        exit 1
    fi
    
    if [ "$VERSION_ID" != "24.04" ]; then
        log_warn "Este script está diseñado para Ubuntu 24.04. La versión detectada es $VERSION_ID"
        echo -n "¿Desea continuar de todos modos? (s/n): "
        read -r answer
        if [ "$answer" != "s" ]; then
            exit 1
        fi
    fi
}

function create_config_if_not_exists() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Creando archivo de configuración: $CONFIG_FILE"
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
        log_info "Archivo de configuración creado. Por favor, edítelo según sus necesidades y ejecute este script nuevamente."
        exit 0
    else
        log_info "Usando configuración existente: $CONFIG_FILE"
    fi
}

function load_config() {
    log_step "Cargando configuración"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Archivo de configuración no encontrado: $CONFIG_FILE"
        exit 1
    fi
    
    # Cargar configuración
    source "$CONFIG_FILE"
    
    # Ajustar número de workers basado en CPU
    if [ "$GITLAB_UNICORN_WORKER_PROCESSES" -le 0 ]; then
        # Fórmula: 1 worker por núcleo + 1, con un mínimo de 2 y máximo de 16
        GITLAB_UNICORN_WORKER_PROCESSES=$((CPU_CORES + 1))
        if [ "$GITLAB_UNICORN_WORKER_PROCESSES" -lt 2 ]; then
            GITLAB_UNICORN_WORKER_PROCESSES=2
        elif [ "$GITLAB_UNICORN_WORKER_PROCESSES" -gt 16 ]; then
            GITLAB_UNICORN_WORKER_PROCESSES=16
        fi
    fi
    
    # Generar contraseña de base de datos si está en blanco
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        log_info "Contraseña de base de datos generada automáticamente"
    fi
    
    log_info "Configuración cargada correctamente"
}

function update_system() {
    log_step "Actualizando sistema"
    apt-get update
    apt-get upgrade -y
}

function install_dependencies() {
    log_step "Instalando dependencias"
    apt-get install -y curl openssh-server ca-certificates tzdata perl postfix
}

function configure_postfix() {
    log_step "Configurando Postfix"
    
    # Configurar Postfix para 'Internet Site'
    debconf-set-selections <<< "postfix postfix/mailname string $(echo $EXTERNAL_URL | sed 's|^http[s]*://||')"
    debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
    
    # Reinstalar para aplicar configuración
    apt-get install -y --reinstall postfix
}

function add_gitlab_repository() {
    log_step "Agregando repositorio GitLab"
    
    curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-${GITLAB_VERSION}/script.deb.sh | bash
}

function install_gitlab() {
    log_step "Instalando GitLab"
    
    export EXTERNAL_URL="$EXTERNAL_URL"
    
    apt-get install -y gitlab-${GITLAB_VERSION}
}

function configure_ssl() {
    if [ "$USE_SSL" = true ]; then
        log_step "Configurando SSL/TLS"
        
        if [ "$USE_LETSENCRYPT" = true ]; then
            log_info "Configurando Let's Encrypt"
            
            # Configurar Let's Encrypt
            gitlab-ctl reconfigure
            
            # Ejecutar el cliente Let's Encrypt
            gitlab-ctl stop nginx
            letsencrypt_domain=$(echo $EXTERNAL_URL | sed 's|^http[s]*://||')
            
            mkdir -p /etc/gitlab/ssl
            gitlab-rake "gitlab:letsencrypt:register[${letsencrypt_domain},${LETSENCRYPT_EMAIL},true]"
            gitlab-ctl start nginx
            
        elif [ -n "$SSL_CERT_PATH" ] && [ -n "$SSL_KEY_PATH" ]; then
            log_info "Usando certificados SSL existentes"
            
            # Crear directorio para certificados
            mkdir -p /etc/gitlab/ssl
            
            # Copiar certificados
            cp "$SSL_CERT_PATH" "/etc/gitlab/ssl/$(echo $EXTERNAL_URL | sed 's|^http[s]*://||').crt"
            cp "$SSL_KEY_PATH" "/etc/gitlab/ssl/$(echo $EXTERNAL_URL | sed 's|^http[s]*://||').key"
            
            chmod 600 /etc/gitlab/ssl/*
        else
            log_warn "SSL habilitado pero no se proporcionaron rutas de certificados o configuración Let's Encrypt"
        fi
    fi
}

function configure_email() {
    if [ "$SMTP_ENABLED" = true ]; then
        log_step "Configurando correo electrónico"
        
        # Crear configuración de correo
        cat > /etc/gitlab/gitlab.rb.email_config <<EOF
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "$SMTP_ADDRESS"
gitlab_rails['smtp_port'] = $SMTP_PORT
gitlab_rails['smtp_user_name'] = "$SMTP_USERNAME"
gitlab_rails['smtp_password'] = "$SMTP_PASSWORD"
gitlab_rails['smtp_domain'] = "$SMTP_DOMAIN"
gitlab_rails['smtp_authentication'] = "$SMTP_AUTHENTICATION"
gitlab_rails['smtp_enable_starttls_auto'] = $SMTP_ENABLE_STARTTLS_AUTO
gitlab_rails['smtp_tls'] = $SMTP_TLS
gitlab_rails['gitlab_email_from'] = "$GITLAB_EMAIL_FROM"
gitlab_rails['gitlab_email_reply_to'] = "$GITLAB_EMAIL_REPLY_TO"
EOF
        
        # Añadir configuración al archivo gitlab.rb
        cat /etc/gitlab/gitlab.rb.email_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.email_config
    fi
}

function configure_database() {
    log_step "Configurando base de datos"
    
    # Solo si no se usa la base de datos por defecto
    if [ "$DB_HOST" != "localhost" ]; then
        cat > /etc/gitlab/gitlab.rb.db_config <<EOF
gitlab_rails['db_adapter'] = "$DB_ADAPTER"
gitlab_rails['db_encoding'] = "utf8"
gitlab_rails['db_host'] = "$DB_HOST"
gitlab_rails['db_port'] = $DB_PORT
gitlab_rails['db_username'] = "$DB_USERNAME"
gitlab_rails['db_password'] = "$DB_PASSWORD"
gitlab_rails['db_database'] = "$DB_NAME"
EOF
        
        # Añadir configuración al archivo gitlab.rb
        cat /etc/gitlab/gitlab.rb.db_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.db_config
    fi
}

function configure_backup() {
    if [ "$BACKUP_ENABLED" = true ]; then
        log_step "Configurando sistema de backup"
        
        # Crear configuración de backup
        cat > /etc/gitlab/gitlab.rb.backup_config <<EOF
gitlab_rails['backup_path'] = "$BACKUP_PATH"
gitlab_rails['backup_keep_time'] = $BACKUP_KEEP_TIME
EOF
        
        # Añadir configuración al archivo gitlab.rb
        cat /etc/gitlab/gitlab.rb.backup_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.backup_config
        
        # Crear directorio de backup si no existe
        mkdir -p "$BACKUP_PATH"
        chmod 700 "$BACKUP_PATH"
        
        # Configurar cronjob para backup diario
        echo "0 2 * * * /opt/gitlab/bin/gitlab-backup create CRON=1" > /etc/cron.d/gitlab-backup
    fi
}

function configure_performance() {
    log_step "Optimizando rendimiento"
    
    # Configuración de Unicorn (servidor web de Rails)
    cat > /etc/gitlab/gitlab.rb.performance_config <<EOF
unicorn['worker_timeout'] = $GITLAB_UNICORN_WORKER_TIMEOUT
unicorn['worker_processes'] = $GITLAB_UNICORN_WORKER_PROCESSES
EOF
    
    # Configuraciones basadas en la memoria disponible
    if [ "$TOTAL_RAM_MB" -lt 4096 ]; then  # Menos de 4GB
        cat >> /etc/gitlab/gitlab.rb.performance_config <<EOF
# Configuración para servidor con menos de 4GB RAM
postgresql['shared_buffers'] = "256MB"
unicorn['worker_memory_limit_min'] = "200*1024"
unicorn['worker_memory_limit_max'] = "300*1024"
sidekiq['concurrency'] = 4
prometheus_monitoring['enable'] = false
EOF
    elif [ "$TOTAL_RAM_MB" -lt 8192 ]; then  # Entre 4GB y 8GB
        cat >> /etc/gitlab/gitlab.rb.performance_config <<EOF
# Configuración para servidor con 4-8GB RAM
postgresql['shared_buffers'] = "512MB"
unicorn['worker_memory_limit_min'] = "300*1024"
unicorn['worker_memory_limit_max'] = "500*1024"
sidekiq['concurrency'] = 6
EOF
    else  # Más de 8GB
        cat >> /etc/gitlab/gitlab.rb.performance_config <<EOF
# Configuración para servidor con más de 8GB RAM
postgresql['shared_buffers'] = "1GB"
unicorn['worker_memory_limit_min'] = "400*1024"
unicorn['worker_memory_limit_max'] = "650*1024"
sidekiq['concurrency'] = 10
EOF
    fi
    
    # Añadir configuración al archivo gitlab.rb
    cat /etc/gitlab/gitlab.rb.performance_config >> /etc/gitlab/gitlab.rb
    rm /etc/gitlab/gitlab.rb.performance_config
}

function configure_storage() {
    if [ "$USE_CUSTOM_STORAGE" = true ] && [ -n "$STORAGE_PATH" ]; then
        log_step "Configurando almacenamiento personalizado"
        
        # Crear directorio de almacenamiento si no existe
        mkdir -p "$STORAGE_PATH"
        chmod 700 "$STORAGE_PATH"
        chown git:git "$STORAGE_PATH"
        
        # Configurar GitLab para usar la ruta personalizada
        cat > /etc/gitlab/gitlab.rb.storage_config <<EOF
# Rutas de almacenamiento personalizado
git_data_dirs({
  "default" => { "path" => "$STORAGE_PATH" }
})
EOF
        
        # Añadir configuración al archivo gitlab.rb
        cat /etc/gitlab/gitlab.rb.storage_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.storage_config
    fi
}

function reconfigure_gitlab() {
    log_step "Reconfigurando GitLab"
    
    # Actualizar la URL externa en gitlab.rb
    sed -i "s|^external_url.*|external_url '$EXTERNAL_URL'|" /etc/gitlab/gitlab.rb
    
    # Ejecutar reconfigure
    gitlab-ctl reconfigure
}

function configure_firewall() {
    log_step "Configurando firewall"
    
    # Verificar si ufw está instalado
    if ! command -v ufw > /dev/null; then
        apt-get install -y ufw
    fi
    
    # Configurar reglas
    ufw allow OpenSSH
    
    if [[ "$EXTERNAL_URL" == *"https://"* ]]; then
        ufw allow https
    else
        ufw allow http
    fi
    
    # Activar firewall si no está activo
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable
    fi
    
    ufw status
}

function verify_installation() {
    log_step "Verificando la instalación"
    
    # Comprobar si los servicios de GitLab están ejecutándose
    gitlab-ctl status
    
    # Obtener la contraseña de root
    log_info "Contraseña inicial para el usuario root:"
    cat /etc/gitlab/initial_root_password
    
    # Crear archivo con información de la instalación
    cat > gitlab_installation_info.txt <<EOF
Instalación de GitLab completada el $(date)

URL de GitLab: $EXTERNAL_URL
Versión: GitLab $GITLAB_VERSION

La contraseña inicial para el usuario root se encuentra en:
/etc/gitlab/initial_root_password
(Válida por 24 horas desde la instalación)

IMPORTANTE: Por favor, inicie sesión y cambie la contraseña inmediatamente.

Configuración de correo: $([ "$SMTP_ENABLED" = true ] && echo "Habilitada" || echo "No configurada")
SSL/TLS: $([ "$USE_SSL" = true ] && echo "Habilitado" || echo "No configurado")
Backup automático: $([ "$BACKUP_ENABLED" = true ] && echo "Habilitado (diario a las 2:00 AM)" || echo "No configurado")

Para administrar GitLab, use el comando 'gitlab-ctl':
- gitlab-ctl status     : Verificar estado de los servicios
- gitlab-ctl reconfigure: Reconfigurar después de cambios
- gitlab-ctl restart    : Reiniciar servicios
- gitlab-ctl backup     : Crear un backup manual

El archivo de configuración principal se encuentra en:
/etc/gitlab/gitlab.rb
EOF
    
    log_info "Se ha creado un archivo con información de la instalación: gitlab_installation_info.txt"
}

function show_banner() {
    echo -e "${GREEN}"
    echo "======================================================================"
    echo "                GitLab Installer para Ubuntu Server 24.04"
    echo "======================================================================"
    echo -e "${NC}"
}

#########################################################################
# Ejecución principal
#########################################################################

show_banner
check_root
check_os
create_config_if_not_exists
load_config
update_system
install_dependencies
configure_postfix
add_gitlab_repository
install_gitlab
configure_ssl
configure_email
configure_database
configure_backup
configure_performance
configure_storage
reconfigure_gitlab
configure_firewall
verify_installation

log_info "Instalación y configuración de GitLab completada exitosamente"
log_info "Acceda a GitLab en: $EXTERNAL_URL"
