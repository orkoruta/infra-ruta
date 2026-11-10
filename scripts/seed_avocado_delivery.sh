#!/bin/bash
# ============================================================================
# Alta del Cliente «Avocado Delivery» y su catálogo.
#
# Cliente FULL en modalidad CUSTOM_LANDING_BY_RUTA: su frontend es la landing
# propia (repo landignpage-avocadodelivery), no el storefront nativo.
#
# IDEMPOTENTE: se puede relanzar. El cliente se reconoce por `slug` y los
# productos por `sku`; una segunda pasada actualiza precios y nombres en vez de
# duplicar filas.
#
# Los `sku` son **los mismos ids que usa la landing** en `lib/products.js`
# (caja-2, combo-x3…). Ese es el puente entre los dos mundos: la landing pide
# el catálogo a la API y empareja por sku, sin tablas de traducción.
#
# Uso:
#   DRY_RUN=1 bash infra-ruta/scripts/seed_avocado_delivery.sh   # solo valida
#   bash infra-ruta/scripts/seed_avocado_delivery.sh             # aplica
#
# DATABASE_URL se toma del entorno o de backend-ruta/.env.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# `ADMIN_RUTA` es el rol que las políticas RLS eximen del filtro por tenant
# (`OR current_setting('app.current_user_role') = 'ADMIN_RUTA'`). Sin esto, el
# INSERT en tablas particionadas por client_id no pasa.
export PGOPTIONS="${PGOPTIONS:-} -c app.current_user_role=ADMIN_RUTA"

if [[ -z "${DATABASE_URL:-}" ]]; then
  if [[ -f "$ROOT/backend-ruta/.env" ]]; then
    DATABASE_URL=$(grep -E '^DATABASE_URL=' "$ROOT/backend-ruta/.env" | cut -d= -f2- | tr -d '"'"'"' ')
  fi
fi
if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: falta DATABASE_URL (ni en el entorno ni en backend-ruta/.env)." >&2
  exit 1
fi

# La URL del proyecto lleva parámetros que entiende Prisma y libpq no
# (`connection_limit`, `pool_timeout`): psql aborta con
# «invalid URI query parameter». Se recorta la query para psql; Prisma sigue
# usando la URL completa desde el .env.
PSQL_URL="${DATABASE_URL%%\?*}"

SLUG="avocado-delivery"
BUSINESS_CODE="AVOCADO001"
LANDING_URL="https://avocadodelivery.onrender.com"

echo "=== Alta de Avocado Delivery ==="
echo "slug:    $SLUG"
echo "destino: $(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^:]*:)[^@]*@#\1***@#')"
echo

