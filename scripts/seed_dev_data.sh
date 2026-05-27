#!/usr/bin/env bash
# seed_dev_data.sh
#
# Siembra datos de desarrollo en la BD de RUTA.
# Crea 1 Cliente Full piloto + usuarios, catálogo y puntos de recogida.
#
# IDEMPOTENTE: si el cliente 'piloto-native' ya existe, no hace nada.
# Requiere: psql, node, backend-ruta con deps instaladas (pnpm install).
# Uso: bash scripts/seed_dev_data.sh

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
# Idempotencia: abortar si el cliente piloto ya existe
# ─────────────────────────────────────────────
EXISTING=$(psql "$DATABASE_URL" -t -A -c \
  "SELECT COUNT(*) FROM ruta.clients WHERE slug = 'piloto-native';")

if [[ "$EXISTING" -gt 0 ]]; then
  echo "El cliente 'piloto-native' ya existe en la BD. Seed ya fue aplicado."
  echo "Para re-sembrar, elimina el cliente y sus datos primero."
  exit 0
fi

# ─────────────────────────────────────────────
# Generar hash argon2id para la contraseña dev
# La contraseña pasa por env var (_RUTA_PW), nunca en texto del script.
# ─────────────────────────────────────────────
DEV_PASSWORD="Dev.Ruta.2026!"
echo "Generando hash argon2id para contraseña dev..."

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

export _RUTA_PW="$DEV_PASSWORD"
DEV_HASH=$(node "$TMP_SCRIPT")
unset _RUTA_PW

if [[ -z "$DEV_HASH" ]]; then
  echo "ERROR: No se pudo generar el hash de la contraseña." >&2
  exit 1
fi

# Argon2 hashes no contienen comillas simples; el escape es por consistencia defensiva.
HASH_SAFE="${DEV_HASH//\'/\'\'}"

echo "Hash generado. Sembrando datos en una transacción..."

# ─────────────────────────────────────────────
# Insertar todo en una sola transacción.
# Se usan subqueries (SELECT ... FROM ruta.clients WHERE slug = ...)
# para evitar bloques DO $$ y simplificar la interpolación bash.
# El trigger trg_clients_auto_partitions crea todas las particiones
# automáticamente al insertar en ruta.clients.
# ─────────────────────────────────────────────
psql "$DATABASE_URL" <<SQL
BEGIN;

-- ── 1. CLIENTE FULL PILOTO ──────────────────────────────────────────────────
INSERT INTO ruta.clients (
  business_code, slug, name, description,
  contact_person_name, contact_person_email, contact_person_phone,
  client_type, frontend_mode, status
) VALUES (
  'PILOTO001',
  'piloto-native',
  'Tienda Piloto RUTA',
  'Cliente Full piloto en modalidad NATIVE_RUTA para desarrollo y QA.',
  'Admin Piloto',
  'admin@piloto.dev',
  '+573001234567',
  'FULL',
  'NATIVE_RUTA',
  'ACTIVE'
);

-- ── 2. USUARIOS ─────────────────────────────────────────────────────────────
INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, status)
SELECT id, 'ADMIN_CLIENT', 'admin.piloto@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Admin Piloto', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, status)
SELECT id, 'OPERATOR_CLIENT', 'operator.piloto@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Operador Piloto', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'COURIER', 'repartidor1@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Carlos Repartidor', '+573109001001', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'COURIER', 'repartidor2@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Maria Repartidora', '+573109001002', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'COURIER', 'repartidor3@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Luis Mensajero', '+573109001003', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'BUYER', 'comprador1@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Ana Compradora', '+573201001001', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'BUYER', 'comprador2@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Juan Comprador', '+573201001002', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.users (client_id, user_type, email, password_hash, auth_mode, full_name, phone, status)
SELECT id, 'BUYER', 'comprador3@piloto.dev', '${HASH_SAFE}', 'PASSWORD', 'Sofia Compradora', '+573201001003', 'ACTIVE'
FROM ruta.clients WHERE slug = 'piloto-native';

