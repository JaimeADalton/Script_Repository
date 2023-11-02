#!/bin/bash

# Instalar dependencias
sudo apt-get update
sudo apt-get install -y mysql-server mysql-client libmysqlclient-dev

# Configurar MySQL
echo "Configurando MySQL..."
sudo service mysql start
/usr/bin/mysqladmin -u root password 'mypassword'

# Crear base de datos para NDOUtils
mysql -u root -p'mypassword' <<EOF
CREATE DATABASE nagios DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER 'ndoutils'@'localhost' IDENTIFIED BY 'ndoutils_password';
GRANT USAGE ON *.* TO 'ndoutils'@'localhost' IDENTIFIED BY 'ndoutils_password';
GRANT ALL PRIVILEGES ON nagios.* TO 'ndoutils'@'localhost';
EOF

# Descargar NDOUtils
cd /tmp
wget -O ndoutils.tar.gz https://github.com/NagiosEnterprises/ndoutils/releases/download/ndoutils-2.1.3/ndoutils-2.1.3.tar.gz
tar xzf ndoutils.tar.gz

# Compilar e instalar NDOUtils
cd /tmp/ndoutils-2.1.3/
./configure
make all
sudo make install

# Inicializar base de datos
cd db/
./installdb -u 'ndoutils' -p 'ndoutils_password' -h 'localhost' -d nagios

# Instalar archivos de configuración
sudo make install-config
sudo mv /usr/local/nagios/etc/ndo2db.cfg-sample /usr/local/nagios/etc/ndo2db.cfg
sudo sed -i 's/^db_user=.*/db_user=ndoutils/g' /usr/local/nagios/etc/ndo2db.cfg
sudo sed -i 's/^db_pass=.*/db_pass=ndoutils_password/g' /usr/local/nagios/etc/ndo2db.cfg
sudo mv /usr/local/nagios/etc/ndomod.cfg-sample /usr/local/nagios/etc/ndomod.cfg

# Configurar Nagios para usar el módulo NDO
echo "broker_module=/usr/local/nagios/bin/ndomod.o config_file=/usr/local/nagios/etc/ndomod.cfg" | sudo tee -a /usr/local/nagios/etc/nagios.cfg

# Reiniciar Nagios
sudo service nagios restart

echo "Instalación completada."
