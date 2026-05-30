#!/usr/bin/env bash
# backup_db.sh
#
# Genera un backup del schema 'ruta' en PostgreSQL usando pg_dump --format=custom.
# Opcionalmente sube el archivo a S3 o OCI Object Storage si $BACKUP_BUCKET está definido.
#
# Variables de entorno:
#   DB_HOST        Host de la BD          (default: 149.130.168.24)
#   DB_PORT        Puerto de la BD        (default: 26432)
#   DB_NAME        Nombre de la BD        (default: rutadb)
#   DB_USER        Usuario de la BD       (default: ruta)
#   PGPASSWORD     Password de la BD      (REQUERIDO)
#   BACKUP_DIR     Directorio de salida   (default: directorio actual)
#   BACKUP_BUCKET  Bucket destino S3/OCI  (opcional; sube si está definido)
#
# Uso: bash scripts/backup_db.sh
# Ejemplo con password: PGPASSWORD=secret bash scripts/backup_db.sh

set -euo pipefail

# ─────────────────────────────────────────────
# Variables con defaults
# ─────────────────────────────────────────────
DB_HOST="${DB_HOST:-149.130.168.24}"
DB_PORT="${DB_PORT:-26432}"
DB_NAME="${DB_NAME:-rutadb}"
DB_USER="${DB_USER:-ruta}"
BACKUP_DIR="${BACKUP_DIR:-.}"

# ─────────────────────────────────────────────
# Verificar password requerido
# ─────────────────────────────────────────────
if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: La variable PGPASSWORD es requerida." >&2
  echo "Uso: PGPASSWORD=<password> bash scripts/backup_db.sh" >&2
  exit 1
fi

export PGPASSWORD

# ─────────────────────────────────────────────
# Verificar dependencias
# ─────────────────────────────────────────────
if ! command -v pg_dump &>/dev/null; then
  echo "ERROR: 'pg_dump' es requerido pero no está instalado." >&2
  echo "Instálalo con: sudo apt install postgresql-client" >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Generar nombre del archivo de backup
# ─────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/ruta_backup_${TIMESTAMP}.dump"

echo "=== Backup BD RUTA ==="
echo ""
echo "Host    : $DB_HOST:$DB_PORT"
echo "BD      : $DB_NAME  (schema: ruta)"
echo "Archivo : $BACKUP_FILE"
echo ""
echo "Ejecutando pg_dump..."

# ─────────────────────────────────────────────
# Ejecutar pg_dump
# ─────────────────────────────────────────────
if ! pg_dump \
  --format=custom \
  --schema=ruta \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  "$DB_NAME" \
  -f "$BACKUP_FILE"; then
  echo "" >&2
  echo "ERROR: pg_dump falló. Revisa la conexión y las credenciales." >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

# ─────────────────────────────────────────────
# Reportar tamaño del archivo
# ─────────────────────────────────────────────
FILE_SIZE="$(du -sh "$BACKUP_FILE" | cut -f1)"
echo ""
echo "✓ Backup completado exitosamente."
echo "  Archivo : $BACKUP_FILE"
echo "  Tamaño  : $FILE_SIZE"

# ─────────────────────────────────────────────
# Upload opcional a bucket (S3 o OCI)
# Requiere el CLI instalado y configurado:
#   - AWS CLI: https://docs.aws.amazon.com/cli/
#   - OCI CLI: https://docs.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm
# ─────────────────────────────────────────────
if [[ -n "${BACKUP_BUCKET:-}" ]]; then
  echo ""
  echo "BACKUP_BUCKET definido: $BACKUP_BUCKET"

  UPLOAD_SUCCESS=false

  # Intentar con AWS CLI primero
  if command -v aws &>/dev/null; then
    echo "Subiendo con AWS CLI a s3://$BACKUP_BUCKET/ ..."
    if aws s3 cp "$BACKUP_FILE" "s3://${BACKUP_BUCKET}/$(basename "$BACKUP_FILE")"; then
      echo "✓ Upload a S3 completado."
      UPLOAD_SUCCESS=true
    else
      echo "AVISO: aws s3 cp falló. Intentando con OCI CLI..." >&2
    fi
  fi

  # Intentar con OCI CLI si AWS no funcionó o no está disponible
  if [[ "$UPLOAD_SUCCESS" == "false" ]]; then
    if command -v oci &>/dev/null; then
      echo "Subiendo con OCI CLI al bucket $BACKUP_BUCKET ..."
      # Requiere: OCI_NAMESPACE, OCI_BUCKET_NAME o usar BACKUP_BUCKET como nombre del bucket.
      # Asume que BACKUP_BUCKET es el nombre del bucket en OCI Object Storage.
      if oci os object put \
        --bucket-name "$BACKUP_BUCKET" \
        --file "$BACKUP_FILE" \
        --name "$(basename "$BACKUP_FILE")" \
        --force; then
        echo "✓ Upload a OCI Object Storage completado."
        UPLOAD_SUCCESS=true
      else
        echo "ERROR: oci os object put falló." >&2
      fi
    fi
  fi

  if [[ "$UPLOAD_SUCCESS" == "false" ]]; then
    echo "" >&2
    echo "AVISO: No se pudo subir el backup al bucket." >&2
    echo "  Verifica que aws CLI o oci CLI estén instalados y configurados." >&2
    echo "  El archivo local se conserva en: $BACKUP_FILE" >&2
    # No salir con error — el backup local fue exitoso
  fi
fi

echo ""
echo "Listo."
exit 0
