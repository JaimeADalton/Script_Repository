#!/bin/bash

# Bloquear señales relevantes
trap '' INT QUIT TSTP

# Funciones
function validate_input() {
    local input="$1"
    local pattern="^[a-zA-Z0-9._-]+$"
    if [[ ! $input =~ $pattern ]]; then
        echo "Caracteres no válidos en la entrada"
        return 1
    fi
    return 0
}

function log_action() {
    local ip="$1"
    local cmd="$2"
    echo "[ $(date +"%d/%m/%y %r")] Host: $ip  --  $cmd" >> /var/log/restricted_shell.log
}

function sanitize_command() {
    echo "$1" | sed -e 's/&&.*//g' -e 's/||.*//g' -e 's/\;.*//g' -e 's/\|.*//g' -e 's/>.*//g' -e 's/<.*//g'
}

# Variables
IP=$(echo $SSH_CONNECTION | awk '{print $1, $2}')
allowed_commands=("ping" "tracepath" "plink" "ssh" "exit")
max_args=3
timeout_duration=10s

# Limpiar la pantalla
clear && clear

echo "Comandos Permitidos: ${allowed_commands[*]}"

while true; do
    read -e -p "Restricted: $ " -a cmd_parts
    while [[ -z ${cmd_parts[0]} ]]; do
        read -e -p "Restricted: $ " -a cmd_parts
    done

    first_word="${cmd_parts[0]}"
    cmd="${cmd_parts[*]}"

    # Validar entrada
    if ! validate_input "$first_word"; then
        continue
    fi

    # Sanitizar el comando
    sanitized_cmd=$(sanitize_command "$cmd")
    
    # Registrar la acción
    log_action "$IP" "$cmd"

    if [[ " ${allowed_commands[*]} " =~ " ${first_word} " ]]; then
        if [[ "${first_word}" == "exit" ]]; then
            exit 0
        else
            # Limitar la cantidad de argumentos
            if [[ ${#cmd_parts[@]} -gt $max_args ]]; then
                echo "Demasiados argumentos para el comando \"$first_word\". Se permiten hasta $((max_args-1)) argumentos."
                continue
            fi

            # Ejecutar el comando de manera segura
            timeout $timeout_duration "${cmd_parts[@]}"
            exit_status=$?
            
            if [ $exit_status -eq 124 ]; then
                echo "El comando se interrumpió después de $timeout_duration"
            elif [ $exit_status -ne 0 ]; then
                echo "El comando falló con código de salida $exit_status"
            fi
        fi
    else
        echo "Comando \"${sanitized_cmd}\" no permitido. Comandos Permitidos: ${allowed_commands[*]}"
    fi
done
