#!/bin/bash

# Actualiza la lista de paquetes e instala las herramientas necesarias
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Crea el directorio para el almacenamiento de claves
sudo install -m 0755 -d /etc/apt/keyrings

# Descarga y agrega la clave GPG de Docker al anillo de claves
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Otorga permisos de lectura a la clave GPG
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Agrega el repositorio de Docker al archivo sources.list.d
echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualiza la lista de paquetes nuevamente
sudo apt-get update

# Instala Docker y sus componentes
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
