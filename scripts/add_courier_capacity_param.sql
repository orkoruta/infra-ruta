-- ============================================================================
-- Tope de pedidos simultáneos por repartidor, visible en el panel
-- ============================================================================
--
-- El código ya lee `limits.max_concurrent_orders_per_courier` (3 por defecto,
-- en courier_assignment.service.ts), pero el parámetro nunca se sembró como
-- global, así que **no aparecía en Ajustes → Parámetros** y el Cliente no tenía
-- forma de subirlo. Lo reportaron como «solo deja asignar 3 pedidos por
-- repartidor».
--
-- Se siembra el global (client_id = 0) con el mismo valor por defecto que usa
-- el código, sobrescribible por cada Cliente. No cambia el comportamiento de
-- nadie: solo lo hace visible y editable.
--
-- Idempotente.
--
-- Uso:
--   PGOPTIONS="-c app.current_user_role=ADMIN_RUTA" \
--     psql "$DATABASE_URL" -f infra-ruta/scripts/add_courier_capacity_param.sql
--
-- Para subirlo de una vez a un Cliente concreto (p. ej. 10 para Avocado), sin
-- esperar a que lo cambie desde el panel:
--   INSERT INTO ruta.client_parameters
--     (client_id, parameter_key, parameter_value, value_type, description, is_overrideable_by_client)
--   SELECT id, 'limits.max_concurrent_orders_per_courier', '10', 'INTEGER',
--          'Pedidos simultáneos por Repartidor', TRUE
--   FROM ruta.clients WHERE slug = 'avocado-delivery'
--   ON CONFLICT (client_id, parameter_key) DO UPDATE SET parameter_value = EXCLUDED.parameter_value;
-- ============================================================================

INSERT INTO ruta.client_parameters
  (client_id, parameter_key, parameter_value, value_type, description, is_overrideable_by_client)
VALUES
  (0, 'limits.max_concurrent_orders_per_courier', '3', 'INTEGER',
   'Pedidos simultáneos por Repartidor antes de dejar de aparecer como disponible', TRUE)
ON CONFLICT (client_id, parameter_key) DO NOTHING;
