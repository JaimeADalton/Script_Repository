#!/bin/bash

# Function to install a specific Nagios instance
install_nagios_instance() {
    INSTANCE_NAME=$1
    INSTANCE_PATH=/usr/local/${INSTANCE_NAME}

    # Compiling Nagios
    cd /tmp/nagioscore-nagios-4.4.14/
    sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled --prefix=${INSTANCE_PATH}
    sudo make all
    sudo make install
    sudo make install-daemoninit
    sudo make install-commandmode
    sudo make install-config

    # Installing Apache config files
    sudo make install-webconf
    sudo a2enmod rewrite
    sudo a2enmod cgi

    # Setting up nagiosadmin user for the web interface
    echo "Please enter a password for 'nagiosadmin' for the instance in ${INSTANCE_PATH}:"
    sudo htpasswd -c ${INSTANCE_PATH}/etc/htpasswd.users nagiosadmin

    # Installing Plugins
    cd /tmp/nagios-plugins-release-2.4.6/
    sudo ./tools/setup
    sudo ./configure --prefix=${INSTANCE_PATH}
    sudo make
    sudo make install

    # Starting services
    sudo systemctl restart apache2.service
    sudo systemctl start nagios.service

    echo "Installation of Nagios Core at ${INSTANCE_PATH} completed. Access the web interface at http://[your-ip-address]/nagios with username 'nagiosadmin' and the provided password."
}

# Update and prerequisites
sudo apt-get update
sudo apt-get install -y apache2 autoconf bc build-essential dc gawk gcc gettext libapache2-mod-php7.4 libc6 libgd-dev libmcrypt-dev libnet-snmp-perl libssl-dev make openssl php snmp unzip wget

# Download Nagios Core and Plugins
cd /tmp
wget -O nagioscore.tar.gz https://github.com/NagiosEnterprises/nagioscore/archive/nagios-4.4.14.tar.gz
wget --no-check-certificate -O nagios-plugins.tar.gz https://github.com/nagios-plugins/nagios-plugins/archive/release-2.4.6.tar.gz
tar xzf nagioscore.tar.gz
tar zxf nagios-plugins.tar.gz

# Create user and group
sudo make install-groups-users
sudo usermod -a -G nagios www-data

# Firewall setup
sudo ufw allow Apache
sudo ufw reload


read -p "Nombre de la Instancia de Nagios: " instance_name
install_nagios_instance $instance_name

#Pendiente de revision
#mv /etc/apache2/sites-enabled/nagios.conf /etc/apache2/sites-enabled/${instance_name}.conf
#sed -iE "s/ScriptAlias[[:space:]]\/nagios\/cgi-bin/ScriptAlias\/${instance_name}\/cgi-bin/g" /etc/apache2/sites-enabled/${instance_name}.conf
#sed -iE "s/Alias[[:space:]]\/nagios/Alias\/${instance_name}/g" /etc/apache2/sites-enabled/${instance_name}.conf
#sed -iE "s/\/nagios\/cgi-bin/\/${instance_name}\/cgi-bin/g" /usr/local/${instance_name}/share/config.inc.php
