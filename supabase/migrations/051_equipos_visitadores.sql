-- ============================================================
-- 051: Equipos de visitadores (supervisores aislados entre sí)
-- ------------------------------------------------------------
-- Una empresa puede tener varios equipos, cada uno con UN supervisor y sus
-- visitadores. Confidencialidad: un supervisor solo ve los visitadores de SUS
-- equipos y sus visitas; no ve los de otro supervisor (aunque tengan igual rol).
-- Gestión: admin crea equipos y asigna a cualquiera; el supervisor puede
-- gestionar SOLO su(s) propio(s) equipo(s).
-- ============================================================

CREATE TABLE IF NOT EXISTS equipos_visitadores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  nombre text NOT NULL,
  zona text,
  supervisor_id uuid REFERENCES cuentas_proveedor(id) ON DELETE SET NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_equipos_empresa ON equipos_visitadores(empresa_id);
CREATE INDEX IF NOT EXISTS idx_equipos_supervisor ON equipos_visitadores(supervisor_id);

-- A qué equipo pertenece cada visitador (uno solo).
ALTER TABLE cuentas_proveedor
  ADD COLUMN IF NOT EXISTS equipo_id uuid REFERENCES equipos_visitadores(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_cuentas_equipo ON cuentas_proveedor(equipo_id);

-- ¿El usuario actual (supervisor) supervisa el equipo de esta cuenta?
CREATE OR REPLACE FUNCTION supervisa_cuenta_proveedor(p_cuenta_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM cuentas_proveedor cp
    JOIN equipos_visitadores e ON e.id = cp.equipo_id
    WHERE cp.id = p_cuenta_id AND e.supervisor_id = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION supervisa_cuenta_proveedor(uuid) TO authenticated;

-- ---------- RLS de equipos_visitadores ----------
ALTER TABLE equipos_visitadores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Equipos: ver segun rol" ON equipos_visitadores;
CREATE POLICY "Equipos: ver segun rol" ON equipos_visitadores
FOR SELECT USING (
  empresa_id = mi_empresa_proveedor() AND (
    mi_rol_proveedor() IN ('admin', 'editor')
    OR supervisor_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Equipos: admin gestiona" ON equipos_visitadores;
CREATE POLICY "Equipos: admin gestiona" ON equipos_visitadores
FOR ALL
USING (empresa_id = mi_empresa_proveedor() AND mi_rol_proveedor() IN ('admin', 'editor'))
WITH CHECK (empresa_id = mi_empresa_proveedor() AND mi_rol_proveedor() IN ('admin', 'editor'));

-- ---------- cuentas_proveedor: supervisor ve a su equipo + pool libre ----------
-- Ve los visitadores de SUS equipos, y los visitadores SIN equipo (pool libre)
-- para poder sumarlos. NO ve los de otro supervisor.
DROP POLICY IF EXISTS "Supervisor ve cuentas de su equipo" ON cuentas_proveedor;
CREATE POLICY "Supervisor ve cuentas de su equipo" ON cuentas_proveedor
FOR SELECT USING (
  mi_rol_proveedor() = 'supervisor' AND (
    supervisa_cuenta_proveedor(id)
    OR (empresa_id = mi_empresa_proveedor() AND rol_en_empresa = 'visitador_medico' AND equipo_id IS NULL)
  )
);

-- ---------- visitas: supervisor SOLO ve las de su equipo ----------
DROP POLICY IF EXISTS "Proveedor ve visitas segun rol" ON visitas_agendadas;
CREATE POLICY "Proveedor ve visitas segun rol" ON visitas_agendadas
FOR SELECT USING (
  empresa_id = mi_empresa_proveedor() AND (
    mi_rol_proveedor() IN ('admin', 'editor')               -- admin/editor: todas
    OR cuenta_proveedor_id = auth.uid()                      -- visitador: las suyas
    OR propuesta_por = auth.uid()
    OR (mi_rol_proveedor() = 'supervisor' AND supervisa_cuenta_proveedor(cuenta_proveedor_id))
  )
);

-- ---------- RPC: asignar/quitar visitador de un equipo ----------
-- p_equipo_id NULL = quitar del equipo. Admin: cualquier equipo. Supervisor:
-- solo sus equipos, y no puede tocar visitadores del equipo de otro supervisor.
CREATE OR REPLACE FUNCTION asignar_visitador_equipo(p_visitador_id uuid, p_equipo_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller_rol text;
  v_caller_empresa uuid;
  v_vis_empresa uuid;
  v_vis_equipo uuid;
  v_target_sup uuid;
  v_current_sup uuid;
BEGIN
  SELECT rol_en_empresa, empresa_id INTO v_caller_rol, v_caller_empresa
  FROM cuentas_proveedor WHERE id = auth.uid();

  SELECT empresa_id, equipo_id INTO v_vis_empresa, v_vis_equipo
  FROM cuentas_proveedor WHERE id = p_visitador_id;
  IF v_vis_empresa IS NULL OR v_vis_empresa IS DISTINCT FROM v_caller_empresa THEN
    RAISE EXCEPTION 'El visitador no pertenece a tu empresa';
  END IF;

  IF p_equipo_id IS NOT NULL THEN
    SELECT supervisor_id INTO v_target_sup FROM equipos_visitadores
    WHERE id = p_equipo_id AND empresa_id = v_caller_empresa;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo no válido'; END IF;
  END IF;
  IF v_vis_equipo IS NOT NULL THEN
    SELECT supervisor_id INTO v_current_sup FROM equipos_visitadores WHERE id = v_vis_equipo;
  END IF;

  IF v_caller_rol IN ('admin', 'editor') THEN
    NULL; -- admin sin límite
  ELSIF v_caller_rol = 'supervisor' THEN
    IF v_vis_equipo IS NOT NULL AND v_current_sup IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Ese visitador pertenece al equipo de otro supervisor';
    END IF;
    IF p_equipo_id IS NOT NULL AND v_target_sup IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Solo puedes asignar visitadores a tus propios equipos';
    END IF;
  ELSE
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE cuentas_proveedor SET equipo_id = p_equipo_id, updated_at = now()
  WHERE id = p_visitador_id;
END;
$$;
GRANT EXECUTE ON FUNCTION asignar_visitador_equipo(uuid, uuid) TO authenticated;
