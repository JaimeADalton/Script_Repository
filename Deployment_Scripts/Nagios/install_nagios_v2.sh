#!/bin/bash

set -eo pipefail # Detiene el script en caso de error

# Define colores para la salida
GREEN='\033[0;32m'
RESET_COLOR='\033[0m'

# Define la IP por la que te has conectado a la maquina
IP_ADDRESS=$(ip route get $(echo $SSH_CLIENT | awk '{print $1}') | head -n 1 | awk '{print $7}')

# Función para mostrar mensajes
echo_green() {
    echo -e "${GREEN}$1${RESET_COLOR}"
}

# Actualizar y instalar prerequisitos
update_and_install_prerequisites() {
    sudo apt-get update
    sudo apt-get install -y apache2 autoconf bc build-essential dc gawk gcc gettext \
    libapache2-mod-php7.4 libc6 libgd-dev libmcrypt-dev libnet-snmp-perl libssl-dev make \
    openssl php snmp unzip wget
}

# Configurar usuario y grupos de Nagios
setup_nagios_user_and_groups() {
    sudo groupadd nagios || true # Ignora si el grupo ya existe
    sudo groupadd nagcmd || true # Igual aquí
    sudo useradd -m -s /bin/bash -g nagios nagios || true
    sudo usermod -a -G nagcmd,nagios,www-data nagios
}

# Descargar e instalar Nagios Core y Plugins
download_and_install_nagios() {
    local nagios_version nagios_plugin_version nagioscore_tar nagios_plugins_tar
    nagios_version=$(curl -s https://github.com/NagiosEnterprises/nagioscore/releases | grep "f1 text-bold d-inline mr-3" | head -n 1 | awk -F">" '{print $3}' | awk -F "<" '{print $1}'| sed -e 's/Release\ //')
    nagios_plugin_version=$(curl -s https://github.com/nagios-plugins/nagios-plugins/releases | grep '<h2 class="sr-only"' | head -n 1 | awk -F ">" '{print $2}' | awk -F "<" '{print $1}' | sed -E 's/Nagios\ Plugins\ //' | sed -E 's/\ Released//')
    nagioscore_tar="/tmp/nagioscore.tar.gz"
    nagios_plugins_tar="/tmp/nagios-plugins.tar.gz"

    wget -O "${nagioscore_tar}" "https://github.com/NagiosEnterprises/nagioscore/archive/nagios-${nagios_version}.tar.gz"
    wget --no-check-certificate -O "${nagios_plugins_tar}" "https://github.com/nagios-plugins/nagios-plugins/archive/release-${nagios_plugin_version}.tar.gz"

    tar xzf "${nagioscore_tar}" -C /tmp
    tar zxf "${nagios_plugins_tar}" -C /tmp

    local instance_name instance_path
    read -pe "${GREEN}Nombre de la Instancia de Nagios: ${RESET_COLOR}" instance_name
    instance_path="/usr/local/${instance_name}"

    # Compilación e instalación de Nagios Core
    (cd /tmp/nagioscore-nagios-${nagios_version}/ && sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled --prefix="${instance_path}" && sudo make all && sudo make install && sudo make install-daemoninit && sudo make install-commandmode && sudo make install-config)

    # Compilación e instalación de Nagios Plugins
    (cd /tmp/nagios-plugins-release-${nagios_plugin_version}/ && sudo ./tools/setup && sudo ./configure --prefix="${instance_path}" && sudo make && sudo make install)
}

# Configurar Apache y firewall
configure_apache_and_firewall() {
    sudo a2enmod rewrite cgi
    sudo ufw allow Apache
    sudo ufw allow ssh
    sudo ufw reload
}

# Configurar acceso web de Nagios
setup_web_access() {
    local instance_path="$1"
    sudo make install-webconf
    echo_green "Please enter a password for 'nagiosadmin' for the instance in ${instance_path}:"
    sudo htpasswd -c "${instance_path}/etc/htpasswd.users" nagiosadmin
}

# Iniciar servicios
start_services() {
    sudo systemctl restart apache2.service
    sudo systemctl start nagios.service
}

main() {
    update_and_install_prerequisites
    setup_nagios_user_and_groups
    download_and_install_nagios
    configure_apache_and_firewall
    setup_web_access "${instance_path}"
    start_services
    echo_green "Installation of Nagios Core at ${instance_path} completed. Access the web interface at http://${IP_ADDRESS}/nagios with username 'nagiosadmin' and the provided password."
}

main "$@"
