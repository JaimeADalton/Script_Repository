#!/bin/bash

# Establece la variable DEBIAN_FRONTEND en "noninteractive"
export DEBIAN_FRONTEND=noninteractive

# Actualiza la lista de paquetes e instala las herramientas necesarias
sudo apt-get update -q -y
sudo apt-get install -q -y ca-certificates curl gnupg

# Crea el directorio para el almacenamiento de claves
sudo install -m 0755 -d /etc/apt/keyrings

# Descarga y agrega la clave GPG de Docker al anillo de claves
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Otorga permisos de lectura a la clave GPG
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Agrega el repositorio de Docker al archivo sources.list.d
echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualiza la lista de paquetes nuevamente antes de la instalación de Docker
sudo apt-get update -q -y

# Instala Docker y sus componentes
sudo apt-get install -q -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Restaura la variable DEBIAN_FRONTEND a su valor predeterminado
unset DEBIAN_FRONTEND

# Fin del script
