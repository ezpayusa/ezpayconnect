-- ============================================================
-- 057: destinatarios_conversacion — a quién notificar (push) por un mensaje nuevo.
-- Devuelve los ids de cuenta que deben recibir push (miembros menos el autor).
-- Solo un miembro de la conversación puede consultarlo.
-- ============================================================
CREATE OR REPLACE FUNCTION destinatarios_conversacion(p_conv uuid)
RETURNS TABLE (cuenta_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE c_empresa uuid; c_tipo text; c_equipo uuid;
BEGIN
  IF NOT es_miembro_conversacion(p_conv) THEN RETURN; END IF;
  SELECT empresa_id, tipo, equipo_id INTO c_empresa, c_tipo, c_equipo FROM chat_conversaciones WHERE id = p_conv;
  IF c_tipo = 'administracion' THEN
    RETURN QUERY SELECT cp.id FROM cuentas_proveedor cp
      WHERE cp.empresa_id = c_empresa AND cp.activo = true AND cp.id <> auth.uid()
        AND cp.rol_en_empresa IN ('admin','editor','supervisor','catalogo','marketing','finanzas');
  ELSIF c_tipo = 'equipo' THEN
    RETURN QUERY SELECT cp.id FROM cuentas_proveedor cp
      WHERE cp.activo = true AND cp.id <> auth.uid()
        AND (cp.equipo_id = c_equipo OR cp.id IN (SELECT e.supervisor_id FROM equipos_visitadores e WHERE e.id = c_equipo));
  ELSIF c_tipo = 'directo' THEN
    RETURN QUERY SELECT p.cuenta_id FROM chat_participantes p WHERE p.conversacion_id = p_conv AND p.cuenta_id <> auth.uid();
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION destinatarios_conversacion(uuid) TO authenticated;
