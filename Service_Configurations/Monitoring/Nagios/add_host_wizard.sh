#!/bin/bash


# Script para agregar nuevos hosts y servicios a la configuración de Nagios.
# Entrada: Se solicitan datos al usuario para los detalles del host.
# Salida: Archivo de configuración de Nagios actualizado.

dir="/usr/local/nagios/etc/objects/"
files=( "$dir"*.cfg )
options=()
options=("Añadir un nuevo cliente")

for ((i = 0; i < ${#files[@]}; i++)); do
    file="${files[$i]}"
    base_name=$(basename "$file" .cfg)
    cleaned_name="${base_name//[-_]/ }"
    options+=("$cleaned_name")
done


echo "Por favor, selecciona un cliente a modificar:"
select opt in "${options[@]}"; do
    if [ "$REPLY" -eq 1 ]; then
        echo -n "Introduce el nombre del nuevo cliente: "
        read client_name
        # Sustituir espacios por guiones bajos
        client_name="${client_name// /_}"
        # Crear un archivo nuevo con el nombre del cliente
        new_file="$dir$client_name.cfg"
        touch "$new_file"
        # Añadir línea en nagios.cfg
        echo "cfg_file=$new_file" | sudo tee -a /usr/local/nagios/etc/nagios.cfg > /dev/null
        echo "Archivo para el cliente '$client_name' creado exitosamente."
        NAGIOS_CONFIG="$new_file"
        break
    elif [ "$REPLY" -ge 2 ] && [ "$REPLY" -le $(( ${#options[@]} + 1 )) ]; then
        NAGIOS_CONFIG="${files[$REPLY-2]}"
        break
    else
        echo "Opción no válida. Por favor selecciona un número de la lista."
    fi
done



trap '[[ -n $temp_file ]] && rm -f $temp_file' EXIT

if [[ ! -f "$NAGIOS_CONFIG" ]]; then
    echo "Error: Archivo de configuración "$NAGIOS_CONFIG" no encontrado."
    exit 1
fi

add_new_member_to_hostgroup() {
    local hostgroup_name="$1"
    local new_member="$2"
    local input_file="$3"
    local temp_file=$(mktemp)
    awk -v hostgroup_name="$hostgroup_name" -v new_member="$new_member" '
    BEGIN { in_hostgroup = 0 }
    {
        if ($1 == "define" && $2 == "hostgroup{") {
            in_hostgroup = 1
        }
        if (in_hostgroup && $1 == "hostgroup_name" && $2 == hostgroup_name) {
            found_hostgroup = 1
        }
        if (in_hostgroup && $1 == "members" && found_hostgroup) {
            sub(/members[[:space:]]*/, "&" new_member ",")
            found_hostgroup = 0
        }
        if ($1 == "}") {
            in_hostgroup = 0
        }
        print
    }' "$input_file" > "$temp_file"
    sudo mv "$temp_file" "$input_file"
    sudo chown nagios:nagios "$input_file"
    sudo chmod 660 "$input_file"
}

while true; do
    echo -n "Introduce el número de hosts a añadir: "
    read num_hosts
    if [[ ! $num_hosts =~ ^[0-9]+$ ]]; then
        echo "Entrada no válida. Por favor, ingresa un número."
    else
        break
    fi
done

while true; do
    echo -n "Número de hosts introducido: $num_hosts. ¿Es correcto? (S/n): "
    read confirmacion
    confirmacion=${confirmacion:-S}
    if [[ $confirmacion =~ ^[Ss]$ ]]; then
        break
    elif [[ $confirmacion =~ ^[Nn]$ ]]; then
        while true; do
            echo -n "Introduce el número de hosts a añadir: "
            read num_hosts
            if [[ ! $num_hosts =~ ^[0-9]+$ ]]; then
                echo "Entrada no válida. Por favor, ingresa un número."
            else
                break
            fi
        done
    else
        echo "Respuesta no válida. Por favor, responde 'S' o 'n'."
    fi
done

declare -A hostgroup_members

hostgroups=$(grep -E "^\s*hostgroup_name" "$NAGIOS_CONFIG" | awk '{print $2}')
echo "Selecciona un hostgroup para agregar los hosts o ingresa uno nuevo:"
PS3="Escribe el número correspondiente o introduce un hostgroup nuevo: "
select hostgroup in $hostgroups "Nuevo hostgroup"; do
    if [[ $hostgroup == "Nuevo hostgroup" ]] || [[ -z $hostgroup ]]; then
        echo -n "Introduce el nombre del nuevo hostgroup: "
        read hostgroup
    fi
    break
done

for ((i=1; i<=num_hosts; i++))
do
    echo "Introduce los datos para el host número $i:"
    echo -n "Host_name: "
    read host_name
    echo -n "Alias: "
    read alias
    echo -n "Address: "
    read address
    cat >> "$NAGIOS_CONFIG" << EOF
define host{
        use             generic-switch
        host_name       $host_name
        alias           $alias
        address         $address
        hostgroups      $hostgroup
        }
EOF
    cat >> "$NAGIOS_CONFIG" << EOF
define service{
        use                     generic-service
        host_name               $host_name
        service_description     PING
        check_command           check_ping!200.0,20%!200.0,60%
        }
EOF
    if [[ -n "${hostgroup_members["$hostgroup"]}" ]]; then
        hostgroup_members["$hostgroup"]+=","
    fi
    hostgroup_members["$hostgroup"]+="$host_name"
done

for hostgroup in "${!hostgroup_members[@]}"; do
    members="${hostgroup_members["$hostgroup"]}"
    hostgroup_exists=$(grep -E "^\s*hostgroup_name\s+$hostgroup" "$NAGIOS_CONFIG")
    if [[ -z $hostgroup_exists ]]; then
        cat >> "$NAGIOS_CONFIG" << EOF
define hostgroup{
        hostgroup_name  $hostgroup
        alias           New Hostgroup
        members         $members
        }
EOF
    else
        add_new_member_to_hostgroup "$hostgroup" "$members" "$NAGIOS_CONFIG"
    fi
done

echo "Los hosts y servicios han sido agregados correctamente. Por favor, verifica y reinicia el servicio de Nagios para aplicar los cambios."
if /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg > /dev/null 2>&1 | awk '/Total/ {if ($3 == 0) { exit 0 } else { exit 1 }}'; then
    sudo /usr/bin/systemctl restart nagios.service
else
    /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
fi
