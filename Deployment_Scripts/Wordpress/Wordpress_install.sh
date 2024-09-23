#!/bin/bash

# Script para instalar WordPress en Ubuntu 22.04

# Variables de configuración
DB_ROOT_PASSWORD="root_password"      # Cambia esta contraseña para el usuario root de MySQL
DB_NAME="wordpress_db"
DB_USER="wordpress_user"
DB_PASSWORD="db_password"             # Cambia esta contraseña para el usuario de WordPress
SITE_URL="localhost"                  # Cambia si vas a usar un dominio

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update -y && sudo apt upgrade -y

# Instalar Apache
echo "Instalando Apache..."
sudo apt install apache2 -y

# Habilitar Apache al inicio y arrancar el servicio
sudo systemctl enable apache2
sudo systemctl start apache2

# Instalar MySQL
echo "Instalando MySQL..."
sudo apt install mysql-server -y

# Configurar contraseña root de MySQL y ajustes de seguridad
echo "Configurando MySQL..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASSWORD';"
sudo mysql -e "FLUSH PRIVILEGES;"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "DROP DATABASE IF EXISTS test;"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# Crear base de datos y usuario para WordPress
echo "Creando base de datos y usuario para WordPress..."
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -uroot -p$DB_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# Instalar PHP y extensiones necesarias
echo "Instalando PHP y extensiones..."
sudo apt install php libapache2-mod-php php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl -y

# Configurar Apache para preferir archivos PHP
echo "Configurando Apache para que priorice archivos PHP..."
sudo sed -i "s/DirectoryIndex index.html/DirectoryIndex index.php index.html/g" /etc/apache2/mods-enabled/dir.conf

# Reiniciar Apache para aplicar cambios
sudo systemctl restart apache2

# Descargar WordPress
echo "Descargando WordPress..."
cd /tmp
wget https://wordpress.org/latest.tar.gz

# Extraer WordPress
echo "Extrayendo WordPress..."
tar -xzvf latest.tar.gz

# Copiar archivos de WordPress al directorio web
echo "Copiando archivos de WordPress al directorio web..."
sudo rsync -avP /tmp/wordpress/ /var/www/html/

# Configurar permisos
echo "Configurando permisos..."
sudo chown -R www-data:www-data /var/www/html/
sudo find /var/www/html/ -type d -exec chmod 755 {} \;
sudo find /var/www/html/ -type f -exec chmod 644 {} \;

# Configurar archivo wp-config.php
echo "Configurando archivo wp-config.php..."
cd /var/www/html/
sudo cp wp-config-sample.php wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/g" wp-config.php
sudo sed -i "s/username_here/$DB_USER/g" wp-config.php
sudo sed -i "s/password_here/$DB_PASSWORD/g" wp-config.php

# Generar claves de seguridad únicas
echo "Generando claves de seguridad..."
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sudo sed -i "/AUTH_KEY/d" wp-config.php
sudo sed -i "/SECURE_AUTH_KEY/d" wp-config.php
sudo sed -i "/LOGGED_IN_KEY/d" wp-config.php
sudo sed -i "/NONCE_KEY/d" wp-config.php
sudo sed -i "/AUTH_SALT/d" wp-config.php
sudo sed -i "/SECURE_AUTH_SALT/d" wp-config.php
sudo sed -i "/LOGGED_IN_SALT/d" wp-config.php
sudo sed -i "/NONCE_SALT/d" wp-config.php
sudo sed -i "/#@-/a $SALT" wp-config.php

# Configurar URL del sitio si no es localhost
if [ "$SITE_URL" != "localhost" ]; then
    echo "Configurando URL del sitio..."
    sudo sed -i "s/define('WP_SITEURL', 'http:\/\/example.com');/define('WP_SITEURL', 'http:\/\/$SITE_URL');/g" wp-config.php
    sudo sed -i "s/define('WP_HOME', 'http:\/\/example.com');/define('WP_HOME', 'http:\/\/$SITE_URL');/g" wp-config.php
fi

# Habilitar módulo rewrite de Apache
echo "Habilitando módulo rewrite de Apache..."
sudo a2enmod rewrite

# Configurar archivo de host virtual de Apache
echo "Configurando host virtual de Apache..."
sudo bash -c "cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ServerName $SITE_URL
    <Directory /var/www/html/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
EOF"

# Deshabilitar sitio por defecto y habilitar el nuevo
sudo a2dissite 000-default.conf
sudo a2ensite wordpress.conf

# Reiniciar Apache para aplicar cambios
echo "Reiniciando Apache..."
sudo systemctl restart apache2

# Mensaje final
echo "Instalación completada. Puedes acceder a WordPress en http://$SITE_URL"
