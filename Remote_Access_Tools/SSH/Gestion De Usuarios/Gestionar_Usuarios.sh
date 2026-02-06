#!/bin/bash
set -euo pipefail
#export PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:-main}: '
#set -xEeuo pipefail
#trap 'ret=$?;
#      echo -e "\n\033[0;31m[ERROR]\033[0m Falló el comando en línea $LINENO: $BASH_COMMAND (ret=$ret)";
#      echo "Contexto: archivo: $BASH_SOURCE, función: ${FUNCNAME[0]:-main}";
#      exit $ret' ERR


# --- Configuración de Logging ---
readonly LOG_LEVEL_QUIET=-1
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_VERBOSE=3
readonly LOG_LEVEL_DEBUG=4

readonly C_ERROR='\033[0;31m'
readonly C_WARN='\033[0;33m'
readonly C_INFO='\033[0;32m'
readonly C_VERBOSE_INFO='\033[0;36m'
readonly C_DEBUG='\033[0;34m'
readonly C_SUMMARY_H='\033[1;32m'
readonly C_NC='\033[0m'

_log_msg() {
    local level_name="$1"; shift; local message="$*"
    local numeric_level_msg; local color_code_msg; local tag_display_msg
    local should_log_this_msg=0

    case "$level_name" in
        ERROR) numeric_level_msg=$LOG_LEVEL_ERROR; color_code_msg=$C_ERROR; tag_display_msg="ERROR" ;;
        WARN)  numeric_level_msg=$LOG_LEVEL_WARN;  color_code_msg=$C_WARN; tag_display_msg="WARN " ;;
        INFO)  numeric_level_msg=$LOG_LEVEL_INFO;  color_code_msg=$C_INFO; tag_display_msg="INFO " ;;
        VERBOSE_INFO) numeric_level_msg=$LOG_LEVEL_VERBOSE; color_code_msg=$C_VERBOSE_INFO; tag_display_msg="INFOV" ;;
        DEBUG) numeric_level_msg=$LOG_LEVEL_DEBUG; color_code_msg=$C_DEBUG; tag_display_msg="DEBUG" ;;
        SUMMARY_H) numeric_level_msg=$LOG_LEVEL_ERROR; color_code_msg=$C_SUMMARY_H; tag_display_msg="" ;;
        SUMMARY) numeric_level_msg=$LOG_LEVEL_ERROR; color_code_msg=$C_INFO; tag_display_msg="" ;;
        *) echo -e "${C_ERROR}[CRITICAL] Nivel de log desconocido en _log_msg: ${level_name}${C_NC}" >&2; return 1 ;;
    esac

    if [[ $numeric_level_msg -le $CURRENT_LOG_LEVEL_INTERNAL ]]; then
        should_log_this_msg=1
    fi

    if [[ $should_log_this_msg -eq 1 ]]; then
        if [[ "$level_name" == "SUMMARY" || "$level_name" == "SUMMARY_H" ]]; then
            echo -e "${color_code_msg}${message}${C_NC}" >&2
        else
            echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${color_code_msg}[${tag_display_msg}]${C_NC} ${message}" >&2
        fi
    fi
}

# --- Fin Configuración de Logging ---

# --- Constantes y Variables Globales ---
readonly DEFAULT_USER_FILE_ORIG="usernames.txt"
readonly SSH_KEY_TYPE_ORIG="ed25519"
readonly SSH_KEY_ROUNDS_ORIG=200
readonly SSH_KEY_PREFIX_ORIG="_srvbastionssh.key"
readonly MIN_UID_REGULAR_ORIG=1000
readonly DISTRIBUIR_SCRIPT_PATH="/usr/local/bin/distribuir_claves"
readonly DISTRIBUIR_CLAVES_LINK_LOG_PATH="/tmp/ssh_links.log"
readonly SSH_SERVERS_DIR_PATH="/tmp/ssh_servers"

# Variables que se modificarán por flags
USER_FILE_VAR="$DEFAULT_USER_FILE_ORIG"
EXPLICIT_LINKS_FLAG=0
FORCE_ALL_FLAG=0
FORCE_USER_VAR=""
# Nivel de log global real - se seteará después de parsear args
CURRENT_LOG_LEVEL_INTERNAL=$LOG_LEVEL_QUIET

