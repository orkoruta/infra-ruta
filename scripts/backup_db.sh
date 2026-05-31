#!/usr/bin/env bash
# backup_db.sh
#
# Genera un backup comprimido del schema 'ruta' en PostgreSQL usando pg_dump | gzip.
# El archivo resultante tiene el formato ruta_backup_YYYYMMDD_HHMMSS.sql.gz.
#
# Variables de entorno:
#   DB_HOST            Host de la BD                 (requerido; sin default en prod)
#   DB_PORT            Puerto de la BD               (requerido; sin default en prod)
#   DB_NAME            Nombre de la BD               (requerido; sin default en prod)
#   DB_USER            Usuario de la BD              (requerido; sin default en prod)
#   DB_PASSWORD        Password de la BD             (requerido)
#   BACKUP_DIR         Directorio de salida          (default: ./backups)
#   BACKUP_KEEP_DAYS   Días de retención de backups  (default: 7)
#
# Uso: bash scripts/backup_db.sh
# Ejemplo local (dev):
#   DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
#   DB_PASSWORD=secret bash scripts/backup_db.sh

set -euo pipefail

# ─────────────────────────────────────────────
# Variables de entorno (sin defaults hardcodeados en prod)
# ─────────────────────────────────────────────
DB_HOST="${DB_HOST:?'ERROR: DB_HOST es requerido'}"
DB_PORT="${DB_PORT:?'ERROR: DB_PORT es requerido'}"
DB_NAME="${DB_NAME:?'ERROR: DB_NAME es requerido'}"
DB_USER="${DB_USER:?'ERROR: DB_USER es requerido'}"
DB_PASSWORD="${DB_PASSWORD:?'ERROR: DB_PASSWORD es requerido'}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"

export PGPASSWORD="$DB_PASSWORD"

# ─────────────────────────────────────────────
# Verificar dependencias
# ─────────────────────────────────────────────
for cmd in pg_dump gzip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[ERROR] '$cmd' es requerido pero no está instalado." >&2
    echo "        Instálalo con: sudo apt install postgresql-client gzip" >&2
    exit 1
  fi
done

# ─────────────────────────────────────────────
# Verificar compatibilidad de versión pg_dump vs servidor
# pg_dump debe ser >= versión del servidor para hacer el dump correctamente.
# Si hay mismatch, abortar para evitar dumps corruptos o incompletos.
# Para forzar ejecución (bajo su propio riesgo), exportar PGDUMP_SKIP_VERSION_CHECK=1
# ─────────────────────────────────────────────
if [[ "${PGDUMP_SKIP_VERSION_CHECK:-0}" != "1" ]]; then
  LOCAL_VERSION=$(pg_dump --version | grep -oP '\d+' | head -1)
  SERVER_VERSION=$(PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -A -c "SHOW server_version_num;" 2>/dev/null || echo "0")
  SERVER_MAJOR=$(( SERVER_VERSION / 10000 ))

  if [[ "$LOCAL_VERSION" -lt "$SERVER_MAJOR" ]]; then
    echo "[ERROR] Incompatibilidad de versión:" >&2
    echo "        pg_dump local: ${LOCAL_VERSION}.x" >&2
    echo "        Servidor PostgreSQL: ${SERVER_MAJOR}.x" >&2
    echo "" >&2
    echo "        Instala postgresql-client-${SERVER_MAJOR} para hacer backups." >&2
    echo "        Ver: https://www.postgresql.org/download/linux/ubuntu/" >&2
    echo "" >&2
    echo "        Para saltarte esta verificación (bajo tu propio riesgo):" >&2
    echo "        PGDUMP_SKIP_VERSION_CHECK=1 bash scripts/backup_db.sh" >&2
    exit 1
  fi
fi

# ─────────────────────────────────────────────
# Crear directorio de backup si no existe
# ─────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"

# ─────────────────────────────────────────────
# Generar nombre del archivo de backup
# ─────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/ruta_backup_${TIMESTAMP}.sql.gz"

echo "[INFO]  === Backup BD RUTA ==="
echo "[INFO]  Inicio   : $(date '+%Y-%m-%d %H:%M:%S')"
echo "[INFO]  Host     : ${DB_HOST}:${DB_PORT}"
echo "[INFO]  BD       : ${DB_NAME}  (schema: ruta)"
echo "[INFO]  Archivo  : ${BACKUP_FILE}"
echo "[INFO]  Retención: ${BACKUP_KEEP_DAYS} días"
echo ""
echo "[INFO]  Ejecutando pg_dump | gzip ..."

# ─────────────────────────────────────────────
# Ejecutar pg_dump y comprimir con gzip
# ─────────────────────────────────────────────
if ! pg_dump \
  --schema=ruta \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  "$DB_NAME" \
  | gzip > "$BACKUP_FILE"; then
  echo "" >&2
  echo "[ERROR] pg_dump falló. Revisa la conexión y las credenciales." >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

# ─────────────────────────────────────────────
# Reportar tamaño del archivo
# ─────────────────────────────────────────────
FILE_SIZE="$(du -sh "$BACKUP_FILE" | cut -f1)"
echo "[OK]    Backup completado exitosamente."
echo "[INFO]  Archivo : ${BACKUP_FILE}"
echo "[INFO]  Tamaño  : ${FILE_SIZE}"

# ─────────────────────────────────────────────
# Retención: eliminar backups más viejos que BACKUP_KEEP_DAYS días
# ─────────────────────────────────────────────
echo ""
echo "[INFO]  Aplicando política de retención (${BACKUP_KEEP_DAYS} días) en ${BACKUP_DIR} ..."

DELETED=0
while IFS= read -r old_file; do
  echo "[INFO]  Eliminando backup expirado: ${old_file}"
  rm -f "$old_file"
  DELETED=$((DELETED + 1))
done < <(find "$BACKUP_DIR" -maxdepth 1 -name 'ruta_backup_*.sql.gz' -mtime +"$BACKUP_KEEP_DAYS" 2>/dev/null || true)

if [[ "$DELETED" -eq 0 ]]; then
  echo "[INFO]  Sin backups expirados para eliminar."
else
  echo "[INFO]  ${DELETED} backup(s) expirado(s) eliminado(s)."
fi

echo ""
echo "[OK]    Proceso finalizado: $(date '+%Y-%m-%d %H:%M:%S')"
exit 0
