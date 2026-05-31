#!/usr/bin/env bash
# restore_db.sh
#
# Restaura un backup del schema 'ruta' desde un archivo .sql.gz generado por backup_db.sh.
# Muestra advertencia y solicita confirmación antes de sobreescribir la BD.
# Ejecuta verificación post-restore contando filas en tablas clave.
#
# Variables de entorno:
#   DB_HOST        Host de la BD          (requerido)
#   DB_PORT        Puerto de la BD        (requerido)
#   DB_NAME        Nombre de la BD        (requerido)
#   DB_USER        Usuario de la BD       (requerido)
#   DB_PASSWORD    Password de la BD      (requerido)
#
# Uso:   bash scripts/restore_db.sh <backup_file.sql.gz> [--yes]
# Flags: --yes  Omite la confirmación interactiva (útil en CI/CD)
#
# Ejemplo:
#   DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
#   DB_PASSWORD=secret bash scripts/restore_db.sh backups/ruta_backup_20260530_120000.sql.gz

set -euo pipefail

# ─────────────────────────────────────────────
# Parsear argumentos
# ─────────────────────────────────────────────
BACKUP_FILE=""
AUTO_YES=false

for arg in "$@"; do
  case "$arg" in
    --yes) AUTO_YES=true ;;
    -*) echo "[ERROR] Opción desconocida: $arg" >&2; exit 1 ;;
    *)
      if [[ -z "$BACKUP_FILE" ]]; then
        BACKUP_FILE="$arg"
      else
        echo "[ERROR] Argumento inesperado: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$BACKUP_FILE" ]]; then
  echo "[ERROR] Falta el argumento: archivo de backup." >&2
  echo "Uso: bash scripts/restore_db.sh <backup_file.sql.gz> [--yes]" >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Validar archivo de backup
# ─────────────────────────────────────────────
if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "[ERROR] El archivo de backup no existe: ${BACKUP_FILE}" >&2
  exit 1
fi

if [[ "$BACKUP_FILE" != *.sql.gz ]]; then
  echo "[ERROR] El archivo debe terminar en .sql.gz : ${BACKUP_FILE}" >&2
  echo "        Solo se aceptan backups generados por backup_db.sh." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Variables de entorno (sin defaults hardcodeados en prod)
# ─────────────────────────────────────────────
DB_HOST="${DB_HOST:?'ERROR: DB_HOST es requerido'}"
DB_PORT="${DB_PORT:?'ERROR: DB_PORT es requerido'}"
DB_NAME="${DB_NAME:?'ERROR: DB_NAME es requerido'}"
DB_USER="${DB_USER:?'ERROR: DB_USER es requerido'}"
DB_PASSWORD="${DB_PASSWORD:?'ERROR: DB_PASSWORD es requerido'}"

export PGPASSWORD="$DB_PASSWORD"

# ─────────────────────────────────────────────
# Verificar dependencias
# ─────────────────────────────────────────────
for cmd in gunzip psql; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] '$cmd' es requerido pero no está instalado." >&2
    echo "        Instálalo con: sudo apt install gzip postgresql-client" >&2
    exit 1
  fi
done

# ─────────────────────────────────────────────
# Mostrar advertencia y solicitar confirmación
# ─────────────────────────────────────────────
FILE_SIZE="$(du -sh "$BACKUP_FILE" | cut -f1)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   ADVERTENCIA                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  ESTO SOBREESCRIBIRÁ LA BD. Los datos actuales del schema"
echo "  'ruta' serán eliminados y reemplazados por este backup."
echo ""
echo "  Host    : ${DB_HOST}:${DB_PORT}"
echo "  BD      : ${DB_NAME}  (schema: ruta)"
echo "  Archivo : ${BACKUP_FILE}  (${FILE_SIZE})"
echo ""
echo "  Esta operacion NO se puede deshacer."
echo ""

if [[ "$AUTO_YES" == "true" ]]; then
  echo "[INFO]  Confirmación automática (--yes)."
else
  echo -n "  ¿Continuar? (escribe 'si' para confirmar): "
  read -r CONFIRM
  if [[ "$CONFIRM" != "si" ]]; then
    echo ""
    echo "[INFO]  Restore cancelado. No se realizaron cambios."
    exit 0
  fi
fi

echo ""
echo "[INFO]  === Restaurando backup ==="
echo "[INFO]  Inicio : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ─────────────────────────────────────────────
# Ejecutar gunzip + psql para restaurar
# ─────────────────────────────────────────────
echo "[INFO]  Ejecutando gunzip | psql ..."

if ! gunzip -c "$BACKUP_FILE" | psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -v ON_ERROR_STOP=1; then
  echo "" >&2
  echo "[ERROR] psql falló durante el restore. Revisa los mensajes anteriores." >&2
  exit 1
fi

echo ""
echo "[INFO]  Restore SQL completado. Ejecutando verificación post-restore..."

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
SELECT 'clients' AS tabla, COUNT(*) FROM ruta.clients
UNION ALL SELECT 'users', COUNT(*) FROM ruta.users
UNION ALL SELECT 'orders', COUNT(*) FROM ruta.orders;
SQL
)

if [[ -z "$VERIFICATION" ]]; then
  echo "" >&2
  echo "[AVISO] La consulta de verificación no retornó datos." >&2
  echo "        Verifica manualmente el estado de la BD." >&2
  exit 1
fi

echo ""
printf "  %-20s %s\n" "Tabla" "Filas"
printf "  %-20s %s\n" "--------------------" "-----"
while IFS='|' read -r tabla filas; do
  printf "  %-20s %s\n" "$tabla" "$filas"
done <<< "$VERIFICATION"
echo ""

echo "[OK]    Restore completado exitosamente: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
exit 0