-- ── 3. PERFILES DE COURIER ──────────────────────────────────────────────────
INSERT INTO ruta.courier_profiles (user_id, client_id, transport_method, vehicle_plate)
SELECT u.id, u.client_id, 'MOTO', 'ABC-123'
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'repartidor1@piloto.dev';

INSERT INTO ruta.courier_profiles (user_id, client_id, transport_method, vehicle_plate)
SELECT u.id, u.client_id, 'BICICLETA', NULL
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'repartidor2@piloto.dev';

INSERT INTO ruta.courier_profiles (user_id, client_id, transport_method, vehicle_plate)
SELECT u.id, u.client_id, 'MOTO', 'XYZ-789'
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'repartidor3@piloto.dev';

-- ── 4. PERFILES DE BUYER ────────────────────────────────────────────────────
INSERT INTO ruta.buyer_profiles (
  user_id, client_id,
  default_address_line, default_address_city, default_address_state,
  default_address_country, default_address_latitude, default_address_longitude
)
SELECT u.id, u.client_id,
  'Cra 7 #32-10 Apto 501', 'Bogota', 'Cundinamarca', 'Colombia', 4.6366, -74.0855
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'comprador1@piloto.dev';

INSERT INTO ruta.buyer_profiles (
  user_id, client_id,
  default_address_line, default_address_city, default_address_state,
  default_address_country, default_address_latitude, default_address_longitude
)
SELECT u.id, u.client_id,
  'Cll 72 #10-45 Oficina 301', 'Bogota', 'Cundinamarca', 'Colombia', 4.6582, -74.0579
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'comprador2@piloto.dev';

INSERT INTO ruta.buyer_profiles (
  user_id, client_id,
  default_address_line, default_address_city, default_address_state,
  default_address_country, default_address_latitude, default_address_longitude
)
SELECT u.id, u.client_id,
  'Av El Dorado #68D-35', 'Bogota', 'Cundinamarca', 'Colombia', 4.6780, -74.1058
FROM ruta.users u JOIN ruta.clients c ON u.client_id = c.id
WHERE c.slug = 'piloto-native' AND u.email = 'comprador3@piloto.dev';

-- ── 5. CATEGORIAS DE PRODUCTO ───────────────────────────────────────────────
INSERT INTO ruta.product_categories (client_id, name, display_order, status)
SELECT id, 'Frutas y Verduras', 1, 'ACTIVE' FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.product_categories (client_id, name, display_order, status)
SELECT id, 'Lacteos y Huevos', 2, 'ACTIVE' FROM ruta.clients WHERE slug = 'piloto-native';

INSERT INTO ruta.product_categories (client_id, name, display_order, status)
SELECT id, 'Carnes y Proteinas', 3, 'ACTIVE' FROM ruta.clients WHERE slug = 'piloto-native';

-- ── 6. PRODUCTOS (10) ───────────────────────────────────────────────────────
-- Frutas y Verduras (4 productos)
INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'FRU-001', 'Manzana Roja', 'Manzana roja importada por kg', 4500, 'COP', pc.id, 100, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Frutas y Verduras'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'FRU-002', 'Banano', 'Banano colombiano por racimo aprox. 7 unidades', 3200, 'COP', pc.id, 80, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Frutas y Verduras'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'VER-001', 'Tomate Chonto', 'Tomate chonto fresco por kg', 3800, 'COP', pc.id, 60, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Frutas y Verduras'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'VER-002', 'Cebolla Cabezona', 'Cebolla cabezona blanca por kg', 2900, 'COP', pc.id, 70, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Frutas y Verduras'
WHERE c.slug = 'piloto-native';

