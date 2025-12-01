#!/bin/bash
# =============================================================================
# NOC-ISP Stack - Script de Despliegue
# =============================================================================
# Uso: ./deploy.sh
# =============================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones de logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================================================="
echo "  NOC-ISP Stack - Despliegue Automatizado"
echo "  LibreNMS + Oxidized + Nginx"
echo "============================================================================="
echo ""

# =============================================================================
# FASE 1: Validación de prerrequisitos
# =============================================================================
log_info "Fase 1: Validando prerrequisitos..."

# Verificar Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker no está instalado"
    exit 1
fi
log_success "Docker disponible: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# Verificar Docker Compose
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose no está disponible"
    exit 1
fi
log_success "Docker Compose disponible: $(docker compose version --short)"

# Verificar archivos necesarios
REQUIRED_FILES=(".env" "librenms.env" "docker-compose.yml" "nginx/nginx.conf" "nginx/ssl/cert.pem" "nginx/ssl/key.pem" "oxidized/config" "oxidized/router.db")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        log_error "Archivo requerido no encontrado: $file"
        exit 1
    fi
done
log_success "Todos los archivos de configuración presentes"

# Verificar puertos
REQUIRED_PORTS=(80 443 514 162 8888)
for port in "${REQUIRED_PORTS[@]}"; do
    if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        log_warning "Puerto $port ya está en uso - puede haber conflictos"
    fi
done
log_success "Puertos verificados"

# =============================================================================
# FASE 2: Preparación del entorno
# =============================================================================
log_info "Fase 2: Preparando entorno..."

# Crear directorios necesarios
mkdir -p librenms db redis
log_success "Directorios de datos creados"

# Establecer permisos correctos para Oxidized
chmod 755 oxidized
chmod 644 oxidized/config oxidized/router.db
log_success "Permisos configurados"

# =============================================================================
# FASE 3: Limpieza de despliegues anteriores
# =============================================================================
log_info "Fase 3: Limpiando despliegues anteriores..."

# Detener y eliminar contenedores existentes del proyecto
docker compose down --remove-orphans 2>/dev/null || true

# Esperar un momento para que los recursos se liberen
sleep 2
log_success "Limpieza completada"

# =============================================================================
# FASE 4: Despliegue de servicios
# =============================================================================
log_info "Fase 4: Desplegando servicios..."

# Pull de imágenes
log_info "Descargando imágenes Docker..."
docker compose pull --quiet

# Iniciar servicios
log_info "Iniciando contenedores..."
docker compose up -d

# =============================================================================
# FASE 5: Verificación de salud
# =============================================================================
log_info "Fase 5: Verificando salud de servicios..."

# Función para esperar servicio
wait_for_service() {
    local container=$1
    local max_wait=$2
    local waited=0
    
    echo -n "  Esperando $container"
    while [[ $waited -lt $max_wait ]]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")
        if [[ "$status" == "healthy" ]]; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        elif [[ "$status" == "unhealthy" ]]; then
            echo -e " ${RED}✗${NC}"
            return 1
        fi
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done
    echo -e " ${YELLOW}timeout${NC}"
    return 1
}

# Esperar servicios críticos
wait_for_service "librenms_db" 60
wait_for_service "librenms_redis" 30

# LibreNMS tarda más en arrancar (migraciones de DB, etc)
log_info "Esperando a LibreNMS (puede tardar 2-3 minutos)..."
wait_for_service "librenms" 180

# =============================================================================
# FASE 6: Configuración inicial de LibreNMS
# =============================================================================
log_info "Fase 6: Configuración inicial de LibreNMS..."

# Esperar un poco más para asegurar que todo está listo
sleep 10

# Crear usuario administrador
log_info "Creando usuario administrador..."
if docker compose exec -T librenms lnms user:add admin -p 'Admin123!' -r admin -e admin@noc.local 2>/dev/null; then
    log_success "Usuario admin creado (password: Admin123!)"
else
    log_warning "El usuario admin ya existe o hubo un error"
fi

# =============================================================================
# FASE 7: Verificación final
# =============================================================================
log_info "Fase 7: Verificación final..."

echo ""
echo "Estado de contenedores:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# =============================================================================
# RESUMEN
# =============================================================================
echo ""
echo "============================================================================="
echo -e "  ${GREEN}✓ DESPLIEGUE COMPLETADO${NC}"
echo "============================================================================="
echo ""
echo "  Acceso Web:"
echo "    URL:      https://localhost (o la IP del servidor)"
echo "    Usuario:  admin"
echo "    Password: Admin123!"
echo ""
echo "  Servicios adicionales:"
echo "    Oxidized API: http://localhost:8888"
echo "    Syslog:       UDP/TCP 514"
echo "    SNMP Traps:   UDP/TCP 162"
echo ""
echo "  Próximos pasos:"
echo "    1. Accede a la web y cambia la contraseña"
echo "    2. Genera un token API en Settings > API > API Settings"
echo "    3. Ejecuta: ./configure-oxidized.sh <TOKEN>"
echo "    4. Añade tus dispositivos de red"
echo ""
echo "  Comandos útiles:"
echo "    Ver logs:          docker compose logs -f"
echo "    Ver logs LibreNMS: docker compose logs -f librenms"
echo "    Entrar a shell:    docker compose exec librenms bash"
echo "    Detener todo:      docker compose down"
echo "    Reiniciar:         docker compose restart"
echo ""
echo "============================================================================="
