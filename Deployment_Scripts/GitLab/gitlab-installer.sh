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

# Verificación del nombre de host - deshabilitar si el servidor no es accesible públicamente
# o si está utilizando un nombre de host interno no resuelto por DNS público
CHECK_HOSTNAME_DNS=true

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

# Configuración de Puma (servidor web moderno que reemplaza a Unicorn)
# Estos valores se ajustarán automáticamente según el hardware disponible
PUMA_WORKERS=0  # 0 = automático basado en CPU
PUMA_MAX_THREADS=4
PUMA_MIN_THREADS=1

# Configuración de rendimiento de Unicorn (para compatibilidad con versiones anteriores)
GITLAB_UNICORN_WORKER_TIMEOUT=60
GITLAB_UNICORN_WORKER_PROCESSES=3

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

function fix_dpkg_error() {
    log_step "Verificando estado de paquetes"

    if dpkg -l | grep gitlab-ce | grep -q "^iF"; then
        log_warn "Paquete gitlab-ce en estado incompleto, intentando reparar..."
        dpkg --configure -a

        if dpkg -l | grep gitlab-ce | grep -q "^iF"; then
            log_warn "Reconstruyendo el paquete gitlab-ce..."
            apt-get -f install -y

            if dpkg -l | grep gitlab-ce | grep -q "^ii"; then
                log_info "Paquete gitlab-ce reparado correctamente"
            else
                log_error "No se pudo reparar el paquete gitlab-ce automáticamente"
                log_error "Intente ejecutar manualmente: sudo dpkg --configure -a && sudo apt-get -f install"
            fi
        fi
    else
        log_info "Estado de paquetes correcto"
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

    # Establecer valores predeterminados para variables numéricas
    PUMA_WORKERS=${PUMA_WORKERS:-0}
    PUMA_MAX_THREADS=${PUMA_MAX_THREADS:-4}
    PUMA_MIN_THREADS=${PUMA_MIN_THREADS:-1}
    GITLAB_UNICORN_WORKER_TIMEOUT=${GITLAB_UNICORN_WORKER_TIMEOUT:-60}
    GITLAB_UNICORN_WORKER_PROCESSES=${GITLAB_UNICORN_WORKER_PROCESSES:-3}

    source "$CONFIG_FILE"

    # Asegurar valores válidos
    PUMA_WORKERS=${PUMA_WORKERS:-0}
    PUMA_MAX_THREADS=${PUMA_MAX_THREADS:-4}
    PUMA_MIN_THREADS=${PUMA_MIN_THREADS:-1}
    GITLAB_UNICORN_WORKER_TIMEOUT=${GITLAB_UNICORN_WORKER_TIMEOUT:-60}
    GITLAB_UNICORN_WORKER_PROCESSES=${GITLAB_UNICORN_WORKER_PROCESSES:-3}

    if [ "$PUMA_WORKERS" -eq 0 ]; then
        PUMA_WORKERS=$((CPU_CORES + 1))
        if [ "$PUMA_WORKERS" -lt 2 ]; then
            PUMA_WORKERS=2
        elif [ "$PUMA_WORKERS" -gt 16 ]; then
            PUMA_WORKERS=16
        fi
        log_info "Número de trabajadores Puma ajustado automáticamente a $PUMA_WORKERS"
    fi

    if [[ "$EXTERNAL_URL" != http://* ]] && [[ "$EXTERNAL_URL" != https://* ]]; then
        log_error "URL externa inválida: $EXTERNAL_URL. Debe comenzar con http:// o https://"
        log_warn "Corrigiendo automáticamente a http://$EXTERNAL_URL"
        EXTERNAL_URL="http://$EXTERNAL_URL"
    fi

    EXTERNAL_URL=$(echo "$EXTERNAL_URL" | sed 's/\/$//')
    log_info "URL externa configurada: $EXTERNAL_URL"

    if [[ "$EXTERNAL_URL" == https://* ]]; then
        USE_SSL=true
        log_info "SSL habilitado automáticamente basado en URL HTTPS"
    elif [[ "$EXTERNAL_URL" == http://* ]] && [ "$USE_SSL" = true ]; then
        log_warn "URL en HTTP pero SSL habilitado - cambiando URL a HTTPS"
        EXTERNAL_URL=$(echo "$EXTERNAL_URL" | sed 's/^http:/https:/')
    fi

    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        log_info "Contraseña de base de datos generada automáticamente"
    fi

    CHECK_HOSTNAME_DNS=${CHECK_HOSTNAME_DNS:-true}
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
    debconf-set-selections <<< "postfix postfix/mailname string $(echo $EXTERNAL_URL | sed 's|^http[s]*://||')"
    debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
    apt-get install -y --reinstall postfix
}

function add_gitlab_repository() {
    log_step "Agregando repositorio GitLab"
    curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-${GITLAB_VERSION}/script.deb.sh | bash
}

function install_gitlab() {
    log_step "Instalando GitLab"
    cat > /tmp/gitlab_pre_install.rb <<EOF
# Configuración básica
external_url '${EXTERNAL_URL}'

# Desactivar explícitamente Let's Encrypt
letsencrypt['enable'] = false
EOF

    export GITLAB_OMNIBUS_CONFIG="$(cat /tmp/gitlab_pre_install.rb)"
    log_info "Configuración pre-instalación creada en /tmp/gitlab_pre_install.rb"
    DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-${GITLAB_VERSION}

    if [ $? -ne 0 ]; then
        log_warn "La instalación de GitLab encontró errores, intentando reparar..."
        fix_dpkg_error
    fi

    rm /tmp/gitlab_pre_install.rb

    if ! dpkg -l | grep gitlab-${GITLAB_VERSION} | grep -q "^ii"; then
        log_error "La instalación de GitLab falló"
        exit 1
    fi

    log_info "GitLab instalado correctamente"
}

function configure_ssl() {
    if [ "$USE_SSL" = true ]; then
        log_step "Configurando SSL/TLS"
        if [ "$USE_LETSENCRYPT" = true ]; then
            log_info "Configurando Let's Encrypt"
            letsencrypt_domain=$(echo $EXTERNAL_URL | sed 's|^http[s]*://||' | sed 's|/.*$||')
            if [ "$CHECK_HOSTNAME_DNS" = true ]; then
                log_info "Verificando registros DNS para $letsencrypt_domain..."
                if ! host $letsencrypt_domain > /dev/null 2>&1; then
                    log_error "No se encontraron registros DNS válidos para $letsencrypt_domain"
                    log_error "Para usar Let's Encrypt, el dominio debe tener registros A o AAAA válidos y ser accesible públicamente"
                    log_error "Considere establecer CHECK_HOSTNAME_DNS=false si está en un entorno de prueba"
                    log_error "Deshabilitando Let's Encrypt y continuando con HTTP..."
                    EXTERNAL_URL=$(echo $EXTERNAL_URL | sed 's|^https://|http://|')
                    log_warn "Cambiando a $EXTERNAL_URL para continuar la instalación"
                    USE_SSL=false
                    cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Desactivar Let's Encrypt
letsencrypt['enable'] = false
EOF
                    cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
                    rm /etc/gitlab/gitlab.rb.ssl_config
                    return
                fi
            fi

            cat > /etc/gitlab/gitlab.rb.letsencrypt_config <<EOF
# Configuración Let's Encrypt
letsencrypt['enable'] = true
letsencrypt['contact_emails'] = ['${LETSENCRYPT_EMAIL:-admin@example.com}']
letsencrypt['auto_renew'] = true
letsencrypt['auto_renew_hour'] = 3
letsencrypt['auto_renew_minute'] = 30
letsencrypt['auto_renew_day_of_month'] = "*/7"
EOF
            cat /etc/gitlab/gitlab.rb.letsencrypt_config >> /etc/gitlab/gitlab.rb
            rm /etc/gitlab/gitlab.rb.letsencrypt_config

        elif [ -n "$SSL_CERT_PATH" ] && [ -n "$SSL_KEY_PATH" ]; then
            log_info "Usando certificados SSL existentes"
            if [ ! -f "$SSL_CERT_PATH" ]; then
                log_error "El archivo de certificado no existe: $SSL_CERT_PATH"
                log_warn "Deshabilitando SSL y continuando con HTTP..."
                EXTERNAL_URL=$(echo $EXTERNAL_URL | sed 's|^https://|http://|')
                USE_SSL=false
                cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Desactivar Let's Encrypt
letsencrypt['enable'] = false
EOF
                cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
                rm /etc/gitlab/gitlab.rb.ssl_config
                return
            fi

            if [ ! -f "$SSL_KEY_PATH" ]; then
                log_error "El archivo de clave privada no existe: $SSL_KEY_PATH"
                log_warn "Deshabilitando SSL y continuando con HTTP..."
                EXTERNAL_URL=$(echo $EXTERNAL_URL | sed 's|^https://|http://|')
                USE_SSL=false
                cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Desactivar Let's Encrypt
letsencrypt['enable'] = false
EOF
                cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
                rm /etc/gitlab/gitlab.rb.ssl_config
                return
            fi

            mkdir -p /etc/gitlab/ssl
            ssl_domain=$(echo $EXTERNAL_URL | sed 's|^http[s]*://||' | sed 's|/.*$||')
            log_info "Certificado: $SSL_CERT_PATH"
            log_info "Clave: $SSL_KEY_PATH"
            log_info "Dominio: $ssl_domain"
            cp -v "$SSL_CERT_PATH" "/etc/gitlab/ssl/$ssl_domain.crt"
            cp -v "$SSL_KEY_PATH" "/etc/gitlab/ssl/$ssl_domain.key"
            if [ ! -f "/etc/gitlab/ssl/$ssl_domain.crt" ] || [ ! -f "/etc/gitlab/ssl/$ssl_domain.key" ]; then
                log_error "Error al copiar los certificados SSL"
                log_warn "Deshabilitando SSL y continuando con HTTP..."
                EXTERNAL_URL=$(echo $EXTERNAL_URL | sed 's|^https://|http://|')
                USE_SSL=false
                return
            fi
            chmod 600 /etc/gitlab/ssl/*
            log_info "Certificados copiados a /etc/gitlab/ssl/"
            cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Configuración manual de SSL
nginx['ssl_certificate'] = "/etc/gitlab/ssl/$ssl_domain.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/$ssl_domain.key"
nginx['redirect_http_to_https'] = true
letsencrypt['enable'] = false
EOF
            cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
            rm /etc/gitlab/gitlab.rb.ssl_config
            log_info "GitLab configurado para usar certificados SSL manuales"
        else
            log_warn "SSL habilitado pero no se proporcionaron rutas de certificados y Let's Encrypt está desactivado"
            log_warn "Deshabilitando SSL y continuando con HTTP..."
            EXTERNAL_URL=$(echo $EXTERNAL_URL | sed 's|^https://|http://|')
            USE_SSL=false
            cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Desactivar Let's Encrypt
letsencrypt['enable'] = false
EOF
            cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
            rm /etc/gitlab/gitlab.rb.ssl_config
        fi
    else
        cat > /etc/gitlab/gitlab.rb.ssl_config <<EOF
# Desactivar Let's Encrypt ya que no se usa SSL
letsencrypt['enable'] = false
EOF
        cat /etc/gitlab/gitlab.rb.ssl_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.ssl_config
    fi
}

function configure_email() {
    if [ "$SMTP_ENABLED" = true ]; then
        log_step "Configurando correo electrónico"
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
        cat /etc/gitlab/gitlab.rb.email_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.email_config
    fi
}

function configure_database() {
    log_step "Configurando base de datos"
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
        cat /etc/gitlab/gitlab.rb.db_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.db_config
    fi
}

function configure_backup() {
    if [ "$BACKUP_ENABLED" = true ]; then
        log_step "Configurando sistema de backup"
        cat > /etc/gitlab/gitlab.rb.backup_config <<EOF
gitlab_rails['backup_path'] = "$BACKUP_PATH"
gitlab_rails['backup_keep_time'] = $BACKUP_KEEP_TIME
EOF
        cat /etc/gitlab/gitlab.rb.backup_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.backup_config
        mkdir -p "$BACKUP_PATH"
        chmod 700 "$BACKUP_PATH"
        echo "0 2 * * * /opt/gitlab/bin/gitlab-backup create CRON=1" > /etc/cron.d/gitlab-backup
    fi
}

function configure_performance() {
    log_step "Optimizando rendimiento"
    if [ "$TOTAL_RAM_MB" -lt 4096 ]; then
        cat > /etc/gitlab/gitlab.rb.performance_config <<EOF
# Servidor con menos de 4GB RAM
postgresql['shared_buffers'] = "256MB"
puma['worker_processes'] = 2
puma['min_threads'] = 1
puma['max_threads'] = 4
sidekiq['concurrency'] = 4
prometheus_monitoring['enable'] = false
EOF
    elif [ "$TOTAL_RAM_MB" -lt 8192 ]; then
        cat > /etc/gitlab/gitlab.rb.performance_config <<EOF
# Servidor con 4-8GB RAM
postgresql['shared_buffers'] = "512MB"
puma['worker_processes'] = $PUMA_WORKERS
puma['min_threads'] = $PUMA_MIN_THREADS
puma['max_threads'] = $PUMA_MAX_THREADS
sidekiq['concurrency'] = 6
EOF
    else
        cat > /etc/gitlab/gitlab.rb.performance_config <<EOF
# Servidor con más de 8GB RAM
postgresql['shared_buffers'] = "1GB"
puma['worker_processes'] = $PUMA_WORKERS
puma['min_threads'] = $PUMA_MIN_THREADS
puma['max_threads'] = $PUMA_MAX_THREADS
sidekiq['concurrency'] = 10
EOF
    fi
    cat /etc/gitlab/gitlab.rb.performance_config >> /etc/gitlab/gitlab.rb
    rm /etc/gitlab/gitlab.rb.performance_config
}

function configure_storage() {
    if [ "$USE_CUSTOM_STORAGE" = true ] && [ -n "$STORAGE_PATH" ]; then
        log_step "Configurando almacenamiento personalizado"
        mkdir -p "$STORAGE_PATH"
        chmod 700 "$STORAGE_PATH"
        chown git:git "$STORAGE_PATH"
        cat > /etc/gitlab/gitlab.rb.storage_config <<EOF
# Almacenamiento personalizado
gitaly['storage'] = [
  {
    'name' => 'default',
    'path' => '$STORAGE_PATH'
  }
]
EOF
        cat /etc/gitlab/gitlab.rb.storage_config >> /etc/gitlab/gitlab.rb
        rm /etc/gitlab/gitlab.rb.storage_config
    fi
}

function configure_firewall() {
    log_step "Configurando firewall"
    if ! command -v ufw > /dev/null; then
        apt-get install -y ufw
    fi
    ufw allow OpenSSH
    if [[ "$EXTERNAL_URL" == *"https://"* ]]; then
        ufw allow https
    else
        ufw allow http
    fi
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable
    fi
    ufw status
}

function verify_installation() {
    log_step "Verificando la instalación"
    gitlab-ctl status
    log_info "Contraseña inicial para el usuario root:"
    cat /etc/gitlab/initial_root_password
    cat > gitlab_installation_info.txt <<EOF
Instalación de GitLab completada el $(date)

URL de GitLab: $EXTERNAL_URL
Versión: GitLab ${GITLAB_VERSION}

La contraseña inicial para el usuario root se encuentra en:
/etc/gitlab/initial_root_password
(Válida por 24 horas desde la instalación)

IMPORTANTE: Inicie sesión y cambie la contraseña inmediatamente.

Correo: $([ "$SMTP_ENABLED" = true ] && echo "Habilitada" || echo "No configurada")
SSL/TLS: $([ "$USE_SSL" = true ] && echo "Habilitado" || echo "No configurado")
Backup: $([ "$BACKUP_ENABLED" = true ] && echo "Habilitado (diario a las 2:00 AM)" || echo "No configurado")

Para administrar GitLab, use:
- gitlab-ctl status
- gitlab-ctl reconfigure
- gitlab-ctl restart
- gitlab-ctl backup

El archivo de configuración se encuentra en:
/etc/gitlab/gitlab.rb
EOF
    log_info "Archivo con información de la instalación creado: gitlab_installation_info.txt"
}

function show_banner() {
    echo -e "${GREEN}"
    echo "======================================================================"
    echo "                GitLab Installer para Ubuntu Server 24.04"
    echo "======================================================================"
    echo -e "${NC}"
}

function reconfigure_gitlab() {
    log_step "Reconfigurando GitLab"
    if [ -f /etc/gitlab/gitlab.rb ]; then
        cp -f /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.bak.$(date +%Y%m%d%H%M%S)
        log_info "Backup creado: /etc/gitlab/gitlab.rb.bak.$(date +%Y%m%d%H%M%S)"
    fi

    if [ -f /etc/gitlab/gitlab.rb ]; then
        log_info "Eliminando configuraciones obsoletas de Unicorn"
        sed -i '/^unicorn\[/d' /etc/gitlab/gitlab.rb
    fi

    sed -i "s|^external_url.*|external_url '${EXTERNAL_URL}'|" /etc/gitlab/gitlab.rb

    if grep -q "letsencrypt\['enable'\]" /etc/gitlab/gitlab.rb; then
        if [ "$USE_LETSENCRYPT" = true ]; then
            sed -i "s|^letsencrypt\['enable'\].*|letsencrypt['enable'] = true|" /etc/gitlab/gitlab.rb
        else
            sed -i "s|^letsencrypt\['enable'\].*|letsencrypt['enable'] = false|" /etc/gitlab/gitlab.rb
        fi
    else
        if [ "$USE_LETSENCRYPT" = true ]; then
            echo "letsencrypt['enable'] = true" >> /etc/gitlab/gitlab.rb
        else
            echo "letsencrypt['enable'] = false" >> /etc/gitlab/gitlab.rb
        fi
    fi

    log_info "Ejecutando gitlab-ctl reconfigure..."
    if ! gitlab-ctl reconfigure; then
        log_warn "Reconfiguración inicial fallida, intentando enfoque alternativo..."
        fix_dpkg_error
        cat > /tmp/gitlab_minimal.rb <<EOF
# Configuración mínima para recuperación
external_url '${EXTERNAL_URL}'
letsencrypt['enable'] = false
EOF
        cp -f /tmp/gitlab_minimal.rb /etc/gitlab/gitlab.rb
        rm /tmp/gitlab_minimal.rb
        if ! gitlab-ctl reconfigure; then
            log_error "Reconfiguración mínima fallida. Revise /var/log/gitlab/reconfigure/"
            exit 1
        else
            log_info "Reconfiguración mínima exitosa. Restaurando configuración completa..."
            configure_ssl
            configure_database
            configure_backup
            configure_performance
            log_info "Ejecutando reconfigure final..."
            if ! gitlab-ctl reconfigure; then
                log_error "Reconfiguración final fallida. GitLab funcionará con configuración mínima."
            else
                log_info "Reconfiguración final exitosa"
            fi
        fi
    fi
}

#########################################################################
# Inicio del script
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
configure_firewall
reconfigure_gitlab
verify_installation
