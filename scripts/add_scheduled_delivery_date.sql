-- ============================================================================
-- Fecha de entrega programada en pedidos
-- ============================================================================
--
-- Agrega `orders.scheduled_delivery_date`: el día en que el Cliente se
-- compromete a entregar el pedido. Lo fija a mano desde el detalle del pedido
-- en el panel administrativo; lo ven el comprador y el repartidor.
--
-- Es DATE y no TIMESTAMPTZ a propósito: es un día calendario del negocio
-- (Colombia, UTC-5) y un timestamp se renderiza como el día anterior con
-- facilidad. No confundir con `delivered_at`, que es cuándo se entregó.
--
-- Aditivo y nullable: los pedidos existentes quedan en NULL y nada se rompe.
-- `orders` está particionada LIST por client_id; ALTER TABLE sobre la tabla
-- madre propaga la columna a todas las particiones automáticamente.
--
-- Uso:
--   psql "$DATABASE_URL" -f infra-ruta/scripts/add_scheduled_delivery_date.sql
--
-- Revertir:
--   ALTER TABLE ruta.orders DROP COLUMN scheduled_delivery_date;
-- ============================================================================

ALTER TABLE ruta.orders
  ADD COLUMN IF NOT EXISTS scheduled_delivery_date DATE;

-- El mapa de asignación filtra por día de entrega dentro de un tenant.
CREATE INDEX IF NOT EXISTS idx_orders_client_scheduled_delivery
  ON ruta.orders (client_id, scheduled_delivery_date);
