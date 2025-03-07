#!/bin/bash

# Script para realizar respaldos de datos importantes

BACKUP_DIR="/home/security/data/backups"
DATE=$(date +%Y-%m-%d)
BACKUP_FILE="$BACKUP_DIR/backup-$DATE.tar.gz"

# Crear directorio de respaldos si no existe
mkdir -p $BACKUP_DIR

# Directorio temporal para recopilar archivos a respaldar
TEMP_DIR=$(mktemp -d)

# Copiar archivos importantes
echo "[+] Recopilando archivos para el respaldo..."
mkdir -p $TEMP_DIR/workspace
mkdir -p $TEMP_DIR/reports
mkdir -p $TEMP_DIR/scripts

# Respaldar directorio de trabajo
cp -r /home/security/workspace/* $TEMP_DIR/workspace/ 2>/dev/null

# Respaldar informes
cp -r /home/security/reports/* $TEMP_DIR/reports/ 2>/dev/null

# Respaldar scripts personalizados (solo los personalizados, no los del sistema)
find /home/security/scripts -type f -not -name "*.sh" -exec cp {} $TEMP_DIR/scripts/ \; 2>/dev/null

# Crear archivo de respaldo
echo "[+] Creando archivo de respaldo: $BACKUP_FILE"
tar -czf $BACKUP_FILE -C $TEMP_DIR .

# Limpiar directorio temporal
rm -rf $TEMP_DIR

# Establecer permisos correctos
chmod 600 $BACKUP_FILE
chown security:security $BACKUP_FILE

echo "[+] Respaldo completado: $BACKUP_FILE"
echo "[+] Tamaño del respaldo: $(du -h $BACKUP_FILE | cut -f1)"

# Listar respaldos existentes
echo "[+] Respaldos disponibles:"
ls -lh $BACKUP_DIR

# Opcional: Eliminar respaldos antiguos (más de 30 días)
find $BACKUP_DIR -name "backup-*.tar.gz" -type f -mtime +30 -delete
