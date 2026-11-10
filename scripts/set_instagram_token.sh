#!/bin/bash
# ============================================================================
# Conecta el Instagram de un Cliente para que su landing muestre siempre sus
# últimas publicaciones (GET /public/clients/<slug>/instagram).
#
# Requisitos del lado de Instagram (una sola vez, lo hace el equipo de RUTA):
#   1. La cuenta de Instagram del Cliente debe ser **profesional** (empresa o
#      creador).
#   2. En developers.facebook.com, una app con el producto «Instagram» →
#      «API setup with Instagram login». Se añade la cuenta del Cliente como
#      probador (Roles → Instagram testers) y el Cliente acepta la invitación
#      desde su Instagram (Configuración → Apps y sitios web).
#   3. En esa misma pantalla, «Generate token» para la cuenta: ese es un token
#      de **larga duración** (60 días). La API lo renueva sola mientras la
#      landing reciba visitas.
#
# IDEMPOTENTE: relanzarlo reemplaza el token.
#
# Uso:
#   bash infra-ruta/scripts/set_instagram_token.sh <slug>
#
# El token se pide por teclado (no queda en el historial) o en INSTAGRAM_TOKEN.
# DATABASE_URL se toma del entorno o de backend-ruta/.env.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  echo "Uso: bash infra-ruta/scripts/set_instagram_token.sh <slug>" >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c app.current_user_role=ADMIN_RUTA"

if [[ -z "${DATABASE_URL:-}" ]]; then
  DATABASE_URL=$(grep -E '^DATABASE_URL=' "$ROOT/backend-ruta/.env" | cut -d= -f2- | tr -d '"'"'"' ')
fi
PSQL_URL="${DATABASE_URL%%\?*}"

CLIENT_ID=$(psql "$PSQL_URL" -t -A -c "SELECT id FROM ruta.clients WHERE slug = '${SLUG//\'/\'\'}';")
if [[ -z "$CLIENT_ID" ]]; then
  echo "ERROR: no existe ningún Cliente con slug '$SLUG'." >&2
  exit 1
fi

TOKEN="${INSTAGRAM_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  read -r -s -p "Token de Instagram (larga duración): " TOKEN; echo
fi
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: token vacío." >&2
  exit 1
fi

# Se comprueba contra Instagram antes de guardarlo: un token inválido dejaría
# la sección vacía en la landing sin que nadie supiera por qué.
echo "Comprobando el token con Instagram…"
CHECK=$(curl -s -m 15 "https://graph.instagram.com/me?fields=username&access_token=${TOKEN}")
USERNAME=$(printf '%s' "$CHECK" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')
if [[ -z "$USERNAME" ]]; then
  echo "ERROR: Instagram rechazó el token: $CHECK" >&2
  exit 1
fi
echo "Token válido para @$USERNAME"

TOKEN_SAFE="${TOKEN//\'/\'\'}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

psql "$PSQL_URL" -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO ruta.client_parameters
  (client_id, parameter_key, parameter_value, value_type, description, is_overrideable_by_client)
VALUES
  ($CLIENT_ID, 'integrations.instagram_access_token', '$TOKEN_SAFE', 'STRING',
   'Token de Instagram (larga duración) de @$USERNAME', FALSE),
  ($CLIENT_ID, 'integrations.instagram_token_refreshed_at', '$NOW', 'STRING',
   'Último refresco del token de Instagram', FALSE)
ON CONFLICT (client_id, parameter_key) DO UPDATE SET
  parameter_value = EXCLUDED.parameter_value,
  description     = EXCLUDED.description,
  updated_at      = NOW();
SQL

unset TOKEN TOKEN_SAFE
echo "Listo. Comprueba:"
echo "  curl -s https://ruta-orko-api.onrender.com/public/clients/$SLUG/instagram"
