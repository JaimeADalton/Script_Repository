#!/bin/bash

# Establece la variable DEBIAN_FRONTEND en "noninteractive"
export DEBIAN_FRONTEND=noninteractive

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualiza la lista de paquetes nuevamente antes de la instalación de Docker
sudo apt-get update -q -y

# Instala Docker y sus componentes
sudo apt-get install -q -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Restaura la variable DEBIAN_FRONTEND a su valor predeterminado
unset DEBIAN_FRONTEND

# Fin del script
