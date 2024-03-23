#!/bin/bash

# Detener la ejecución si ocurre cualquier error
set -e

# Verificar la arquitectura del sistema
ARCH=$(dpkg --print-architecture)
if [[ ! "$ARCH" =~ ^(amd64|armhf|arm64|s390x|ppc64el)$ ]]; then
    echo "La arquitectura $ARCH no es compatible."
    exit 1
fi

# Desinstalar versiones antiguas
echo "Desinstalando versiones antiguas..."
sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

# Borrando archivo lista de repositorio viejo
rm /etc/apt/sources.list.d/docker.list

# Configurar el repositorio de Docker
echo "Configurando el repositorio de Docker..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Agregar la clave GPG oficial de Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Agregar el repositorio de Docker a APT
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

# Instalar Docker Engine, CLI, y Containerd
echo "Instalando Docker Engine, CLI, y Containerd..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "La instalación de Docker Engine ha sido exitosa."