# Contadores y datos
users_processed_count=0; users_created_count=0; users_keys_regenerated_count=0
users_no_changes_count=0; users_deleted_count=0; errors_encountered_count=0
declare -a GENERATED_LINKS_DATA_ARRAY=()
# --- Fin Constantes y Variables Globales ---


# --- Funciones (sin cambios respecto a la versión anterior, excepto llamadas a _log_msg) ---
_gu_usage() {
    cat <<EOF
Uso: $(basename "$0") [OPCIONES]
Administrador de usuarios y claves SSH. Genera enlaces automáticamente
para usuarios nuevos o cuando se fuerzan claves.
Salida por defecto es concisa (errores y resumen). Use -v o -vv para más detalle.

Opciones:
  -f ARCHIVO       Archivo de usuarios (def: $DEFAULT_USER_FILE_ORIG)
  -q, --quiet      (Comportamiento por defecto) Modo silencioso.
  -v               Modo verboso (INFO, WARN, ERROR, Resumen).
  -vv              Modo debug (DEBUG, INFO, WARN, ERROR, Resumen).
  -h, --help       Muestra esta ayuda
  --force USUARIO  Forzar regeneración de claves para USUARIO (implica enlace).
  --force-all      Forzar regeneración de claves para TODOS (implican enlaces).
  --links          (Opcional) Asegura generación de enlaces. Normalmente automático.

EOF
}

_gu_check_root() {
    if [[ $EUID -ne 0 ]]; then
        # Usar echo directo para este error crítico inicial, ya que el nivel de log aún no está fijado
        echo -e "${C_ERROR}[ERROR] Este script debe ejecutarse como root.${C_NC}" >&2
        ((errors_encountered_count++)); return 1
    fi
    return 0
}

_gu_check_dependencies() {
    if command -v puttygen >/dev/null 2>&1; then
        HAS_PUTTYGEN_VAR=1
        _log_msg DEBUG "puttygen encontrado."
    else
        # Este WARN se mostrará si el nivel final es WARN o superior
        _log_msg WARN "puttygen no está instalado. No se generarán archivos .ppk."
        HAS_PUTTYGEN_VAR=0
    fi
    return 0
}

_gu_validate_user_file() {
    if [[ ! -f "$USER_FILE_VAR" ]]; then
        _log_msg ERROR "Archivo de usuarios '$USER_FILE_VAR' no encontrado."
        ((errors_encountered_count++)); return 1
    fi
     _log_msg DEBUG "Archivo de usuarios '$USER_FILE_VAR' validado."
    return 0
}