-- Lacteos y Huevos (3 productos)
INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'LAC-001', 'Leche Entera 1L', 'Leche entera pasteurizada bolsa 1 litro', 2800, 'COP', pc.id, 200, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Lacteos y Huevos'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'LAC-002', 'Queso Campesino', 'Queso campesino fresco 250g', 5500, 'COP', pc.id, 50, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Lacteos y Huevos'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'HUE-001', 'Huevos AA x12', 'Carton 12 huevos AA tamano grande', 8900, 'COP', pc.id, 120, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Lacteos y Huevos'
WHERE c.slug = 'piloto-native';

-- Carnes y Proteinas (3 productos)
INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'CAR-001', 'Pechuga de Pollo', 'Pechuga de pollo fresca por kg', 12500, 'COP', pc.id, 40, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Carnes y Proteinas'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'CAR-002', 'Carne Molida', 'Carne molida de res especial por kg', 18000, 'COP', pc.id, 30, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Carnes y Proteinas'
WHERE c.slug = 'piloto-native';

INSERT INTO ruta.products (client_id, sku, name, description, unit_price, currency, category_id, stock_quantity, status)
SELECT c.id, 'CAR-003', 'Tilapia Fresca', 'Tilapia fresca entera por kg', 14000, 'COP', pc.id, 25, 'ACTIVE'
FROM ruta.clients c JOIN ruta.product_categories pc ON pc.client_id = c.id AND pc.name = 'Carnes y Proteinas'
WHERE c.slug = 'piloto-native';

-- ── 7. PUNTOS DE RECOGIDA (2) ───────────────────────────────────────────────
INSERT INTO ruta.pickup_points (
  client_id, name, address_line, city, state, country,
  latitude, longitude, contact_phone, status, opening_hours
)
SELECT c.id,
  'Sede Chapinero', 'Cra 13 #54-23', 'Bogota', 'Cundinamarca', 'Colombia',
  4.6403, -74.0653, '+573001110001', 'ACTIVE',
  '{"lunes-viernes": "7:00-19:00", "sabado": "8:00-16:00", "domingo": "cerrado"}'::jsonb
FROM ruta.clients c WHERE c.slug = 'piloto-native';

INSERT INTO ruta.pickup_points (
  client_id, name, address_line, city, state, country,
  latitude, longitude, contact_phone, status, opening_hours
)
SELECT c.id,
  'Sede Usaquen', 'Cll 119 #7-11 Local 3', 'Bogota', 'Cundinamarca', 'Colombia',
  4.6957, -74.0306, '+573001110002', 'ACTIVE',
  '{"lunes-sabado": "8:00-20:00", "domingo": "10:00-16:00"}'::jsonb
FROM ruta.clients c WHERE c.slug = 'piloto-native';

COMMIT;
SQL

echo ""
echo "=== Seed completado exitosamente ==="
echo ""
echo "Cliente:   Tienda Piloto RUTA  (slug: piloto-native, type: FULL/NATIVE_RUTA)"
echo "Password:  $DEV_PASSWORD  (misma para todos los usuarios dev)"
echo ""
echo "Usuarios:"
echo "  admin.piloto@piloto.dev       ADMIN_CLIENT"
echo "  operator.piloto@piloto.dev    OPERATOR_CLIENT"
echo "  repartidor1@piloto.dev        COURIER  (moto ABC-123)"
echo "  repartidor2@piloto.dev        COURIER  (bicicleta)"
echo "  repartidor3@piloto.dev        COURIER  (moto XYZ-789)"
echo "  comprador1@piloto.dev         BUYER"
echo "  comprador2@piloto.dev         BUYER"
echo "  comprador3@piloto.dev         BUYER"
echo ""
echo "Catalogo: 10 productos en 3 categorias (Frutas, Lacteos, Carnes)."
echo "Pickup:   2 puntos (Chapinero, Usaquen)."
echo ""
echo "AVISO: Estas credenciales son SOLO para desarrollo. No usar en produccion."
