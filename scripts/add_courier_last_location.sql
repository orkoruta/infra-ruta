-- ============================================================================
-- Última ubicación conocida del repartidor
-- ============================================================================
--
-- Permite que el comprador siga en el mapa al repartidor que le lleva el
-- pedido, desde que este pulsa "Iniciar despacho" hasta que entrega.
--
-- **Se guarda solo la última posición, no el historial.** Un repartidor
-- reportando cada 20 s durante una jornada de 8 h son ~1.400 filas al día por
-- persona; con flota, millones al año. Para pintar "dónde está ahora" —que es
-- lo que pide el comprador— basta con la última, y así no hace falta tabla
-- nueva, ni particionarla, ni una política de retención. Si algún día se quiere
-- dibujar el recorrido, eso sí pide una tabla aparte pensada para series.
--
-- `courier_profiles` ya está particionada por `client_id`, así que el ALTER
-- sobre la tabla madre propaga a todas las particiones.
--
-- Aditivo y nullable: los repartidores existentes quedan en NULL.
--
-- Uso:
--   psql "$DATABASE_URL" -f infra-ruta/scripts/add_courier_last_location.sql
--
-- Revertir:
--   ALTER TABLE ruta.courier_profiles
--     DROP COLUMN last_latitude, DROP COLUMN last_longitude,
--     DROP COLUMN last_location_at;
-- ============================================================================

ALTER TABLE ruta.courier_profiles
  ADD COLUMN IF NOT EXISTS last_latitude   NUMERIC(10,7),
  ADD COLUMN IF NOT EXISTS last_longitude  NUMERIC(10,7),
  -- Cuándo se recibió. Sin esto no se puede distinguir "está aquí" de "aquí
  -- estaba hace dos horas", que para el comprador es una diferencia enorme.
  ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ;