_gu_is_system_user() {
    local username=$1; local uid
    uid=$(id -u "$username" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        _log_msg WARN "No se pudo obtener UID para $username. Asumiendo como sistema (seguridad)."
        return 0
    fi
    local system_user_names=("root" "nobody" "nfsnobody" "daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats" "systemd-network" "systemd-resolve" "messagebus" "sshd")
    for sys_user_item in "${system_user_names[@]}"; do
        if [[ "$username" == "$sys_user_item" ]]; then
            _log_msg DEBUG "Usuario '$username' es de sistema (por nombre)."
            return 0
        fi
    done
    if [[ $uid -lt $MIN_UID_REGULAR_ORIG || $uid -ge 65000 ]]; then
        _log_msg DEBUG "Usuario '$username' (UID $uid) es de sistema (por UID)."
        return 0
    fi
    _log_msg DEBUG "Usuario '$username' (UID $uid) es regular."
    return 1
}

_gu_setup_ssh_keys() {
    local username=$1
    local is_new_user_created_flag=$2
    local ssh_home_dir="/home/$username/.ssh"
    local keys_were_generated_this_run=0
    local ppk_was_generated_this_run=0

    local should_force_regeneration=0
    if [[ $FORCE_ALL_FLAG -eq 1 || "$FORCE_USER_VAR" == "$username" ]]; then
        should_force_regeneration=1
    fi

    if [[ $should_force_regeneration -eq 1 ]]; then
        _log_msg INFO "Limpiando directorio $ssh_home_dir para '$username' antes de forzar regeneración."
        if [[ -n "$ssh_home_dir" && "$ssh_home_dir" != "/home/" && "$ssh_home_dir" != "/home/*" ]]; then
           # Asegurarse que el directorio base exista antes de borrar contenido
           mkdir -p "$(dirname "$ssh_home_dir")"
           # Si el dir existe, borrar contenido. Si no, mkdir lo creará.
           if [[ -d "$ssh_home_dir" ]]; then
              local bkp_dir="${ssh_home_dir%/}.bkp_$(date +%Y%m%d_%H%M%S)"
              _log_msg VERBOSE_INFO "Copiando $ssh_home_dir  →  $bkp_dir"
              mv "$ssh_home_dir" "$bkp_dir"
           fi
           mkdir -p "$ssh_home_dir"
           chmod 700 "$ssh_home_dir"
           chown "$username:$username" "$ssh_home_dir"
        else
            _log_msg ERROR "Path inválido para limpieza de .ssh: $ssh_home_dir"; ((errors_encountered_count++)); return 1
        fi
    else
        mkdir -p "$ssh_home_dir"; chmod 700 "$ssh_home_dir"; chown "$username:$username" "$ssh_home_dir"
    fi

    local key_file_path="$ssh_home_dir/${username}${SSH_KEY_PREFIX_ORIG}"
    local ppk_file_path="${key_file_path%.key}.ppk"

    if [[ $should_force_regeneration -eq 1 ]]; then
        _log_msg INFO "Forzando regeneración de claves para '$username'."
        keys_were_generated_this_run=1
    elif [[ -f "$key_file_path" ]]; then
        _log_msg VERBOSE_INFO "Claves SSH ($SSH_KEY_TYPE_ORIG) ya existen para '$username'."
    else
        _log_msg INFO "No se encontraron claves $SSH_KEY_TYPE_ORIG para '$username'. Generando nuevas."
        keys_were_generated_this_run=1
    fi

    if [[ $keys_were_generated_this_run -eq 1 ]]; then
        _log_msg VERBOSE_INFO "Generando par de claves SSH $SSH_KEY_TYPE_ORIG para '$username'..."
        if ssh-keygen -t "$SSH_KEY_TYPE_ORIG" -a "$SSH_KEY_ROUNDS_ORIG" -f "$key_file_path" -q -N "" 2>/dev/null; then
            _log_msg INFO "Nuevas claves SSH generadas para '$username'."
            if [[ $is_new_user_created_flag -eq 0 ]]; then
                ((users_keys_regenerated_count++));
            fi
        else
            _log_msg ERROR "Fallo al generar claves SSH para '$username' (ssh-keygen falló)."
            ((errors_encountered_count++)); return 1
        fi
        if [[ -f "$key_file_path.pub" ]]; then
            cat "$key_file_path.pub" > "$ssh_home_dir/authorized_keys"
            chmod 600 "$ssh_home_dir/authorized_keys"
            chown "$username:$username" "$ssh_home_dir/authorized_keys" "$key_file_path" "$key_file_path.pub"
        else
            _log_msg ERROR "Clave pública no encontrada tras generación para '$username'."
            ((errors_encountered_count++)); return 1
        fi
    fi

    if [[ $HAS_PUTTYGEN_VAR -eq 1 ]]; then
        if [[ $keys_were_generated_this_run -eq 1 || $should_force_regeneration -eq 1 || ! -f "$ppk_file_path" ]]; then
            _log_msg VERBOSE_INFO "Generando/Regenerando archivo .ppk para '$username'..."
            local puttygen_output
            local puttygen_status
            puttygen_output=$(puttygen "$key_file_path" -o "$ppk_file_path" -O private 2>&1)
            puttygen_status=$?
            if [[ $puttygen_status -eq 0 ]]; then
                chmod 600 "$ppk_file_path"; chown "$username:$username" "$ppk_file_path"
                _log_msg INFO "Archivo .ppk generado/actualizado: $ppk_file_path"
                ppk_was_generated_this_run=1
                if [[ $keys_were_generated_this_run -eq 0 && $is_new_user_created_flag -eq 0 ]]; then
                     local already_counted_as_regenerated_base_key=0
                     if [[ $keys_were_generated_this_run -eq 1 && $is_new_user_created_flag -eq 0 ]]; then
                        already_counted_as_regenerated_base_key=1
                     fi
                     if [[ $already_counted_as_regenerated_base_key -eq 0 ]]; then
                        ((users_keys_regenerated_count++))
                     fi
                fi
            else
                _log_msg ERROR "Fallo al convertir clave a .ppk para '$username' (status: $puttygen_status)."
                _log_msg ERROR "Salida de puttygen: $puttygen_output"
                ((errors_encountered_count++))
            fi
        else
            _log_msg VERBOSE_INFO "Archivo .ppk existente para '$username'. Omitiendo conversión."
        fi
    else
        _log_msg WARN "puttygen no disponible. No se generará/actualizará .ppk para '$username'."
    fi

    if [[ $is_new_user_created_flag -eq 0 && \
          $keys_were_generated_this_run -eq 0 && \
          $ppk_was_generated_this_run -eq 0 && \
          $should_force_regeneration -eq 0 ]]; then
        ((users_no_changes_count++))
    fi

    if [[ ! -f "$key_file_path" ]]; then
        _log_msg ERROR "Clave privada principal '$key_file_path' no encontrada para '$username' post-proceso."
        ((errors_encountered_count++)); return 1
    fi

    local ppk_arg_for_dist="$key_file_path"
    if [[ -f "$ppk_file_path" ]]; then
        ppk_arg_for_dist="$ppk_file_path"
    elif [[ $HAS_PUTTYGEN_VAR -eq 1 && ($keys_were_generated_this_run -eq 1 || $should_force_regeneration -eq 1) ]]; then
        _log_msg WARN "Se intentó generar PPK para '$username' pero '$ppk_file_path' no existe. Se distribuirá solo la clave principal."
    fi

    local generate_link_for_this_user=0
    if [[ $is_new_user_created_flag -eq 1 ]]; then
        generate_link_for_this_user=1
        _log_msg DEBUG "Usuario '$username' es nuevo, se generará enlace."
    elif [[ $should_force_regeneration -eq 1 ]]; then
        generate_link_for_this_user=1
        _log_msg DEBUG "Regeneración forzada para '$username', se generará enlace."
    elif [[ $EXPLICIT_LINKS_FLAG -eq 1 && ($keys_were_generated_this_run -eq 1 || $ppk_was_generated_this_run -eq 1) ]]; then
        generate_link_for_this_user=1
        _log_msg DEBUG "Flag --links explícito y claves/ppk (re)generados para '$username', se generará enlace."
    fi

    if [[ $generate_link_for_this_user -eq 1 ]]; then
        if [[ ! -f "$DISTRIBUIR_SCRIPT_PATH" ]]; then
            _log_msg ERROR "Script de distribución ($DISTRIBUIR_SCRIPT_PATH) no encontrado. No se puede generar enlace para '$username'."
            ((errors_encountered_count++)); return 1
        fi
         if [[ ! -x "$DISTRIBUIR_SCRIPT_PATH" ]]; then
            _log_msg DEBUG "Asegurando que $DISTRIBUIR_SCRIPT_PATH sea ejecutable..."
            if ! chmod +x "$DISTRIBUIR_SCRIPT_PATH"; then
                _log_msg ERROR "No se pudo hacer ejecutable $DISTRIBUIR_SCRIPT_PATH. No se puede generar enlace para '$username'."
                ((errors_encountered_count++)); return 1
            fi
        fi

        _log_msg INFO "Solicitando enlace de distribución para '$username'..."
        local dist_debug_level=0 # Por defecto, no activar debug en distribuir_claves
        [[ $CURRENT_LOG_LEVEL_INTERNAL -ge $LOG_LEVEL_DEBUG ]] && dist_debug_level=1 # Activar si estamos en debug (-vv)

        local link_data_raw_output
        _log_msg DEBUG "Comando a ejecutar: DIST_DEBUG=$dist_debug_level \"$DISTRIBUIR_SCRIPT_PATH\" --data-only \"$username\" \"$key_file_path\" \"$ppk_arg_for_dist\""

        # Ejecutar en subshell para pasar la variable de entorno correctamente
        link_data_raw_output=$( DIST_DEBUG=$dist_debug_level "$DISTRIBUIR_SCRIPT_PATH" --data-only "$username" "$key_file_path" "$ppk_arg_for_dist" )
        local dist_exit_code=$?

        if [[ $dist_exit_code -eq 0 && -n "$link_data_raw_output" ]]; then
            _log_msg DEBUG "Salida cruda de distribuir_claves para '$username': $link_data_raw_output"
            GENERATED_LINKS_DATA_ARRAY=("${GENERATED_LINKS_DATA_ARRAY[@]}" "$link_data_raw_output")
        else
            _log_msg ERROR "Fallo al obtener información del enlace para '$username' desde $DISTRIBUIR_SCRIPT_PATH (código de salida: $dist_exit_code)."
            if [[ -n "$link_data_raw_output" ]]; then
                 _log_msg ERROR "Salida (stdout) de distribuir_claves: $link_data_raw_output"
            fi
            if [[ $CURRENT_LOG_LEVEL_INTERNAL -ge $LOG_LEVEL_DEBUG ]]; then
                local server_log_path="${SSH_SERVERS_DIR_PATH}/${username}_server/server.log"
                local nohup_log_path="${SSH_SERVERS_DIR_PATH}/${username}_server/nohup.out"
                 _log_msg DEBUG "Buscando logs en $server_log_path y $nohup_log_path"
                 if [[ -f "$server_log_path" ]]; then _log_msg DEBUG "Tail de $server_log_path:"; tail -n 5 "$server_log_path" >&2; fi
                 if [[ -f "$nohup_log_path" ]]; then _log_msg DEBUG "Tail de $nohup_log_path:"; tail -n 5 "$nohup_log_path" >&2; fi
            fi
            ((errors_encountered_count++))
        fi
    elif [[ $EXPLICIT_LINKS_FLAG -eq 1 ]]; then
         _log_msg VERBOSE_INFO "Flag --links activo, pero no se generará enlace para '$username' (sin cambios relevantes y no es nuevo/forzado)."
    fi
    return 0
}

_gu_create_user() {
    local username=$1; local user_is_new=0
    if id "$username" &>/dev/null; then
        _log_msg INFO "Usuario '$username' ya existe. Verificando/actualizando claves."
        user_is_new=0
    else
        _log_msg INFO "Creando usuario '$username'..."
        if useradd -m -s /bin/bash "$username"; then
            _log_msg INFO "Usuario '$username' creado exitosamente."
            ((users_created_count++)); user_is_new=1
            local user_ssh_dir="/home/$username/.ssh"
            chown "$username:$username" "/home/$username"
            mkdir -p "$user_ssh_dir"; chmod 700 "$user_ssh_dir"; chown "$username:$username" "$user_ssh_dir"
        else
            _log_msg ERROR "Fallo al crear usuario '$username'."
            ((errors_encountered_count++)); return 1
        fi
    fi
    _gu_setup_ssh_keys "$username" "$user_is_new"
}

_gu_delete_user() {
    local username=$1
    if _gu_is_system_user "$username"; then
        return 0
    fi
    if [[ "$username" == "$(whoami)" ]]; then
        _log_msg ERROR "¡PROTECCIÓN! No se puede eliminar el usuario actual ('$(whoami)')."
        ((errors_encountered_count++)); return 1
    fi
    _log_msg INFO "Intentando eliminar usuario regular '$username'..."
    if id "$username" &>/dev/null; then
        if userdel -r "$username" 2>/dev/null; then
            _log_msg INFO "Usuario '$username' eliminado exitosamente."
            ((users_deleted_count++))
        else
            _log_msg ERROR "Fallo al ejecutar 'userdel -r $username'."
            ((errors_encountered_count++))
        fi
    else
        _log_msg WARN "Intento de eliminar usuario '$username', pero no existe en el sistema."
    fi
}

_gu_process_users_from_file() {
    _log_msg INFO "Procesando usuarios desde '$USER_FILE_VAR'..."
    local lines_to_process_count
    lines_to_process_count=$(grep -cvE '^\s*(#|$)' "$USER_FILE_VAR" || echo "0")
    _log_msg INFO "Se intentarán procesar aproximadamente $lines_to_process_count usuarios."

    while IFS= read -r user_line_raw || [[ -n "$user_line_raw" ]]; do
        local current_username="${user_line_raw%%#*}"
        current_username="${current_username//[[:space:]]/}"
        if [[ -z "$current_username" ]]; then continue; fi

        ((users_processed_count++))
        _log_msg DEBUG "Procesando usuario de archivo: '$user_line_raw' -> '$current_username'"
        _gu_create_user "$current_username"
    done < "$USER_FILE_VAR"
}

_gu_cleanup_unlisted_users() {
    local desired_users_temp_file; desired_users_temp_file=$(mktemp /tmp/desired_users.XXXXXX)
    local system_passwd_users_temp_file; system_passwd_users_temp_file=$(mktemp /tmp/system_users.XXXXXX)
    trap 'rm -f "$desired_users_temp_file" "$system_passwd_users_temp_file" 2>/dev/null' EXIT SIGINT SIGTERM

    if ! sed -e 's/#.*//' -e 's/[[:space:]]//g' "$USER_FILE_VAR" | grep -v '^$' > "$desired_users_temp_file"; then
       _log_msg ERROR "No se pudo procesar el archivo de usuarios '$USER_FILE_VAR' para la limpieza."
       ((errors_encountered_count++)); return 1
    fi

    _log_msg INFO "Limpieza: Verificando usuarios del sistema no listados en '$USER_FILE_VAR'..."
    if ! awk -F: '{print $1}' /etc/passwd > "$system_passwd_users_temp_file"; then
        _log_msg ERROR "No se pudo leer /etc/passwd para la limpieza."
        ((errors_encountered_count++)); return 1
    fi

    while IFS= read -r username_from_passwd || [[ -n "$username_from_passwd" ]]; do
        if ! grep -Fxq "$username_from_passwd" "$desired_users_temp_file"; then
            if _gu_is_system_user "$username_from_passwd"; then
                :
            else
                _log_msg INFO "Usuario '$username_from_passwd' no listado y no es de sistema. Procediendo a eliminar."
                _gu_delete_user "$username_from_passwd"
            fi
        fi
    done < "$system_passwd_users_temp_file"

    rm -f "$desired_users_temp_file" "$system_passwd_users_temp_file" 2>/dev/null
    trap - EXIT SIGINT SIGTERM
    _log_msg INFO "Limpieza de usuarios no listados completada."
}

_gu_print_summary() {
    local common_zip_password="<No Generada>"
    local has_links=0
    if [[ ${#GENERATED_LINKS_DATA_ARRAY[@]} -gt 0 ]]; then
        has_links=1
        if [[ -n "${GENERATED_LINKS_DATA_ARRAY[0]}" ]]; then
            IFS=';' read -ra parts_for_pass <<< "${GENERATED_LINKS_DATA_ARRAY[0]}"
            for part_pass in "${parts_for_pass[@]}"; do
                if [[ "$part_pass" == PASSWORD:* ]]; then
                    common_zip_password="${part_pass#PASSWORD:}"
                    break
                fi
            done
        fi
    fi

    echo
    _log_msg SUMMARY_H "-----------------------------------------------------"
    _log_msg SUMMARY_H "RESUMEN DE OPERACIONES"
    _log_msg SUMMARY_H "-----------------------------------------------------"
    _log_msg SUMMARY "Usuarios procesados: $users_processed_count"
    _log_msg SUMMARY "- Creados: $users_created_count"
    _log_msg SUMMARY "- Actualizados (claves regeneradas): $users_keys_regenerated_count"
    _log_msg SUMMARY "- Sin cambios: $users_no_changes_count"
    if [[ $users_deleted_count -gt 0 ]]; then
      _log_msg SUMMARY "- Eliminados: $users_deleted_count"
    fi
    local error_color=$C_INFO
    [[ $errors_encountered_count -gt 0 ]] && error_color=$C_ERROR
    _log_msg SUMMARY "${error_color}Errores encontrados: $errors_encountered_count${C_NC}"

    if [[ $has_links -eq 1 ]]; then
        _log_msg SUMMARY_H "-----------------------------------------------------"
        _log_msg SUMMARY_H "ENLACES DE DESCARGA GENERADOS"
        _log_msg SUMMARY "(Contraseña ZIP: ${C_WARN}${common_zip_password}${C_NC})"

        for link_data_item in "${GENERATED_LINKS_DATA_ARRAY[@]}"; do
            local parsed_user="" parsed_url=""
            IFS=';' read -ra item_parts <<< "$link_data_item"
            for field_part in "${item_parts[@]}"; do
                case "$field_part" in
                    USER:*) parsed_user="${field_part#USER:}" ;;
                    URL:*) parsed_url="${field_part#URL:}" ;;
                esac
            done
            if [[ -n "$parsed_user" && -n "$parsed_url" ]]; then
                _log_msg SUMMARY "- Usuario: ${C_VERBOSE_INFO}${parsed_user}${C_NC}"
                _log_msg SUMMARY "  URL: ${parsed_url}"
            else
                _log_msg WARN "  Entrada de enlace malformada en resumen (saltada): $link_data_item"
                ((errors_encountered_count++))
            fi
        done
    fi

    _log_msg SUMMARY_H "-----------------------------------------------------"
    _log_msg SUMMARY "Logs del servidor HTTP: ${SSH_SERVERS_DIR_PATH}/<usuario>_server/server.log"
    _log_msg SUMMARY "Registro histórico de enlaces: ${DISTRIBUIR_CLAVES_LINK_LOG_PATH}"
    if [[ $CURRENT_LOG_LEVEL_INTERNAL -lt $LOG_LEVEL_DEBUG ]]; then
         _log_msg SUMMARY "Para más detalles, ejecute con -v o -vv."
    fi
    _log_msg SUMMARY_H "-----------------------------------------------------"
    echo
}

_gu_main_logic() {
    # Chequeos iniciales críticos
    if ! _gu_check_root; then return 1; fi
    if ! _gu_check_dependencies; then return 1; fi

    local proceed=1
    if [[ -n "$FORCE_USER_VAR" ]]; then
        if ! id "$FORCE_USER_VAR" &>/dev/null; then
            _log_msg ERROR "Usuario '$FORCE_USER_VAR' especificado con --force no existe."
            ((errors_encountered_count++)); proceed=0
        fi
    else
        if ! _gu_validate_user_file; then proceed=0; fi
    fi
    if [[ $proceed -eq 0 ]]; then return 1; fi # Salir si chequeos fallan

    if ! _gu_is_system_user "root"; then
        _log_msg ERROR "FALLO CRÍTICO: Protección de usuarios de sistema no detecta 'root'."
        ((errors_encountered_count++)); return 1
    fi
    _log_msg INFO "Verificación de seguridad 'is_system_user' para 'root' completada."

    # --- Lógica Principal ---
    if [[ $FORCE_ALL_FLAG -eq 1 ]]; then
         _log_msg INFO "Forzando regeneración de claves para TODOS los usuarios en '$USER_FILE_VAR' (implica enlaces)."
         _gu_process_users_from_file
         _gu_cleanup_unlisted_users
    elif [[ -n "$FORCE_USER_VAR" ]]; then
         _log_msg INFO "Forzando regeneración de claves para usuario específico: '$FORCE_USER_VAR' (implica enlace)."
         _gu_setup_ssh_keys "$FORCE_USER_VAR" 0
    else
         _log_msg INFO "Iniciando sincronización estándar de usuarios."
         _log_msg INFO "(Enlaces automáticos para usuarios nuevos)."
         _gu_process_users_from_file
         _gu_cleanup_unlisted_users
    fi

    _log_msg INFO "Proceso principal completado."
    return 0
}


# --- Procesamiento de Argumentos y Ejecución ---
# Resetear variables antes de parsear
USER_FILE_VAR="$DEFAULT_USER_FILE_ORIG"
EXPLICIT_LINKS_FLAG=0
FORCE_ALL_FLAG=0
FORCE_USER_VAR=""
verbose_flag_count=0
FORCE_QUIET=0

OPTIND=1
while getopts ":f:vhq-:" opt_char; do
    case $opt_char in
        f) USER_FILE_VAR="$OPTARG" ;;
        v) verbose_flag_count=$(( verbose_flag_count + 1 )) ;;
        q) FORCE_QUIET=1 ;;
        h) _gu_usage; exit 0 ;;
        -)
            LONG_OPTARG="${OPTARG}"
            case $LONG_OPTARG in
                force-all) FORCE_ALL_FLAG=1 ;;
                force)
                    val_for_force_user="${!OPTIND}"
                    if [[ -z "$val_for_force_user" || "$val_for_force_user" == -* ]]; then
                        # Usar echo directo para errores de parseo que deben verse siempre
                        echo -e "${C_ERROR}Opción --force requiere un argumento (nombre de usuario).${C_NC}" >&2
                        _gu_usage; exit 1
                    fi
                    FORCE_USER_VAR="$val_for_force_user"
                    OPTIND=$((OPTIND + 1))
                    ;;
                links) EXPLICIT_LINKS_FLAG=1 ;;
                quiet) FORCE_QUIET=1 ;;
                help) _gu_usage; exit 0 ;;
                *) echo -e "${C_ERROR}Opción larga inválida: --$LONG_OPTARG${C_NC}" >&2; _gu_usage; exit 1 ;;
            esac ;;
        \?) echo -e "${C_ERROR}Opción corta inválida: -$OPTARG${C_NC}" >&2; _gu_usage; exit 1 ;;
        :) echo -e "${C_ERROR}Opción -$OPTARG requiere un argumento.${C_NC}" >&2; _gu_usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# ---- Determinar nivel de log final ----
