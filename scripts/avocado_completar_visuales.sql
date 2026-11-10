-- ============================================================================
-- Completa imagen y metadata visual del catálogo de Avocado Delivery.
--
-- El catálogo se cargó desde el panel el 2026-09-18 sin `image_url` ni
-- `metadata`, porque RUTA **no tiene object storage** todavía (la deuda #1:
-- `POST /uploads/presigned-url` responde 501). `image_url` acepta una URL, así
-- que se apunta a los ficheros que la propia landing ya sirve en `public/`.
--
-- En `metadata` va lo que la landing necesita para pintar y el modelo no
-- contempla: agrupación (caja/combo), emoji de respaldo, unidades aproximadas,
-- etiqueta destacada y precio tachado.
--
-- IDEMPOTENTE: empareja por `sku` y solo actualiza. Los cuatro productos sin
-- foto (AVO-PAP4, AVO-PAP8, ACE-250, COMBO-EXP) se quedan sin `image_url` a
-- propósito: la landing cae al emoji hasta que existan las fotos. Mejor un
-- hueco honesto que una imagen que no es la del producto.
--
-- Uso:
--   psql "$DATABASE_URL_SIN_QUERY" -f infra-ruta/scripts/avocado_completar_visuales.sql
--   (con PGOPTIONS="-c app.current_user_role=ADMIN_RUTA")
-- ============================================================================

BEGIN;

WITH visuales(sku, imagen, meta) AS (
  VALUES
    ('AVO-2KG',   '/2.png',  '{"grupo":"caja","emoji":"🥑","unit":"≈ 12-14 aguacates"}'),
    ('AVO-4KG',   '/4.png',  '{"grupo":"caja","emoji":"🥑","unit":"≈ 24-28 aguacates","badge":{"text":"Bestseller","variant":"primary"}}'),
    ('AVO-10KG',  '/10.png', '{"grupo":"caja","emoji":"🥑","unit":"≈ 60-70 aguacates","badge":{"text":"Mejor precio x kg","variant":"soft"}}'),
    ('AVO-12KG',  '/12.png', '{"grupo":"caja","emoji":"🥑","unit":"≈ 72-84 aguacates"}'),
    ('COMBO-3X2', '/x3.png', '{"grupo":"combo","emoji":"📦","list_price":75000,"save":"-6.7%"}'),
    ('COMBO-4X2', '/x4.png', '{"grupo":"combo","emoji":"📦","list_price":100000,"save":"-8%"}'),
    ('COMBO-5X2', '/x5.png', '{"grupo":"combo","emoji":"📦","list_price":120000,"save":"-5.8%"}')
)
UPDATE ruta.products p
SET image_url = 'https://avocadodelivery.onrender.com' || v.imagen,
    metadata  = v.meta::jsonb,
    updated_at = NOW()
FROM visuales v, ruta.clients c
WHERE c.slug = 'avocado-delivery'
  AND p.client_id = c.id
  AND p.sku = v.sku;

-- Los que no tienen foto sí llevan agrupación y emoji: sin `grupo` la landing
-- no sabría en qué sección pintarlos y se quedarían fuera de la tienda.
WITH sin_foto(sku, meta) AS (
  VALUES
    ('AVO-PAP4',  '{"grupo":"caja","emoji":"🥑","unit":"4 unidades"}'),
    ('AVO-PAP8',  '{"grupo":"caja","emoji":"🥑","unit":"8 unidades"}'),
    ('ACE-250',   '{"grupo":"caja","emoji":"🫒","unit":"250 ml"}'),
    ('COMBO-EXP', '{"grupo":"combo","emoji":"🎁"}')
)
UPDATE ruta.products p
SET metadata = s.meta::jsonb,
    updated_at = NOW()
FROM sin_foto s, ruta.clients c
WHERE c.slug = 'avocado-delivery'
  AND p.client_id = c.id
  AND p.sku = s.sku;

COMMIT;

SELECT p.sku, p.name, p.unit_price::bigint AS precio,
       COALESCE(p.image_url, '(sin foto)') AS imagen,
       p.metadata->>'grupo' AS grupo
FROM ruta.products p
JOIN ruta.clients c ON c.id = p.client_id
WHERE c.slug = 'avocado-delivery'
ORDER BY p.metadata->>'grupo' DESC, p.unit_price;
