#!/bin/bash

# Mejora el manejo de errores y el registro de progreso
set -eo pipefail

# Define colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET_COLOR='\033[0m'

# Archivo de registro
LOG_FILE="/tmp/docker_install_$(date +%Y%m%d_%H%M%S).log"

# Función para mostrar mensajes y registrarlos
log_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${RESET_COLOR}" | tee -a "$LOG_FILE"
}

# Función para ejecutar comandos con registro y manejo de errores
run_command() {
    local command="$1"
    local error_message="$2"

    log_message "$YELLOW" "Ejecutando: $command"
    if ! eval "$command" >> "$LOG_FILE" 2>&1; then
        log_message "$RED" "ERROR: $error_message"
        log_message "$YELLOW" "Consulte el archivo de registro $LOG_FILE para más detalles."
        exit 1
    fi
}

# Verificar privilegios de root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_message "$RED" "Este script debe ejecutarse como root o con sudo."
        exit 1
    fi
}

# Verificar la arquitectura del sistema
check_architecture() {
    log_message "$GREEN" "Verificando la arquitectura del sistema..."
    local ARCH=$(dpkg --print-architecture)
    
    if [[ ! "$ARCH" =~ ^(amd64|armhf|arm64|s390x|ppc64el)$ ]]; then
        log_message "$RED" "La arquitectura $ARCH no es compatible con Docker."
        exit 1
    else
        log_message "$GREEN" "Arquitectura $ARCH compatible."
    fi
}

# Desinstalar versiones antiguas
remove_old_versions() {
    log_message "$GREEN" "Desinstalando versiones antiguas de Docker..."
    run_command "apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true" "No se pudieron eliminar versiones antiguas"
    
    # Eliminar el archivo de lista de repositorio antiguo si existe
    if [ -f /etc/apt/sources.list.d/docker.list ]; then
        run_command "rm -f /etc/apt/sources.list.d/docker.list" "No se pudo eliminar el archivo de lista antiguo"
    fi
}

# Configurar el repositorio de Docker
setup_repository() {
    log_message "$GREEN" "Configurando el repositorio de Docker..."
    
    # Actualizar e instalar dependencias
    run_command "apt-get update" "No se pudo actualizar la lista de paquetes"
    run_command "apt-get install -y ca-certificates curl gnupg lsb-release" "No se pudieron instalar las dependencias necesarias"
    
    # Crear directorio para claves GPG
    run_command "mkdir -p /etc/apt/keyrings" "No se pudo crear el directorio para claves GPG"
    
    # Descargar e instalar la clave GPG de Docker
    log_message "$GREEN" "Descargando la clave GPG oficial de Docker..."
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_message "$RED" "No se pudo descargar o instalar la clave GPG de Docker."
        exit 1
    fi
    
    # Establecer permisos adecuados para la clave
    run_command "chmod a+r /etc/apt/keyrings/docker.gpg" "No se pudieron establecer permisos para la clave GPG"
    
    # Agregar el repositorio de Docker a APT
    local UBUNTU_CODENAME=$(lsb_release -cs)
    local ARCH=$(dpkg --print-architecture)
    
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    run_command "apt-get update" "No se pudo actualizar la lista de paquetes después de agregar el repositorio de Docker"
}

# Instalar Docker Engine
install_docker() {
    log_message "$GREEN" "Instalando Docker Engine, CLI, Containerd y plugins..."
    run_command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "No se pudo instalar Docker"
}

# Configurar usuario actual para usar Docker sin sudo
setup_user_permissions() {
    local CURRENT_USER="${SUDO_USER:-$USER}"
    
    if [ "$CURRENT_USER" != "root" ]; then
        log_message "$GREEN" "Configurando permisos para que el usuario $CURRENT_USER pueda usar Docker sin sudo..."
        
        # Añadir usuario al grupo docker
        run_command "usermod -aG docker $CURRENT_USER" "No se pudo añadir el usuario al grupo docker"
        
        log_message "$YELLOW" "NOTA: Es necesario cerrar sesión y volver a iniciarla para que los cambios surtan efecto."
    fi
}

# Verificar la instalación
verify_installation() {
    log_message "$GREEN" "Verificando la instalación de Docker..."
    
    if systemctl is-active --quiet docker; then
        log_message "$GREEN" "El servicio Docker está activo."
    else
        log_message "$YELLOW" "El servicio Docker no está activo. Intentando iniciarlo..."
        run_command "systemctl start docker" "No se pudo iniciar el servicio Docker"
    fi
    
    log_message "$GREEN" "Ejecutando prueba de Docker con una imagen de prueba..."
    run_command "docker run --rm hello-world" "La prueba de Docker falló. Por favor, revise la configuración."
}

main() {
    log_message "$GREEN" "Iniciando la instalación de Docker Engine..."
    
    check_root
    check_architecture
    remove_old_versions
    setup_repository
    install_docker
    setup_user_permissions
    verify_installation
    
    log_message "$GREEN" "¡La instalación de Docker Engine ha sido exitosa!"
    log_message "$GREEN" "Para ver los detalles de la instalación, consulte el archivo de registro: $LOG_FILE"
    log_message "$GREEN" "Versión de Docker instalada:"
    docker --version | tee -a "$LOG_FILE"
}

# Ejecutar el script
main "$@"
