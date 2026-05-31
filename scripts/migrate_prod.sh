#!/usr/bin/env bash
# migrate_prod.sh
#
# Aplica el esquema completo de RUTA a la base de datos de producción.
# Diseñado para ejecutarse UNA SOLA VEZ sobre una BD PostgreSQL vacía.
#
# Uso:
#   export PROD_DATABASE_URL="postgresql://ruta_admin:password@149.130.168.24:26432/ruta_prod"
#   bash scripts/migrate_prod.sh
#
# Variables de entorno requeridas:
#   PROD_DATABASE_URL   — connection string completo a la BD de producción
#
# Variables de entorno opcionales:
#   DOCS_RUTA_DIR       — ruta local a docs-ruta/ (default: hermano de este repo)
#   DRY_RUN             — si está definida, solo valida sin aplicar (ej: DRY_RUN=1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_RUTA_DIR="${DOCS_RUTA_DIR:-"$(cd "$REPO_ROOT/../docs-ruta" && pwd)"}"
SQL_FILE="$DOCS_RUTA_DIR/bd/ruta_postgres.sql"

# ─── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ─── Validaciones previas ─────────────────────────────────────────────────────

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  RUTA — Migración a producción${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
  log_error "PROD_DATABASE_URL no está definida."
  echo "  Ejemplo: export PROD_DATABASE_URL=\"postgresql://ruta_admin:password@149.130.168.24:26432/ruta_prod\""
  exit 1
fi

if ! command -v psql &>/dev/null; then
  log_error "psql no está instalado. Instala postgresql-client-18."
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  log_error "No se encuentra el SQL: $SQL_FILE"
  echo "  Define DOCS_RUTA_DIR apuntando al repo docs-ruta."
  exit 1
fi

# ─── Verificar conectividad ───────────────────────────────────────────────────

log_info "Verificando conectividad con la BD de producción..."
PG_VERSION=$(psql "$PROD_DATABASE_URL" -t -A -c "SELECT version();" 2>&1) || {
  log_error "No se pudo conectar a la BD. Verifica PROD_DATABASE_URL y acceso de red."
  exit 1
}
log_ok "Conectado: $(echo "$PG_VERSION" | head -1)"

# ─── Verificar que la BD está vacía ───────────────────────────────────────────

log_info "Verificando que el schema 'ruta' no existe aún..."
SCHEMA_EXISTS=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'ruta';")

if [[ "$SCHEMA_EXISTS" -gt 0 ]]; then
  log_warn "El schema 'ruta' ya existe en esta base de datos."
  echo ""
  echo -e "  ${YELLOW}IMPORTANTE:${RESET} Este script es para instalación NUEVA."
  echo "  Si la BD de producción ya tiene datos, NO ejecutes este script."
  echo "  Si fue una instalación parcial fallida, contacta al equipo antes de continuar."
  echo ""
  read -r -p "  ¿Continuar de todas formas? Escribe 'SI ENTIENDO EL RIESGO' para confirmar: " CONFIRM
  if [[ "$CONFIRM" != "SI ENTIENDO EL RIESGO" ]]; then
    log_info "Migración cancelada."
    exit 0
  fi
fi

# ─── Verificar versión pg_dump vs servidor ────────────────────────────────────

SERVER_MAJOR=$(psql "$PROD_DATABASE_URL" -t -A -c "SHOW server_version_num;" | cut -c1-2)
CLIENT_MAJOR=$(psql --version | grep -oP '\d+' | head -1)
if [[ "$CLIENT_MAJOR" -lt "$SERVER_MAJOR" ]]; then
  log_warn "Cliente psql v${CLIENT_MAJOR} < servidor PostgreSQL v${SERVER_MAJOR}."
  log_warn "Se recomienda instalar postgresql-client-${SERVER_MAJOR} para compatibilidad total."
fi

# ─── Dry run ─────────────────────────────────────────────────────────────────

if [[ -n "${DRY_RUN:-}" ]]; then
  log_ok "DRY_RUN activo — validaciones completadas, no se aplicaron cambios."
  echo "  SQL a aplicar: $SQL_FILE ($(wc -l < "$SQL_FILE") líneas)"
  exit 0
fi

# ─── Confirmación final ───────────────────────────────────────────────────────

echo ""
log_warn "Estás a punto de aplicar el esquema completo de RUTA a:"
echo "  ${PROD_DATABASE_URL//:*@/:***@}"
echo ""
echo "  Esto creará todas las tablas, roles, funciones, triggers,"
echo "  RLS, particiones, catálogo de estados y parámetros globales."
echo ""
read -r -p "  ¿Confirmar migración? [s/N]: " CONFIRM_APPLY
if [[ ! "$CONFIRM_APPLY" =~ ^[sS]$ ]]; then
  log_info "Migración cancelada."
  exit 0
fi

# ─── Aplicar SQL ─────────────────────────────────────────────────────────────

echo ""
log_info "Aplicando $SQL_FILE..."
START_TIME=$(date +%s)

PSQL_OUTPUT=$(psql "$PROD_DATABASE_URL" \
  --set ON_ERROR_STOP=1 \
  --echo-errors \
  -f "$SQL_FILE" 2>&1) && PSQL_EXIT=0 || PSQL_EXIT=$?

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [[ $PSQL_EXIT -ne 0 ]]; then
  log_error "La migración falló (exit $PSQL_EXIT) en ${ELAPSED}s."
  echo ""
  echo "Últimas líneas de salida:"
  echo "$PSQL_OUTPUT" | tail -20
  echo ""
  echo "La transacción fue abortada (el SQL usa BEGIN/COMMIT)."
  echo "La BD quedó sin cambios. Revisa el error y vuelve a intentarlo."
  exit 1
fi

log_ok "SQL aplicado exitosamente en ${ELAPSED}s."

# ─── Verificación post-migración ──────────────────────────────────────────────

echo ""
log_info "Verificando resultado..."

TABLE_COUNT=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'ruta';")

PARTITION_COUNT=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'ruta' AND c.relname LIKE '%_p0' AND c.relkind = 'r';")

PARAM_COUNT=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.client_parameters WHERE client_id = 0;" 2>/dev/null || echo "0")

STATE_COUNT=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.state_catalog;" 2>/dev/null || echo "0")

PLATFORM_CLIENT=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.clients WHERE id = 0;" 2>/dev/null || echo "0")

echo ""
echo -e "  ${BOLD}Resultado de la verificación:${RESET}"
echo "  ┌─────────────────────────────────────────┐"
printf "  │ %-40s│\n" "Tablas en schema ruta: $TABLE_COUNT"
printf "  │ %-40s│\n" "Particiones p0 creadas: $PARTITION_COUNT"
printf "  │ %-40s│\n" "Parámetros globales (client_id=0): $PARAM_COUNT"
printf "  │ %-40s│\n" "Estados en state_catalog: $STATE_COUNT"
printf "  │ %-40s│\n" "Cliente plataforma (id=0): $([ "$PLATFORM_CLIENT" -gt 0 ] && echo 'OK' || echo 'FALTA')"
echo "  └─────────────────────────────────────────┘"

if [[ "$TABLE_COUNT" -lt 20 ]] || [[ "$PARTITION_COUNT" -lt 20 ]] || [[ "$PARAM_COUNT" -lt 40 ]]; then
  log_warn "Algunos conteos están por debajo de lo esperado. Revisa manualmente."
else
  log_ok "Verificación completa — BD de producción lista."
fi

# ─── Siguiente paso ───────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Siguiente paso:${RESET}"
echo "  Crea el primer ADMIN_RUTA ejecutando:"
echo "    PROD_DATABASE_URL=\"\$PROD_DATABASE_URL\" bash scripts/create_admin_ruta_prod.sh"
echo ""
