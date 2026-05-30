#!/usr/bin/env bash
# restore_db.sh
#
# Restaura un backup del schema 'ruta' desde un archivo .dump generado con backup_db.sh.
# Muestra advertencia y solicita confirmación explícita antes de sobreescribir la BD.
# Ejecuta verificación post-restore contando filas en tablas clave.
#
# Variables de entorno:
#   DB_HOST        Host de la BD          (default: 149.130.168.24)
#   DB_PORT        Puerto de la BD        (default: 26432)
#   DB_NAME        Nombre de la BD        (default: rutadb)
#   DB_USER        Usuario de la BD       (default: ruta)
#   PGPASSWORD     Password de la BD      (REQUERIDO)
#
# Uso: bash scripts/restore_db.sh <backup_file.dump>
# Ejemplo: PGPASSWORD=secret bash scripts/restore_db.sh ruta_backup_20260101_120000.dump

set -euo pipefail

# ─────────────────────────────────────────────
# Colores para mensajes
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No color

# ─────────────────────────────────────────────
# Verificar argumento: archivo de backup
# ─────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "ERROR: Falta el argumento: archivo de backup." >&2
  echo "Uso: bash scripts/restore_db.sh <backup_file.dump>" >&2
  exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: El archivo de backup no existe: $BACKUP_FILE" >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Variables con defaults
# ─────────────────────────────────────────────
DB_HOST="${DB_HOST:-149.130.168.24}"
DB_PORT="${DB_PORT:-26432}"
DB_NAME="${DB_NAME:-rutadb}"
DB_USER="${DB_USER:-ruta}"

# ─────────────────────────────────────────────
# Verificar password requerido
# ─────────────────────────────────────────────
if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: La variable PGPASSWORD es requerida." >&2
  echo "Uso: PGPASSWORD=<password> bash scripts/restore_db.sh <backup_file.dump>" >&2
  exit 1
fi

export PGPASSWORD

# ─────────────────────────────────────────────
# Verificar dependencias
# ─────────────────────────────────────────────
for cmd in pg_restore psql; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' es requerido pero no está instalado." >&2
    echo "Instálalo con: sudo apt install postgresql-client" >&2
    exit 1
  fi
done

# ─────────────────────────────────────────────
# Mostrar advertencia y solicitar confirmación
# ─────────────────────────────────────────────
FILE_SIZE="$(du -sh "$BACKUP_FILE" | cut -f1)"

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ⚠️   ADVERTENCIA                      ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}  ESTO SOBREESCRIBIRÁ LA BD. Los datos actuales del schema${NC}"
echo -e "${YELLOW}  'ruta' serán eliminados y reemplazados por este backup.${NC}"
echo ""
echo "  Host    : $DB_HOST:$DB_PORT"
echo "  BD      : $DB_NAME  (schema: ruta)"
echo "  Archivo : $BACKUP_FILE  ($FILE_SIZE)"
echo ""
echo -e "${RED}  Esta operación NO se puede deshacer.${NC}"
echo ""
echo -n "  ¿Continuar? (escribe 'si' para confirmar): "
read -r CONFIRM

if [[ "$CONFIRM" != "si" ]]; then
  echo ""
  echo "Restore cancelado. No se realizaron cambios."
  exit 0
fi

echo ""
echo "=== Restaurando backup... ==="
echo ""

# ─────────────────────────────────────────────
# Ejecutar pg_restore
# ─────────────────────────────────────────────
if ! pg_restore \
  --clean \
  --if-exists \
  --schema=ruta \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  "$BACKUP_FILE"; then
  echo "" >&2
  echo -e "${RED}ERROR: pg_restore falló. Revisa los mensajes anteriores.${NC}" >&2
  exit 1
fi

echo ""
echo "pg_restore completado. Ejecutando verificación post-restore..."

# ─────────────────────────────────────────────
# Verificación post-restore: contar filas en tablas clave
# ─────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo "Conteo de filas en tablas clave (schema ruta):"
echo "─────────────────────────────────────────────"

VERIFICATION=$(psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -A -t \
  <<SQL
SELECT 'users' AS tabla, COUNT(*) FROM ruta.users
UNION ALL SELECT 'orders', COUNT(*) FROM ruta.orders
UNION ALL SELECT 'clients', COUNT(*) FROM ruta.clients;
SQL
)

if [[ -z "$VERIFICATION" ]]; then
  echo "" >&2
  echo -e "${YELLOW}AVISO: La consulta de verificación no retornó datos.${NC}" >&2
  echo "  Verifica manualmente el estado de la BD." >&2
  exit 1
fi

# Mostrar resultados formateados
echo ""
printf "  %-20s %s\n" "Tabla" "Filas"
printf "  %-20s %s\n" "--------------------" "-----"
while IFS='|' read -r tabla filas; do
  printf "  %-20s %s\n" "$tabla" "$filas"
done <<< "$VERIFICATION"
echo ""

echo -e "${GREEN}✓ Restore completado exitosamente.${NC}"
echo ""
exit 0
