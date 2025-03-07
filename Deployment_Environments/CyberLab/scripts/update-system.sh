#!/bin/bash

# Script para actualizar el sistema y las herramientas

echo "[+] Actualizando repositorios..."
sudo apt update

echo "[+] Actualizando paquetes del sistema..."
sudo apt upgrade -y

echo "[+] Actualizando herramientas de Python..."
pip3 install --upgrade pip
pip3 list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip3 install -U

echo "[+] Actualizando herramientas descargadas..."
/home/security/scripts/setup-tools.sh

echo "[+] Sistema actualizado completamente!"
