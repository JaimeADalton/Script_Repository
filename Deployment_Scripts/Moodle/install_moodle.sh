#!/bin/bash

# Actualizar lista de paquetes y actualizar el sistema
sudo apt-get update
sudo apt-get upgrade -y

sudo add-apt-repository ppa:ondrej/php

# Instalar Apache, MySQL y PHP junto con las extensiones necesarias
sudo apt-get install -y apache2 mysql-client mysql-server php7.4 libapache2-mod-php php7.4-pspell php7.4-curl php7.4-gd php7.4-intl php7.4-mysql php7.4-xml php7.4-xmlrpc php7.4-ldap php7.4-zip php7.4-soap php7.4-mbstring

# Instalar herramientas adicionales
sudo apt-get install -y graphviz aspell ghostscript clamav git vim

# Configurar MySQL (asignar contraseñas de forma segura en producción)
sudo mysql_secure_installation

# Configurar MySQL para Moodle
echo "default_storage_engine = innodb" >> /etc/mysql/mysql.conf.d/mysqld.cnf
echo "innodb_file_per_table = 1" >> /etc/mysql/mysql.conf.d/mysqld.cnf
echo "innodb_file_format = Barracuda" >> /etc/mysql/mysql.conf.d/mysqld.cnf
sudo service mysql restart

# Crear base de datos Moodle y usuario
DB_PASSWORD="passwordformoodledude" # Cambiar por una contraseña segura
sudo mysql -e "CREATE DATABASE moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER 'moodledude'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL ON moodle.* TO 'moodledude'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Descargar Moodle
cd /opt
sudo git clone git://git.moodle.org/moodle.git
cd moodle
sudo git branch --track MOODLE_400_STABLE origin/MOODLE_400_STABLE
sudo git checkout MOODLE_400_STABLE

# Copiar Moodle al directorio web
sudo cp -R /opt/moodle /var/www/html/
sudo mkdir /var/moodledata
sudo chown -R www-data /var/moodledata
sudo chmod -R 0777 /var/moodledata
sudo chmod -R 0755 /var/www/html/moodle

# Reiniciar Apache para cargar la configuración
sudo service apache2 restart

# Cambiar los permisos de Moodle después de la instalación
sudo chmod -R 0755 /var/www/html/moodle

# Instrucciones finales
echo "Moodle ha sido instalado. Accede a la URL de tu servidor para completar la configuración."
