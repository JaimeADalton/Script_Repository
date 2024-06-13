#!/bin/bash

echo "### Información del Sistema Operativo ###"

# Función para identificar el gestor de paquetes
identify_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "Gestor de paquetes: APT (Debian/Ubuntu)"
    elif command -v yum &> /dev/null; then
        echo "Gestor de paquetes: YUM (RHEL/CentOS)"
    elif command -v dnf &> /dev/null; then
        echo "Gestor de paquetes: DNF (Fedora)"
    elif command -v pacman &> /dev/null; then
        echo "Gestor de paquetes: Pacman (Arch Linux)"
    elif command -v zypper &> /dev/null; then
        echo "Gestor de paquetes: Zypper (SUSE)"
    else
        echo "Gestor de paquetes no identificado"
    fi
}

# Función para identificar la distribución y versión
identify_os_version() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "Distribución: $NAME"
        echo "Versión: $VERSION"
    elif [ -f /etc/lsb-release ]; then
        source /etc/lsb-release
        echo "Distribución: $DISTRIB_ID"
        echo "Versión: $DISTRIB_RELEASE ($DISTRIB_CODENAME)"
    elif [ -f /etc/redhat-release ]; then
        echo "Distribución: $(cat /etc/redhat-release)"
    elif [ -f /etc/debian_version ]; then
        echo "Distribución: Debian"
        echo "Versión: $(cat /etc/debian_version)"
    else
        echo "Distribución no identificada"
    fi
}

# Función para obtener la versión del kernel y su fecha de lanzamiento
get_kernel_info() {
    KERNEL_VERSION=$(uname -r)
    KERNEL_DATE=$(uname -v)
    echo "Versión del Kernel: $KERNEL_VERSION"
    echo "Fecha del Kernel: $KERNEL_DATE"
}

# Función para inferir la antigüedad de la máquina
infer_machine_age() {
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
    KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)
    if [ $KERNEL_MAJOR -le 2 ] && [ $KERNEL_MINOR -lt 6 ]; then
        echo "La máquina es muy antigua (antes de 2003)"
    elif [ $KERNEL_MAJOR -le 2 ]; then
        echo "La máquina es antigua (2003-2011)"
    elif [ $KERNEL_MAJOR -eq 3 ]; then
        echo "La máquina es moderadamente antigua (2011-2015)"
    elif [ $KERNEL_MAJOR -eq 4 ]; then
        echo "La máquina es relativamente moderna (2015-2020)"
    else
        echo "La máquina es moderna (2020 en adelante)"
    fi
}

# Ejecutar funciones
identify_os_version
identify_package_manager
get_kernel_info
infer_machine_age

# Información adicional
echo "Información adicional:"
uname -a

# Comando lsb_release
if command -v lsb_release &> /dev/null; then
    echo "Comando lsb_release:"
    lsb_release -a
fi

# Comando hostnamectl
if command -v hostnamectl &> /dev/null; then
    echo "Comando hostnamectl:"
    hostnamectl
fi
