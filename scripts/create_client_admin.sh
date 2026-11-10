#!/bin/bash
# ============================================================================
# Crea un usuario ADMIN_CLIENT (administrador del panel) para un Cliente.
#
# Existe porque **no hay forma de producto de hacerlo**: `POST /ruta-admin/clients`
# crea el Cliente pero ningún usuario, y las únicas altas de usuario de la API
# (`/auth/register`, `/auth/guest`) son para compradores. Sin este script, un
# Cliente nuevo no tiene con qué entrar al panel.
#
# IDEMPOTENTE: si el correo ya existe para ese Cliente, actualiza la contraseña
# en vez de fallar.
#
# Uso:
#   bash infra-ruta/scripts/create_client_admin.sh <slug> <email> [nombre]
#
# La contraseña se pide por teclado y no se muestra ni queda en el historial.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SLUG="${1:-}"
EMAIL="${2:-}"
FULL_NAME="${3:-Administrador}"

if [[ -z "$SLUG" || -z "$EMAIL" ]]; then
  echo "Uso: bash infra-ruta/scripts/create_client_admin.sh <slug> <email> [nombre]" >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c app.current_user_role=ADMIN_RUTA"

if [[ -z "${DATABASE_URL:-}" ]]; then
  DATABASE_URL=$(grep -E '^DATABASE_URL=' "$ROOT/backend-ruta/.env" | cut -d= -f2- | tr -d '"'"'"' ')
fi
# libpq no entiende los parámetros de Prisma (connection_limit, pool_timeout).
PSQL_URL="${DATABASE_URL%%\?*}"

ARGON2_PATH="$ROOT/backend-ruta/api/node_modules/argon2"
if [[ ! -d "$ARGON2_PATH" ]]; then
  echo "ERROR: argon2 no encontrado en $ARGON2_PATH (¿falta pnpm install?)" >&2
  exit 1
fi

# El Cliente tiene que existir: crear un admin colgando de la nada dejaría un
# usuario que no puede entrar a ningún sitio.
CLIENT_ID=$(psql "$PSQL_URL" -t -A -c "SELECT id FROM ruta.clients WHERE slug = '${SLUG//\'/\'\'}';")
if [[ -z "$CLIENT_ID" ]]; then
  echo "ERROR: no existe ningún Cliente con slug '$SLUG'." >&2
  exit 1
fi
echo "Cliente '$SLUG' -> client_id $CLIENT_ID"

if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
  PW="$ADMIN_PASSWORD"
else
  read -r -s -p "Contraseña (mín. 12 caracteres): " PW; echo
  read -r -s -p "Repite la contraseña: " PW2; echo
  [[ "$PW" == "$PW2" ]] || { echo "ERROR: no coinciden." >&2; exit 1; }
fi
if [[ ${#PW} -lt 12 ]]; then
  echo "ERROR: la contraseña debe tener al menos 12 caracteres." >&2
  exit 1
fi

TMP_SCRIPT=$(mktemp -t argon.XXXXXX).cjs
trap 'rm -f "$TMP_SCRIPT"' EXIT
cat > "$TMP_SCRIPT" <<NODE_EOF
const argon2 = require('${ARGON2_PATH}/argon2.cjs');
(async () => {
  const hash = await argon2.hash(process.env._RUTA_PW, {
    type: argon2.argon2id, memoryCost: 65536, timeCost: 3, parallelism: 4,
  });
  process.stdout.write(hash);
})();
NODE_EOF

export _RUTA_PW="$PW"
HASH=$(node "$TMP_SCRIPT")
unset _RUTA_PW PW
[[ -n "$HASH" ]] || { echo "ERROR: no se pudo generar el hash." >&2; exit 1; }

EMAIL_SAFE="${EMAIL//\'/\'\'}"
NAME_SAFE="${FULL_NAME//\'/\'\'}"
HASH_SAFE="${HASH//\'/\'\'}"

psql "$PSQL_URL" -v ON_ERROR_STOP=1 -q <<SQL
INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, status)
VALUES ($CLIENT_ID, 'ADMIN_CLIENT', '$EMAIL_SAFE', '$HASH_SAFE', 'PASSWORD', '$NAME_SAFE', 'ACTIVE')
ON CONFLICT (client_id, email) DO UPDATE SET
  password_hash = EXCLUDED.password_hash,
  user_type     = 'ADMIN_CLIENT',
  auth_mode     = 'PASSWORD',
  status        = 'ACTIVE',
  updated_at    = NOW();
SQL

echo
psql "$PSQL_URL" -P pager=off -c "
SELECT id, user_type, email, full_name, status
FROM ruta.users WHERE client_id = $CLIENT_ID AND user_type = 'ADMIN_CLIENT';"

echo "Listo. Entra en el panel con el código de empresa '$SLUG'."
