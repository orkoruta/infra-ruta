#!/usr/bin/env bash
# create_admin_ruta_prod.sh
#
# Versión de producción de create_first_admin_ruta.sh.
# Acepta PROD_DATABASE_URL en lugar de leer desde .env de dev.
#
# Uso:
#   export PROD_DATABASE_URL="postgresql://ruta_admin:password@149.130.168.24:26432/ruta_prod"
#   export BACKEND_RUTA_DIR="/ruta/a/backend-ruta"   # opcional
#   bash scripts/create_admin_ruta_prod.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="${BACKEND_RUTA_DIR:-"$(cd "$REPO_ROOT/../backend-ruta" && pwd)"}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ─── Validaciones ─────────────────────────────────────────────────────────────

if [[ -z "${PROD_DATABASE_URL:-}" ]]; then
  log_error "PROD_DATABASE_URL no está definida."
  exit 1
fi

for cmd in psql node; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "'$cmd' es requerido pero no está instalado."
    exit 1
  fi
done

ARGON2_PATH="$BACKEND_DIR/api/node_modules/argon2"
if [[ ! -d "$ARGON2_PATH" ]]; then
  log_error "argon2 no encontrado en $ARGON2_PATH"
  echo "  Ejecuta: cd backend-ruta && pnpm install"
  exit 1
fi

# ─── Verificar si ya existe un ADMIN_RUTA ────────────────────────────────────

EXISTING=$(psql "$PROD_DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.users WHERE client_id = 0 AND user_type = 'ADMIN_RUTA';")

if [[ "$EXISTING" -gt 0 ]]; then
  log_info "Ya existe $EXISTING usuario(s) ADMIN_RUTA en la BD de producción."
  read -r -p "¿Crear uno adicional? [s/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    log_info "Cancelado."
    exit 0
  fi
fi

# ─── Solicitar datos ─────────────────────────────────────────────────────────

echo ""
echo "=== Crear ADMIN_RUTA en producción ==="
echo ""

read -r -p "Email: " ADMIN_EMAIL
[[ -z "$ADMIN_EMAIL" ]] && { log_error "El email no puede estar vacío."; exit 1; }

read -r -s -p "Contraseña (mín. 12 caracteres, incluye mayúsculas, números y símbolos): " ADMIN_PASSWORD
echo ""
[[ ${#ADMIN_PASSWORD} -lt 12 ]] && { log_error "La contraseña debe tener al menos 12 caracteres."; exit 1; }

read -r -p "Nombre completo (opcional): " ADMIN_NAME

# ─── Hash argon2id ────────────────────────────────────────────────────────────

log_info "Generando hash argon2id..."

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

[[ -z "$PASSWORD_HASH" ]] && { log_error "No se pudo generar el hash."; exit 1; }

# ─── INSERT ──────────────────────────────────────────────────────────────────

EMAIL_SAFE="${ADMIN_EMAIL//\'/\'\'}"
NAME_SAFE="${ADMIN_NAME//\'/\'\'}"
HASH_SAFE="${PASSWORD_HASH//\'/\'\'}"

log_info "Insertando ADMIN_RUTA en producción..."

RESULT=$(psql "$PROD_DATABASE_URL" -A -t <<SQL
INSERT INTO ruta.users (
  client_id, user_type, email, password_hash, auth_mode, full_name, status
) VALUES (
  0, 'ADMIN_RUTA', '${EMAIL_SAFE}', '${HASH_SAFE}', 'PASSWORD',
  NULLIF('${NAME_SAFE}', ''), 'ACTIVE'
)
RETURNING id, email, user_type;
SQL
)

echo ""
log_ok "ADMIN_RUTA creado en producción:"
echo "  $RESULT"
echo ""
echo "  Guarda estas credenciales en el gestor de contraseñas del equipo."
echo "  NO compartas la contraseña por chat ni email."
