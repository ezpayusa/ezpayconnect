-- ============================================================
-- 056: sincronizar_mis_canales — crea los canales que le tocan al usuario
-- (Administración si es admin-tier; el canal de su equipo y/o de los equipos
-- que supervisa). Se llama al abrir la pantalla de Mensajes.
-- ============================================================
CREATE OR REPLACE FUNCTION sincronizar_mis_canales()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rol text; v_empresa uuid; v_equipo uuid; r RECORD;
BEGIN
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo
  FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL THEN RETURN; END IF;

  IF v_rol IN ('admin','editor','supervisor','catalogo','marketing','finanzas')
     AND NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE empresa_id = v_empresa AND tipo = 'administracion') THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, nombre) VALUES (v_empresa, 'administracion', 'Administración');
  END IF;

  IF v_equipo IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = v_equipo) THEN
    INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre)
    SELECT v_empresa, 'equipo', e.id, e.nombre FROM equipos_visitadores e WHERE e.id = v_equipo;
  END IF;

  FOR r IN SELECT e.id, e.nombre FROM equipos_visitadores e WHERE e.supervisor_id = auth.uid() AND e.empresa_id = v_empresa LOOP
    IF NOT EXISTS (SELECT 1 FROM chat_conversaciones WHERE tipo = 'equipo' AND equipo_id = r.id) THEN
      INSERT INTO chat_conversaciones (empresa_id, tipo, equipo_id, nombre) VALUES (v_empresa, 'equipo', r.id, r.nombre);
    END IF;
  END LOOP;
END; $$;
GRANT EXECUTE ON FUNCTION sincronizar_mis_canales() TO authenticated;
