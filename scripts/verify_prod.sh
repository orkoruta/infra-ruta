#!/usr/bin/env bash
# verify_prod.sh
#
# Verifica el estado de la BD de producción post-migración.
# Seguro ejecutar en cualquier momento — solo lectura.
#
# Uso:
#   export PROD_DATABASE_URL="postgresql://..."
#   bash scripts/verify_prod.sh

set -euo pipefail

if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
  echo "ERROR: PROD_DATABASE_URL no está definida." >&2
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; }
fail() { echo -e "  ${RED}✗${RESET} $*"; }

echo -e "\n${BOLD}RUTA — Verificación de producción${RESET}\n"

# Conectividad
PG_VERSION=$(psql "$PROD_DATABASE_URL" -t -A -c "SELECT version();" 2>&1) \
  && ok "Conectado: $(echo "$PG_VERSION" | head -1 | cut -c1-60)..." \
  || { fail "No se puede conectar."; exit 1; }

# Schema
SCHEMA=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='ruta';")
[[ "$SCHEMA" -gt 0 ]] && ok "Schema ruta: existe" || fail "Schema ruta: NO existe"

# Tablas
TABLES=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM pg_tables WHERE schemaname='ruta';")
[[ "$TABLES" -ge 20 ]] \
  && ok "Tablas en schema ruta: $TABLES" \
  || warn "Tablas: $TABLES (esperadas ≥20)"

# Particiones p0
PARTS=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='ruta' AND c.relname LIKE '%_p0' AND c.relkind='r';")
[[ "$PARTS" -ge 20 ]] \
  && ok "Particiones p0 para client_id=0: $PARTS" \
  || warn "Particiones p0: $PARTS (esperadas ≥20)"

# Cliente plataforma
PLATFORM=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.clients WHERE id=0;")
[[ "$PLATFORM" -gt 0 ]] && ok "Cliente plataforma (id=0): existe" || fail "Cliente plataforma: NO existe"

# Parámetros globales
PARAMS=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.client_parameters WHERE client_id=0;")
[[ "$PARAMS" -ge 40 ]] \
  && ok "Parámetros globales: $PARAMS" \
  || warn "Parámetros globales: $PARAMS (esperados ≥40)"

# State catalog
STATES=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.state_catalog;")
[[ "$STATES" -ge 30 ]] \
  && ok "Estados en state_catalog: $STATES" \
  || warn "Estados: $STATES (esperados ≥30)"

# ADMIN_RUTA
ADMINS=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.users WHERE client_id=0 AND user_type='ADMIN_RUTA';")
[[ "$ADMINS" -gt 0 ]] \
  && ok "Usuarios ADMIN_RUTA: $ADMINS" \
  || warn "Usuarios ADMIN_RUTA: 0 — ejecuta create_admin_ruta_prod.sh"

# RLS
RLS=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM pg_tables WHERE schemaname='ruta' AND rowsecurity=TRUE;")
[[ "$RLS" -ge 10 ]] \
  && ok "Tablas con RLS activo: $RLS" \
  || warn "Tablas con RLS: $RLS (esperadas ≥10)"

# Roles de BD
for role in ruta_app ruta_jobs ruta_readonly; do
  EXISTS=$(psql "$PROD_DATABASE_URL" -t -A -c \
    "SELECT COUNT(*) FROM pg_roles WHERE rolname='$role';")
  [[ "$EXISTS" -gt 0 ]] && ok "Rol $role: existe" || fail "Rol $role: NO existe"
done

echo ""
echo -e "${BOLD}Listo.${RESET} Si hay advertencias, revísalas antes del go-live.\n"
