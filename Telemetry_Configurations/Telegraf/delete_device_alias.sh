#!/usr/bin/env bash

set -e

INFLUX_HOST="localhost"
INFLUX_PORT="8086"
DB="telegraf"
RP="un_ano"

read -rp "Measurement: " MEAS
read -rp "device_alias exacto: " ALIAS

echo
echo "Database        : $DB"
echo "RetentionPolicy : $RP"
echo "Measurement     : $MEAS"
echo "device_alias    : $ALIAS"
echo

echo "Series que se van a eliminar:"
echo "--------------------------------"
influx -host "$INFLUX_HOST" -port "$INFLUX_PORT" -database "$DB" -execute \
  "SHOW SERIES FROM \"$RP\".\"$MEAS\" WHERE \"device_alias\" = '$ALIAS';"

echo
read -rp "¿Confirmas el borrado? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Operación cancelada."
  exit 0
fi

echo
echo "Ejecutando DELETE..."
influx -host "$INFLUX_HOST" -port "$INFLUX_PORT" -database "$DB" -execute \
  "DELETE FROM \"$RP\".\"$MEAS\" WHERE \"device_alias\" = '$ALIAS';"

echo "Borrado completado."

echo
echo "Verificación:"
influx -host "$INFLUX_HOST" -port "$INFLUX_PORT" -database "$DB" -execute \
  "SHOW SERIES FROM \"$RP\".\"$MEAS\" WHERE \"device_alias\" = '$ALIAS';"
