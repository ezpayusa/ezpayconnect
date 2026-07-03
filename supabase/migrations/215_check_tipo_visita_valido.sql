-- ============================================================================
-- Migración 215: CHECK de valores válidos para visitas_agendadas.tipo_visita
-- ============================================================================
-- DEFENSA EN PROFUNDIDAD: visitas_agendadas.tipo_visita es TEXT NOT NULL DEFAULT
-- 'presentacion_producto' pero NO tenía CHECK. El front (VisitadorAgendarPage) ya restringe
-- el selector a estos 5 valores; este CHECK lo hace explícito en la DB, de modo que un INSERT
-- directo (o un futuro caller) no pueda meter un tipo_visita arbitrario.
-- Verificado antes de aplicar: los únicos valores en prod son 'presentacion_producto' (10) y
-- 'capacitacion' (3), ambos dentro del set → el CHECK no rompe datos existentes.
-- ============================================================================

ALTER TABLE public.visitas_agendadas
  ADD CONSTRAINT tipo_visita_valido
  CHECK (tipo_visita IN ('presentacion_producto', 'capacitacion', 'muestra_gratis', 'pedido', 'otro'));