# La variable global REAL es CURRENT_LOG_LEVEL_INTERNAL
if [[ $FORCE_QUIET -eq 1 ]]; then
    CURRENT_LOG_LEVEL_INTERNAL=$LOG_LEVEL_ERROR
    if [[ $verbose_flag_count -gt 0 ]]; then
         # Advertir solo si el nivel permite WARN (o sea, si NO es QUIET)
         # Pero como ya forzamos QUIET, esta advertencia nunca se mostraría con _log_msg.
         # Usar echo directo si queremos que se vea.
          echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${C_WARN}[WARN ]${C_NC} Se usó -q/--quiet junto con -v/-vv. Modo silencioso tiene precedencia." >&2
    fi
elif [[ $verbose_flag_count -eq 1 ]]; then
    CURRENT_LOG_LEVEL_INTERNAL=$LOG_LEVEL_INFO   # -v: Elevar a INFO
elif [[ $verbose_flag_count -ge 2 ]]; then
    CURRENT_LOG_LEVEL_INTERNAL=$LOG_LEVEL_DEBUG  # -vv: Elevar a DEBUG
else
    # Si no hay -q, -v, ni -vv, mantener el default QUIET
     CURRENT_LOG_LEVEL_INTERNAL=$LOG_LEVEL_ERROR
