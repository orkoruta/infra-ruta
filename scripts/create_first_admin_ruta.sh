#!/usr/bin/env bash
# create_first_admin_ruta.sh
#
# Crea el primer usuario ADMIN_RUTA en la base de datos de RUTA.
# Requiere: psql, node, pnpm instalado y backend-ruta con deps.
#
# Uso: bash scripts/create_first_admin_ruta.sh
# Puede ejecutarse desde cualquier directorio del workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend-ruta"

# ─────────────────────────────────────────────
# Cargar DATABASE_URL desde backend-ruta/.env
# ─────────────────────────────────────────────
if [[ -z "${DATABASE_URL:-}" ]]; then
  ENV_FILE="$BACKEND_DIR/.env"
  if [[ -f "$ENV_FILE" ]]; then
    DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_FILE" | head -1 | cut -d'=' -f2-)
    export DATABASE_URL
  fi
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL no está definida. Defínela en el entorno o en backend-ruta/.env." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Verificar dependencias
# ─────────────────────────────────────────────
for cmd in psql node; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' es requerido pero no está instalado." >&2
    exit 1
  fi
done

ARGON2_PATH="$BACKEND_DIR/api/node_modules/argon2"
if [[ ! -d "$ARGON2_PATH" ]]; then
  echo "ERROR: argon2 no encontrado en $ARGON2_PATH" >&2
  echo "Ejecuta primero: cd backend-ruta && pnpm install" >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Verificar si ya existe un ADMIN_RUTA
# ─────────────────────────────────────────────
EXISTING=$(psql "$DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.users WHERE client_id = 0 AND user_type = 'ADMIN_RUTA';")

if [[ "$EXISTING" -gt 0 ]]; then
  echo "Ya existe $EXISTING usuario(s) ADMIN_RUTA en la BD."
  read -r -p "¿Crear uno adicional? [s/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo "Cancelado."
    exit 0
  fi
fi

# ─────────────────────────────────────────────
# Solicitar datos
# ─────────────────────────────────────────────
echo ""
echo "=== Crear primer ADMIN_RUTA ==="
echo ""

read -r -p "Email: " ADMIN_EMAIL
if [[ -z "$ADMIN_EMAIL" ]]; then
  echo "ERROR: El email no puede estar vacío." >&2
  exit 1
fi

read -r -s -p "Contraseña (mín. 12 caracteres): " ADMIN_PASSWORD
echo ""
if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
  echo "ERROR: La contraseña debe tener al menos 12 caracteres." >&2
  exit 1
fi

read -r -p "Nombre completo (opcional, Enter para omitir): " ADMIN_NAME

# ─────────────────────────────────────────────
# Hash con argon2id — contraseña pasa por env var (no en código)
# ─────────────────────────────────────────────
echo ""
echo "Generando hash argon2id..."

# Script Node temporal; la contraseña llega via _RUTA_PW (env var, no en texto)
TMP_SCRIPT=$(mktemp --suffix=.cjs)
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<NODE_EOF
const argon2 = require('${ARGON2_PATH}/argon2.cjs');
(async () => {
  const hash = await argon2.hash(process.env._RUTA_PW, {
    type: argon2.argon2id,
    memoryCost: 65536,
    timeCost: 3,
    parallelism: 4,
  });
  process.stdout.write(hash);
})();
NODE_EOF

export _RUTA_PW="$ADMIN_PASSWORD"
PASSWORD_HASH=$(node "$TMP_SCRIPT")
unset _RUTA_PW

if [[ -z "$PASSWORD_HASH" ]]; then
  echo "ERROR: No se pudo generar el hash de la contraseña." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Escapar valores para SQL (sustituir ' por '')
# ─────────────────────────────────────────────
EMAIL_SAFE="${ADMIN_EMAIL//\'/\'\'}"
NAME_SAFE="${ADMIN_NAME//\'/\'\'}"
HASH_SAFE="${PASSWORD_HASH//\'/\'\'}"  # argon2 hash no contiene ', por seguridad igual

# ─────────────────────────────────────────────
# INSERT en ruta.users
# ─────────────────────────────────────────────
echo "Insertando usuario ADMIN_RUTA..."

RESULT=$(psql "$DATABASE_URL" -A -t <<SQL
INSERT INTO ruta.users (
  client_id,
  user_type,
  email,
  password_hash,
  auth_mode,
  full_name,
  status
) VALUES (
  0,
  'ADMIN_RUTA',
  '${EMAIL_SAFE}',
  '${HASH_SAFE}',
  'PASSWORD',
  NULLIF('${NAME_SAFE}', ''),
  'ACTIVE'
)
RETURNING id, email, user_type;
SQL
)

echo ""
echo "✓ ADMIN_RUTA creado exitosamente."
echo "$RESULT"
echo ""
echo "Guarda estas credenciales en un gestor de contraseñas."
