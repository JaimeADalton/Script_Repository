#!/bin/bash -x

# Mejora el manejo de errores y el registro de progreso
set -eo pipefail

# Define colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET_COLOR='\033[0m'

# Define la IP por la que te has conectado a la máquina
IP_ADDRESS=$(ip route get $(echo $SSH_CLIENT | awk '{print $1}') | head -n 1 | awk '{print $7}')

# Archivo de registro
LOG_FILE="/tmp/nagios_install_$(date +%Y%m%d_%H%M%S).log"

# Función para mostrar mensajes y registrarlos
log_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${RESET_COLOR}" | tee -a "$LOG_FILE"
}

# Función para ejecutar comandos con registro y manejo de errores
run_command() {
    local command="$1"
    local error_message="$2"

    if ! eval "$command" >> "$LOG_FILE" 2>&1; then
        log_message "$RED" "ERROR: $error_message"
        log_message "$YELLOW" "Consulte el archivo de registro $LOG_FILE para más detalles."
        exit 1
    fi
}

# Actualizar y instalar prerequisitos
update_and_install_prerequisites() {
    log_message "$GREEN" "Actualizando e instalando prerequisitos..."
    run_command "sudo apt-get update" "No se pudo actualizar la lista de paquetes"
    run_command "sudo apt-get install -y apache2 autoconf bc build-essential dc gawk gcc gettext libapache2-mod-php7.4 libc6 libgd-dev libmcrypt-dev libnet-snmp-perl libssl-dev make openssl php snmp unzip wget" "No se pudieron instalar los paquetes necesarios"
}

# Configurar usuario y grupos de Nagios
setup_nagios_user_and_groups() {
    log_message "$GREEN" "Configurando usuario y grupos de Nagios..."

    # Crear grupo nagios
    if ! getent group nagios > /dev/null 2>&1; then
        run_command "sudo groupadd nagios" "No se pudo crear el grupo nagios"
    else
        log_message "$YELLOW" "El grupo nagios ya existe. Continuando..."
    fi

    # Crear grupo nagcmd
    if ! getent group nagcmd > /dev/null 2>&1; then
        run_command "sudo groupadd nagcmd" "No se pudo crear el grupo nagcmd"
    else
        log_message "$YELLOW" "El grupo nagcmd ya existe. Continuando..."
    fi

    # Crear usuario nagios
    if ! id -u nagios > /dev/null 2>&1; then
        run_command "sudo useradd -m -s /bin/bash -g nagios nagios" "No se pudo crear el usuario nagios"
    else
        log_message "$YELLOW" "El usuario nagios ya existe. Continuando..."
    fi

    # Añadir usuario nagios a los grupos necesarios
    run_command "sudo usermod -a -G nagcmd,nagios,www-data nagios" "No se pudo modificar los grupos del usuario nagios"

    log_message "$GREEN" "Configuración de usuario y grupos de Nagios completada."
}