# ---------------------------------------------------------------------------
# El SQL va entero en una transacción: o queda el cliente con su catálogo
# completo, o no queda nada. Un cliente a medias es peor que ninguno, porque
# la landing lo encontraría y mostraría un catálogo incompleto.
# ---------------------------------------------------------------------------
SQL=$(cat <<SQL_EOF
BEGIN;

-- ── Cliente ────────────────────────────────────────────────────────────────
-- El trigger trg_clients_auto_partitions crea las particiones de todas las
-- tablas operativas al insertar aquí.
INSERT INTO ruta.clients (
  business_code, slug, name, description,
  contact_person_name, contact_person_email, contact_person_phone,
  client_type, frontend_mode, status
) VALUES (
  '$BUSINESS_CODE',
  '$SLUG',
  'Avocado Delivery',
  'Aguacates del árbol a tu mesa. Tres generaciones cultivando.',
  'Avocado Delivery',
  'hola@avocadodelivery.com',
  '+573000000000',
  'FULL',
  'CUSTOM_LANDING_BY_RUTA',
  'ACTIVE'
)
ON CONFLICT (slug) DO UPDATE SET
  name          = EXCLUDED.name,
  description   = EXCLUDED.description,
  client_type   = EXCLUDED.client_type,
  frontend_mode = EXCLUDED.frontend_mode,
  status        = 'ACTIVE',
  updated_at    = NOW();

-- ── Categorías ─────────────────────────────────────────────────────────────
-- product_categories no tiene índice único por nombre, así que la
-- idempotencia se hace con NOT EXISTS en vez de ON CONFLICT.
INSERT INTO ruta.product_categories (client_id, name, display_order, status)
SELECT c.id, 'Cajas', 1, 'ACTIVE'
FROM ruta.clients c
WHERE c.slug = '$SLUG'
  AND NOT EXISTS (
    SELECT 1 FROM ruta.product_categories pc
    WHERE pc.client_id = c.id AND pc.name = 'Cajas'
  );

INSERT INTO ruta.product_categories (client_id, name, display_order, status)
SELECT c.id, 'Combos', 2, 'ACTIVE'
FROM ruta.clients c
WHERE c.slug = '$SLUG'
  AND NOT EXISTS (
    SELECT 1 FROM ruta.product_categories pc
    WHERE pc.client_id = c.id AND pc.name = 'Combos'
  );

-- ── Catálogo ───────────────────────────────────────────────────────────────
-- Precios en COP, enteros, calcados de lib/products.js.
-- En metadata va lo que la landing necesita para pintar y RUTA no modela:
-- (sin acentos graves en este bloque: el heredoc no va entrecomillado para
-- poder interpolar \$SLUG, así que bash ejecutaría lo que hubiera entre ellos)
-- emoji, unidades aproximadas, etiqueta y precio tachado. Así el catálogo
-- sigue teniendo una sola fuente de verdad aunque la presentación sea propia.
WITH cli AS (
  SELECT id FROM ruta.clients WHERE slug = '$SLUG'
),
cat AS (
  SELECT pc.name, pc.id
  FROM ruta.product_categories pc, cli
  WHERE pc.client_id = cli.id
),
items(sku, name, description, price, category, image, meta) AS (
  VALUES
    ('caja-2',   'Caja 2 kg',  'Para una persona o pareja. Dura la semana sin que sobre.', 25000, 'Cajas',  '/2.png',
      '{"kind":"box","emoji":"🥑","unit":"≈ 12-14 aguacates"}'),
    ('caja-4',   'Caja 4 kg',  'El favorito de las familias. Equilibrio perfecto.',        48000, 'Cajas',  '/4.png',
      '{"kind":"box","emoji":"🥑","unit":"≈ 24-28 aguacates","badge":{"text":"Bestseller","variant":"primary"}}'),
    ('caja-10',  'Caja 10 kg', 'Para los que cocinan en grande o comparten con vecinos.',  90000, 'Cajas',  '/10.png',
      '{"kind":"box","emoji":"🥑","unit":"≈ 60-70 aguacates","badge":{"text":"Mejor precio x kg","variant":"soft"}}'),
    ('caja-12',  'Caja 12 kg', 'Volumen total: la caja más rendidora del catálogo.',       96000, 'Cajas',  '/12.png',
      '{"kind":"box","emoji":"🥑","unit":"≈ 72-84 aguacates"}'),
    ('combo-x3', 'Combo x3 cajas de 2 kg', '12-14 unidades por caja',                      70000, 'Combos', '/x3.png',
      '{"kind":"combo","emoji":"📦","list_price":75000,"save":"-6.7%"}'),
    ('combo-x4', 'Combo x4 cajas de 2 kg', '12-14 unidades por caja',                      92000, 'Combos', '/x4.png',
      '{"kind":"combo","emoji":"📦","list_price":100000,"save":"-8%"}'),
    ('combo-x5', 'Combo x5 cajas de 2 kg', '12-14 unidades por caja',                     113000, 'Combos', '/x5.png',
      '{"kind":"combo","emoji":"📦","list_price":120000,"save":"-5.8%"}')
)
INSERT INTO ruta.products (
  client_id, sku, name, description, product_type,
  unit_price, currency, category_id, image_url, status, metadata
)
SELECT
  cli.id, i.sku, i.name, i.description, 'VENTA_NORMAL',
  i.price, 'COP', cat.id, '$LANDING_URL' || i.image, 'ACTIVE', i.meta::jsonb
FROM items i
CROSS JOIN cli
LEFT JOIN cat ON cat.name = i.category
ON CONFLICT (client_id, sku) DO UPDATE SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  unit_price  = EXCLUDED.unit_price,
  category_id = EXCLUDED.category_id,
  image_url   = EXCLUDED.image_url,
  metadata    = EXCLUDED.metadata,
  status      = 'ACTIVE',
  updated_at  = NOW();

COMMIT;
SQL_EOF
)

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "── MODO SECO: se valida el SQL sin aplicarlo ──"
  # ROLLBACK en vez de COMMIT: ejecuta de verdad (así detecta errores reales de
  # tipos, constraints y RLS) pero no deja nada.
  printf '%s' "${SQL/COMMIT;/ROLLBACK;}" | psql "$PSQL_URL" -v ON_ERROR_STOP=1 -q
  echo "SQL válido. Relanza sin DRY_RUN para aplicarlo."
  exit 0
fi

printf '%s' "$SQL" | psql "$PSQL_URL" -v ON_ERROR_STOP=1 -q
echo "Aplicado."
echo

# ── Verificación ───────────────────────────────────────────────────────────
echo "=== Verificación ==="
psql "$PSQL_URL" -v ON_ERROR_STOP=1 -P pager=off -c "
SELECT c.id AS client_id, c.slug, c.client_type, c.frontend_mode, c.status,
       (SELECT COUNT(*) FROM ruta.products p WHERE p.client_id = c.id) AS productos,
       (SELECT COUNT(*) FROM ruta.product_categories pc WHERE pc.client_id = c.id) AS categorias
FROM ruta.clients c WHERE c.slug = '$SLUG';"

psql "$PSQL_URL" -v ON_ERROR_STOP=1 -P pager=off -c "
SELECT p.sku, p.name, p.unit_price::bigint AS precio, pc.name AS categoria
FROM ruta.products p
JOIN ruta.clients c ON c.id = p.client_id
LEFT JOIN ruta.product_categories pc
       ON pc.id = p.category_id AND pc.client_id = p.client_id
WHERE c.slug = '$SLUG'
ORDER BY pc.display_order, p.unit_price;"

echo
echo "Comprueba que la API ya lo sirve:"
echo "  curl -s https://ruta-orko-api.onrender.com/public/clients/$SLUG | head -c 200"
