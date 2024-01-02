#!/bin/bash

# Actualizar lista de paquetes y actualizar el sistema
sudo apt-get update
sudo apt-get upgrade -y

# Instalar Apache, MySQL y PHP junto con las extensiones necesarias
sudo apt install -y graphviz aspell ghostscript clamav git vim apache2 mysql-client mysql-server php8.1 libapache2-mod-php graphviz aspell ghostscript clamav php8.1-pspell php8.1-curl php8.1-gd php8.1-intl php8.1-mysql php8.1-xml php8.1-xmlrpc php8.1-ldap php8.1-zip php8.1-soap php8.1-mbstring

# Configurar MySQL (asignar contraseñas de forma segura en producción)
sudo mysql_secure_installation

# Crear base de datos Moodle y usuario
DB_PASSWORD="passwordformoodledude" # Cambiar por una contraseña segura
DB_USER="moodledude"
sudo mysql -e "CREATE DATABASE moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -e "GRANT ALL ON moodle.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Descargar Moodle
cd /opt
sudo git clone git://git.moodle.org/moodle.git
cd moodle

# Obtener la ultima version de Git
GIT_BRANCH=$(sudo git branch -a | grep -vE 'main|master' | tail -n 1 | cut -d "_" -f 2)

# Descargar la ultima version de Moodle 
sudo git branch --track MOODLE_${GIT_BRANCH}_STABLE origin/MOODLE_${GIT_BRANCH}_STABLE
sudo git checkout MOODLE_${GIT_BRANCH}_STABLE

# Copiar Moodle al directorio web
sudo cp -R /opt/moodle /var/www/html/
sudo mkdir /var/moodledata
sudo chown -R www-data /var/moodledata
sudo chmod -R 0777 /var/moodledata
sudo chmod -R 0755 /var/www/html/moodle

# Habilitar para apache php8.1
sudo a2enmod php8.1

# Reiniciar Apache para cargar la configuración
sudo service apache2 restart

# Cambiar los permisos de Moodle después de la instalación
sudo chmod -R 0755 /var/www/html/moodle

# Instrucciones finales
echo "Moodle ha sido instalado. Accede a la URL de tu servidor para completar la configuración."