# Descargar Nagios Core y Plugins
download_nagios() {
    log_message "$GREEN" "Descargando Nagios Core y Plugins..."
    local nagios_version nagios_plugin_version nagioscore_tar nagios_plugins_tar

    nagios_version=$(curl -s https://github.com/NagiosEnterprises/nagioscore/releases | grep -oP '(?<=tag/nagios-)[\d.]+' | head -n 1)
    nagios_plugin_version=$(curl -s https://github.com/nagios-plugins/nagios-plugins/releases | grep -oP '(?<=tag/release-)[\d.]+' | head -n 1)

    if [[ -z "$nagios_version" || -z "$nagios_plugin_version" ]]; then
        log_message "$RED" "Error: No se pudieron obtener las versiones de Nagios Core o Nagios Plugins."
        exit 1
    fi

    nagioscore_tar="/tmp/nagioscore.tar.gz"
    nagios_plugins_tar="/tmp/nagios-plugins.tar.gz"

    run_command "wget -O \"${nagioscore_tar}\" \"https://github.com/NagiosEnterprises/nagioscore/archive/nagios-${nagios_version}.tar.gz\"" "No se pudo descargar Nagios Core"
    run_command "wget --no-check-certificate -O \"${nagios_plugins_tar}\" \"https://github.com/nagios-plugins/nagios-plugins/archive/release-${nagios_plugin_version}.tar.gz\"" "No se pudo descargar Nagios Plugins"

    run_command "tar xzf \"${nagioscore_tar}\" -C /tmp" "No se pudo descomprimir Nagios Core"
    run_command "tar zxf \"${nagios_plugins_tar}\" -C /tmp" "No se pudo descomprimir Nagios Plugins"

    echo "${nagios_version}:${nagios_plugin_version}"
}

# Instalar Nagios Core y Plugins
install_nagios() {
    local nagios_version="$1"
    local nagios_plugin_version="$2"
    local instance_name="$3"
    local instance_path="/usr/local/${instance_name}"

    log_message "$GREEN" "Compilando e instalando Nagios Core..."
    run_command "(cd /tmp/nagioscore-nagios-${nagios_version}/ && sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled --prefix=\"${instance_path}\" && sudo make all && sudo make install && sudo make install-daemoninit && sudo make install-commandmode && sudo make install-config)" "No se pudo compilar o instalar Nagios Core"

    log_message "$GREEN" "Compilando e instalando Nagios Plugins..."
    run_command "(cd /tmp/nagios-plugins-release-${nagios_plugin_version}/ && sudo ./tools/setup && sudo ./configure --prefix=\"${instance_path}\" && sudo make && sudo make install)" "No se pudo compilar o instalar Nagios Plugins"

    echo "${instance_path}"
}

# Configurar Apache y firewall
configure_apache_and_firewall() {
    log_message "$GREEN" "Configurando Apache y firewall..."
    run_command "sudo a2enmod rewrite cgi" "No se pudieron habilitar los módulos de Apache"
    run_command "sudo ufw allow Apache" "No se pudo configurar el firewall para Apache"
    run_command "sudo ufw allow ssh" "No se pudo configurar el firewall para SSH"
    run_command "sudo ufw reload" "No se pudo recargar el firewall"
}

# Configurar acceso web de Nagios
setup_web_access() {
    local instance_path="$1"
    local nagios_version="$2"
    log_message "$GREEN" "Configurando acceso web de Nagios..."
    run_command "cd /tmp/nagioscore-nagios-${nagios_version} && sudo make install-webconf" "No se pudo instalar la configuración web"
    log_message "$GREEN" "Por favor, ingrese una contraseña para 'nagiosadmin' para la instancia en ${instance_path}:"
    run_command "sudo htpasswd -c \"${instance_path}/etc/htpasswd.users\" nagiosadmin" "No se pudo crear el usuario web de Nagios"
}

# Iniciar servicios
start_services() {
    log_message "$GREEN" "Iniciando servicios..."
    run_command "sudo systemctl restart apache2.service" "No se pudo reiniciar Apache"
    run_command "sudo systemctl start nagios.service" "No se pudo iniciar Nagios"
}

main() {
    log_message "$GREEN" "Iniciando la instalación de Nagios..."

    update_and_install_prerequisites
    setup_nagios_user_and_groups

    log_message "$GREEN" "Comenzando la descarga de Nagios..."
    local download_info
    download_info=$(download_nagios)
    local nagios_version nagios_plugin_version
    nagios_version=$(echo "$download_info" | cut -d':' -f1 | tail -n 1)
    nagios_plugin_version=$(echo "$download_info" | cut -d':' -f2 | tail -n 1)

    while true; do
        log_message "$GREEN" "Nombre de la Instancia de Nagios (solo letras, números, guiones y guiones bajos):"
        read -p "Nombre de la Instancia de Nagios: " instance_name
        if [[ "$instance_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            log_message "$RED" "El nombre de la instancia contiene caracteres no permitidos. Por favor, intente nuevamente."
        fi
    done

    local instance_path
    instance_path=$(install_nagios "$nagios_version" "$nagios_plugin_version" "$instance_name"| tail -n 1)

    log_message "$GREEN" "Configurando Apache y firewall..."
    configure_apache_and_firewall

    log_message "$GREEN" "Configurando acceso web de Nagios..."
    setup_web_access "${instance_path}" "${nagios_version}"

    log_message "$GREEN" "Iniciando servicios..."
    start_services

    log_message "$GREEN" "Instalación de Nagios Core en ${instance_path} completada."
    log_message "$GREEN" "Acceda a la interfaz web en http://${IP_ADDRESS}/nagios con el usuario 'nagiosadmin' y la contraseña proporcionada."
    log_message "$YELLOW" "Para más detalles sobre la instalación, consulte el archivo de registro: $LOG_FILE"
}
main "$@"
