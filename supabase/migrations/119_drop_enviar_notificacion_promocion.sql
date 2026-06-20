-- ============================================================
-- Limpieza/retiro de feature · Dropear enviar_notificacion_promocion (rota-latente)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probe red-first P37 (función ausente). Retiro de feature (Oscar: opción B).
--
-- enviar_notificacion_promocion(text,text,text) era una RPC de broadcast masivo a pacientes,
-- ROTA-LATENTE: su DEFAULT p_tipo='promocion' VIOLA el CHECK de notificaciones_pacientes
-- (tipo IN ('cita','receta','examen','mensaje','general') — sin 'promocion') → toda llamada con
-- el default falla 23514. Nunca cableada al frontend (0 refs src/edge), 0 callers DB; solo la
-- ejercía el harness pasando un tipo válido explícito ('general'), enmascarando el bug.
-- Decisión Oscar = RETIRAR (no arreglar). DROP sin CASCADE (0 dependencias). Se eliminan los
-- probes P38/P39 (autorización del broadcast) y P37 pasa a verificar que la función ya no existe.
-- ============================================================

DROP FUNCTION IF EXISTS public.enviar_notificacion_promocion(text, text, text);
