#!/bin/bash

# Actualiza el sistema
sudo apt update
sudo apt upgrade -y

# Instala Apache, MariaDB, PHP y extensiones necesarias
sudo apt install -y mariadb-server apache2 php php-cli php-fpm php-json php-xml php-zip php-gd php-mysql php-mbstring php-curl php-intl php-imagick php-bcmath php-gmp

# Configura la base de datos de MariaDB
sudo mysql_secure_installation
sudo mysql -u root -p -e "CREATE DATABASE nextcloud;"
sudo mysql -u root -p -e "CREATE USER 'nextclouduser'@'localhost' IDENTIFIED BY 'T3mp0r4l';"
sudo mysql -u root -p -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextclouduser'@'localhost';"
sudo mysql -u root -p -e "FLUSH PRIVILEGES;"

# Descarga y configura Nextcloud
sudo mkdir /var/www/html/nextcloud
sudo wget https://download.nextcloud.com/server/releases/latest.tar.bz2 -P /tmp
sudo tar -xvjf /tmp/latest.tar.bz2 -C /var/www/html
sudo chown -R www-data:www-data /var/www/html/nextcloud

# Configura Apache
sudo tee /etc/apache2/sites-available/nextcloud.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin admin@tudominio.com
    DocumentRoot /var/www/html/nextcloud/
    ServerName tudominio.com

    <Directory /var/www/html/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

sudo a2ensite nextcloud.conf

# Limpieza
sudo rm /tmp/latest.tar.bz2
sudo rm /etc/apache2/sites-enabled/000-default.conf

sudo systemctl restart apache2

echo "Nextcloud se ha instalado y configurado correctamente."
echo "Accede a través de tu navegador web usando la dirección IP o el nombre de dominio de tu servidor."


