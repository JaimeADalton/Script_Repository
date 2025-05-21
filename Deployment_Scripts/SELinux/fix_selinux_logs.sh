#!/bin/bash
#
# fix_selinux_logs.sh - Script para corregir contextos SELinux en logs
#
# Este script soluciona problemas comunes con contextos SELinux en logs
# de sistemas RHEL/CentOS, permitiendo que los servicios escriban correctamente.
#
# Uso: sudo ./fix_selinux_logs.sh
#

# Verificar ejecución como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# Crear archivo de log
LOG_FILE="/tmp/selinux_log_fix_$(date +%Y%m%d_%H%M%S).log"
exec &> >(tee -a "$LOG_FILE")

echo "====================================================="
echo "Iniciando corrección de contextos SELinux para logs"
echo "Fecha: $(date)"
echo "Log: $LOG_FILE"
echo "====================================================="
echo

# Paso 1: Verificar dependencias necesarias
echo "Paso 1: Verificando dependencias necesarias"
if ! command -v semanage &> /dev/null; then
    echo "  ADVERTENCIA: 'semanage' no está disponible"
    echo "  Instale policycoreutils-python-utils: dnf install policycoreutils-python-utils"
    SEMANAGE_AVAILABLE=false
else
    echo "  'semanage' disponible"
    SEMANAGE_AVAILABLE=true
fi

if ! command -v ausearch &> /dev/null; then
    echo "  ADVERTENCIA: 'ausearch' no está disponible"
    echo "  Instale audit: dnf install audit"
    AUSEARCH_AVAILABLE=false
else
    echo "  'ausearch' disponible"
    AUSEARCH_AVAILABLE=true
fi

if ! command -v restorecon &> /dev/null; then
    echo "  ERROR: 'restorecon' no está disponible"
    echo "  Instale policycoreutils: dnf install policycoreutils"
    echo "  Abortando ejecución"
    exit 1
else
    echo "  'restorecon' disponible"
fi
echo

# Paso 2: Eliminar regla genérica incorrecta
echo "Paso 2: Verificando reglas de contexto personalizadas"
if [ "$SEMANAGE_AVAILABLE" = true ]; then
    echo "  Buscando regla de equivalencia incorrecta para /var/log(/.*)?..."
    if semanage fcontext -C -l | grep -qE '^\/var\/log\(\/\.\*\)\?\s+all files\s+system_u:object_r:var_log_t:s0'; then
        echo "  ENCONTRADA regla incorrecta: /var/log(/.*)? -> var_log_t"
        echo "  Eliminando regla..."
        if semanage fcontext -d "/var/log(/.*)?"; then
            echo "  Regla eliminada exitosamente"
        else
            echo "  ERROR: No se pudo eliminar la regla"
        fi
    else
        echo "  No se encontró regla incorrecta (esto es bueno)"
    fi
else
    echo "  No se puede verificar reglas sin 'semanage'"
fi
echo

# Paso 3: Restaurar contextos en /var/log
echo "Paso 3: Restaurando contextos en /var/log"
echo "  Estado actual de contextos importantes:"
ls -lZd /var/log/audit 2>/dev/null || echo "  /var/log/audit no existe"
ls -lZ /var/log/lastlog 2>/dev/null || echo "  /var/log/lastlog no existe"
ls -lZ /var/log/wtmp 2>/dev/null || echo "  /var/log/wtmp no existe"

echo "  Aplicando contextos correctos con restorecon..."
restorecon -Rv /var/log
echo

# Paso 4: Verificar y crear directorio rsyslog si es necesario
echo "Paso 4: Verificando directorio /var/lib/rsyslog"
if [ ! -d "/var/lib/rsyslog" ]; then
    echo "  Creando directorio /var/lib/rsyslog..."
    mkdir -p /var/lib/rsyslog
    chown root:root /var/lib/rsyslog
    chmod 700 /var/lib/rsyslog
fi

echo "  Restaurando contexto para /var/lib/rsyslog..."
restorecon -Rv /var/lib/rsyslog
echo

# Paso ADICIONAL: Restaurar contextos en otros directorios problemáticos identificados
echo "Paso ADICIONAL: Restaurando contextos en otros directorios problemáticos"
echo "  Restaurando contextos para /var/lib/systemd/timers/..."
restorecon -Rv /var/lib/systemd/timers/
echo "  Restaurando contextos para /var/account/..."
restorecon -Rv /var/account/
echo "  Restaurando contextos para /var/lib/logrotate/..."
restorecon -Rv /var/lib/logrotate/
echo "  Restaurando contextos para /var/lib/systemd/linger/..."
restorecon -Rv /var/lib/systemd/linger/
echo "  Restaurando contextos para /var/lib/sss/..."
restorecon -Rv /var/lib/sss/
echo "  Restaurando contextos para /var/lib/systemd/ (más general)..."
restorecon -Rv /var/lib/systemd/
echo

