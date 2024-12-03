#!/bin/bash

# Script para configurar una interfaz de bonding con nmcli en RHEL
# Interfaces esclavas: ens256, ens224, ens161
# Bonding Mode: active-backup (ideal para redundancia)
# Dirección IP estática: Configurable según tus necesidades

# ============================
# Configuración Inicial
# ============================

# Nombre de la interfaz bond
BOND_NAME="mybond0"  # Nombre de la interfaz bond

# Opciones de bonding
BOND_MODE="active-backup"   # Modo recomendado para redundancia
MIIMON="100"                # Monitorización MII en milisegundos
PRIMARY_IF="ens256"         # Interfaz primaria (opcional)

# Interfaces esclavas
SLAVE_INTERFACES=("ens256" "ens224" "ens161")

# Configuración de IP (Modificar según tus necesidades)
IP_ADDRESS="192.168.1.100/24"   # Dirección IP y máscara de subred
GATEWAY="192.168.1.1"           # Puerta de enlace predeterminada
DNS1="8.8.8.8"                   # Servidor DNS primario
DNS2="8.8.4.4"                   # Servidor DNS secundario

# Nombre de la conexión bond
BOND_CONNECTION_NAME="Bond-$BOND_NAME"

# ============================
# Funciones Auxiliares
# ============================

# Función para verificar el estado de un comando
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 falló. Saliendo del script."
        exit 1
    else
        echo "$1 completado exitosamente."
    fi
}

# ============================
# Paso 1: Crear la Conexión de Bond
# ============================

echo "Creando la conexión de bond: $BOND_CONNECTION_NAME"

nmcli con add type bond ifname "$BOND_NAME" con-name "$BOND_CONNECTION_NAME" \
    bond.options "mode=$BOND_MODE,miimon=$MIIMON,primary=$PRIMARY_IF" \
    ipv4.method manual \
    ipv4.addresses "$IP_ADDRESS" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS1 $DNS2" \
    autoconnect yes

check_status "Creación de la conexión de bond"

# ============================
# Paso 2: Configurar las Interfaces Esclavas
# ============================

echo "Configurando las interfaces esclavas y asignándolas al bond: $BOND_NAME"

for SLAVE in "${SLAVE_INTERFACES[@]}"; do
    # Nombre de la conexión esclava
    SLAVE_CONNECTION_NAME="Bond-slave-$SLAVE"
    
    # Eliminar cualquier conexión previa en la interfaz esclava
    nmcli con delete "$SLAVE_CONNECTION_NAME" &> /dev/null
    
    # Crear la conexión esclava y asignarla al bond
    nmcli con add type ethernet ifname "$SLAVE" con-name "$SLAVE_CONNECTION_NAME" \
        master "$BOND_NAME" slave-type bond
    check_status "Asignación de $SLAVE al bond"

    # Activar la conexión esclava
    nmcli con up "$SLAVE_CONNECTION_NAME"
    check_status "Activación de la conexión esclava $SLAVE_CONNECTION_NAME"
done

# ============================
# Paso 3: Activar la Conexión de Bond
# ============================

echo "Activando la conexión de bond: $BOND_CONNECTION_NAME"

nmcli con up "$BOND_CONNECTION_NAME"
check_status "Activación de la conexión de bond"

# ============================
# Paso 4: Verificar la Configuración
# ============================

echo "Verificando la configuración del bond"

# Mostrar detalles de la conexión de bond
nmcli con show "$BOND_CONNECTION_NAME"

# Mostrar detalles a nivel de kernel
echo "---------------------------------------"
cat /proc/net/bonding/"$BOND_NAME"
echo "---------------------------------------"

# Mostrar la configuración IP
ip addr show "$BOND_NAME"

# Verificar la ruta predeterminada
ip route show

# ============================
# Paso 5: Comprobación de Conectividad
# ============================

echo "Comprobando la conectividad de red"

# Intentar hacer ping a la puerta de enlace
ping -c 4 "$GATEWAY"
if [ $? -eq 0 ]; then
    echo "Conectividad a la puerta de enlace verificada."
else
    echo "No se pudo alcanzar la puerta de enlace."
fi

# ============================
# Paso Final: Resumen
# ============================

echo "Configuración de bonding completada exitosamente."
