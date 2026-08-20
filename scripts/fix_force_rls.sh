#!/usr/bin/env bash
# fix_force_rls.sh
#
# Fuerza Row Level Security en las tablas que tienen RLS activo pero sin FORCE.
#
# ¿Por qué hace falta? `rutauser` es el **dueño** de las tablas y PostgreSQL
# exime al dueño de RLS salvo que se declare FORCE. Como la aplicación conecta
# justamente con ese rol, `ENABLE ROW LEVEL SECURITY` por sí solo deja el
# aislamiento **inerte**: un Cliente puede leer datos de otro. En desarrollo se
# detectó una fuga cross-tenant real por esto el 2026-07-22.
#
# El script es **idempotente** y no toca las tablas que no tienen RLS activo:
# hay siete excluidas a propósito (`clients`, `sessions`, `state_catalog`,
# `webhook_subscriptions`, `external_webhook_events` y las dos de Vista de
# Control). Solo endurece lo que ya debería estar protegido.
#
# Uso:
#   export PROD_DATABASE_URL="postgresql://..."
#   bash scripts/fix_force_rls.sh            # muestra qué haría
#   bash scripts/fix_force_rls.sh --apply    # lo aplica
#
# Después de aplicarlo, `pg_dump` necesita `PGOPTIONS` + `--enable-row-security`;
# los scripts de backup de este repo ya lo contemplan.

set -euo pipefail

if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
  echo "ERROR: PROD_DATABASE_URL no está definida." >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c app.current_user_role=ADMIN_RUTA"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

FIND_SQL="SELECT c.relname
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'ruta'
    AND c.relkind IN ('r','p')
    AND c.relname !~ '_p[0-9]+\$'
    AND c.relrowsecurity
    AND NOT c.relforcerowsecurity
  ORDER BY c.relname;"

# Se lee con `while read` y no con `mapfile`: macOS trae bash 3.2, que no lo
# tiene, y este script debe correr igual en el portátil del equipo y en CI.
PENDING=()
while IFS= read -r line; do
  [[ -n "$line" ]] && PENDING+=("$line")
done < <(psql "$PROD_DATABASE_URL" -t -A -c "$FIND_SQL")

if [[ ${#PENDING[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓${RESET} Nada que corregir: todas las tablas con RLS ya la tienen forzada."
  exit 0
fi

echo -e "\n${BOLD}Tablas con RLS activo pero SIN forzar (${#PENDING[@]}):${RESET}"
for t in "${PENDING[@]}"; do echo "  - $t"; done

if [[ "${1:-}" != "--apply" ]]; then
  echo -e "\n${YELLOW}Simulación.${RESET} Para aplicarlo:  bash scripts/fix_force_rls.sh --apply\n"
  exit 0
fi

echo -e "\n${BOLD}Aplicando…${RESET}"
# Todo en una transacción: o quedan todas protegidas o ninguna, para no dejar
# el aislamiento a medias.
{
  echo "BEGIN;"
  for t in "${PENDING[@]}"; do
    echo "ALTER TABLE ruta.${t} FORCE ROW LEVEL SECURITY;"
  done
  echo "COMMIT;"
} | psql "$PROD_DATABASE_URL" -v ON_ERROR_STOP=1

REMAINING=$(psql "$PROD_DATABASE_URL" -t -A -c "$FIND_SQL" | grep -c . || true)
if [[ "$REMAINING" -eq 0 ]]; then
  echo -e "${GREEN}✓${RESET} RLS forzada en ${#PENDING[@]} tablas. Verifica con: bash scripts/verify_prod.sh"
else
  echo -e "Quedan $REMAINING tablas sin forzar. Revisa el error de arriba." >&2
  exit 1
fi