# Paso 5: Verificar contextos críticos después de restauración
echo "Paso 5: Verificando contextos críticos después de restauración"
verify_context() {
    local path="$1"
    local expected_type="$2"

    if [ ! -e "$path" ]; then
        echo "  $path no existe"
        return
    fi

    local current_type
    if [ -d "$path" ]; then
        current_type=$(ls -Zd "$path" | awk -F: '{print $3}')
    else
        current_type=$(ls -Z "$path" | awk -F: '{print $3}')
    fi

    if [ "$current_type" = "$expected_type" ]; then
        echo "  $path: Correcto ($current_type)"
    else
        echo "  $path: INCORRECTO - Actual: $current_type, Esperado: $expected_type"

        if [ "$SEMANAGE_AVAILABLE" = true ]; then
            echo "  Intentando corregir con semanage..."
            if [ -d "$path" ]; then
                semanage fcontext -a -t "$expected_type" "$path(/.*)?"
            else
                semanage fcontext -a -t "$expected_type" "$path"
            fi
            restorecon -v "$path"
        fi
    fi
}

verify_context "/var/log/audit" "auditd_log_t"
verify_context "/var/log/lastlog" "lastlog_t"
verify_context "/var/log/wtmp" "wtmp_t"
verify_context "/var/log/dnf.log" "rpm_log_t"
verify_context "/var/lib/rsyslog" "syslogd_var_lib_t"
echo

# Paso 6: Configurar WorkDirectory en rsyslog si existe
echo "Paso 6: Verificando configuración de rsyslog"
if command -v rsyslogd &> /dev/null; then
    if ! grep -q "workDirectory=" /etc/rsyslog.conf /etc/rsyslog.d/* 2>/dev/null; then
        echo "  workDirectory no está configurado en rsyslog"
        echo "  Añadiendo configuración a /etc/rsyslog.conf..."
        echo '# Configuración añadida por fix_selinux_logs.sh' >> /etc/rsyslog.conf
        echo 'workDirectory="/var/lib/rsyslog"' >> /etc/rsyslog.conf
        echo "  Configuración añadida"
    else
        echo "  WorkDirectory ya está configurado en rsyslog"
    fi
else
    echo "  rsyslog no está instalado"
fi
echo

# Paso 7: Reiniciar servicios relevantes
echo "Paso 7: Reiniciando servicios relevantes"
if systemctl is-active --quiet rsyslog; then
    echo "  Reiniciando rsyslog..."
    systemctl restart rsyslog
    echo "  rsyslog reiniciado"
else
    echo "  rsyslog no está activo"
fi

echo "  Para auditd, se recomienda:"
echo "  - Enviar SIGHUP: kill -SIGHUP \$(pidof auditd)"
echo "  - O reiniciar el sistema"
echo

# Paso 8: Verificar denegaciones AVC recientes
echo "Paso 8: Verificando denegaciones AVC recientes"
if [ "$AUSEARCH_AVAILABLE" = true ]; then
    echo "  Esperando 5 segundos para que los servicios se estabilicen..."
    sleep 5

    echo "  Buscando denegaciones AVC recientes..."
    AVC_OUTPUT=$(ausearch -m avc -ts recent 2>/dev/null)
    if [ -n "$AVC_OUTPUT" ]; then
        echo "  Se encontraron denegaciones AVC recientes:"
        echo "$AVC_OUTPUT"

        if echo "$AVC_OUTPUT" | grep -q 'comm="in:imjournal".*name="/"'; then
            echo
            echo "  PROBLEMA DETECTADO: rsyslog intentando escribir en /"
            echo "  Si el problema persiste después de reiniciar:"
            echo "  - Verifique que WorkDirectory es /var/lib/rsyslog"
            echo "  - Considere habilitar daemons_dump_core: setsebool -P daemons_dump_core 1"
        fi
    else
        echo "  No se encontraron denegaciones AVC recientes"
    fi
else
    echo "  No se puede verificar AVCs sin ausearch"
fi
echo

# Paso 9: Recomendaciones finales
echo "Paso 9: Recomendaciones finales"
echo "  Si los problemas persisten:"
echo "  1. Use 'sealert -a /var/log/audit/audit.log' para análisis detallado"
echo "  2. Para problemas generalizados, considere un re-etiquetado completo:"
echo "     touch /.autorelabel && reboot"
echo "  3. Verifique errores en 'journalctl -xe'"
echo

echo "====================================================="
echo "Corrección de contextos SELinux completada"
echo "Log guardado en: $LOG_FILE"
echo "====================================================="