fi

# Loguear opciones finales solo si el nivel es DEBUG
# Necesita usar CURRENT_LOG_LEVEL_INTERNAL para la condición
if [[ $CURRENT_LOG_LEVEL_INTERNAL -ge $LOG_LEVEL_DEBUG ]]; then
    _log_msg DEBUG "Nivel de log final: $CURRENT_LOG_LEVEL_INTERNAL (Quiet=-1, Err=0, Warn=1, Info=2, Verb=3, Debug=4)"
    _log_msg DEBUG "Opciones finales: USER_FILE='$USER_FILE_VAR', EXPLICIT_LINKS_FLAG=$EXPLICIT_LINKS_FLAG, FORCE_ALL_FLAG=$FORCE_ALL_FLAG, FORCE_USER_VAR='$FORCE_USER_VAR'"
fi

# --- Ejecución ---
# Llamar a la lógica principal y capturar si falló
main_logic_return_code=0
if ! _gu_main_logic; then
    main_logic_return_code=1
    _log_msg DEBUG "La función _gu_main_logic retornó un código de error."
fi

# Siempre imprimir resumen
_gu_print_summary

# Determinar código de salida final
final_exit_code=0
if [[ $errors_encountered_count -gt 0 || $main_logic_return_code -ne 0 ]]; then
    final_exit_code=1
fi

if [[ $final_exit_code -eq 0 ]]; then
    _log_msg INFO "Ejecución completada sin errores." # Se verá con -v o -vv
    exit 0
else
    _log_msg ERROR "Ejecución completada con errores." # Se verá siempre (excepto si el log falla!)
    exit 1
fi
