-- ============================================================
-- 062 · Laboratorios clínicos: afiliación a clínicas, órdenes
--      de examen dirigidas a un lab, walk-in y lab de confianza.
-- (El enum examen_estado ya fue extendido con 'recibida','en_proceso')
-- ============================================================

-- ------------------------------------------------------------
-- 1. examenes: a qué laboratorio va, clínica de origen, walk-in
-- ------------------------------------------------------------
ALTER TABLE examenes
  ADD COLUMN IF NOT EXISTS laboratorio_id     UUID REFERENCES empresas_proveedoras(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS clinica_id         UUID REFERENCES clinicas(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS origen             TEXT NOT NULL DEFAULT 'medico',   -- 'medico' | 'walk_in'
  ADD COLUMN IF NOT EXISTS prioridad          TEXT NOT NULL DEFAULT 'normal',   -- 'normal' | 'urgente'
  ADD COLUMN IF NOT EXISTS paciente_nombre    TEXT,   -- walk-in sin registro / snapshot para el lab
  ADD COLUMN IF NOT EXISTS paciente_documento TEXT,
  ADD COLUMN IF NOT EXISTS paciente_telefono  TEXT,
  ADD COLUMN IF NOT EXISTS medico_nombre      TEXT,   -- snapshot (el lab no lee perfiles por RLS)
  ADD COLUMN IF NOT EXISTS clinica_nombre     TEXT;   -- snapshot

-- walk-in no tiene paciente registrado
ALTER TABLE examenes ALTER COLUMN paciente_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_examenes_laboratorio ON examenes(laboratorio_id);
CREATE INDEX IF NOT EXISTS idx_examenes_clinica     ON examenes(clinica_id);

-- ------------------------------------------------------------
-- 2. Lab de confianza del médico (preselección al ordenar)
-- ------------------------------------------------------------
ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS laboratorio_preferido_id UUID
    REFERENCES empresas_proveedoras(id) ON DELETE SET NULL;

-- ------------------------------------------------------------
-- 3. Afiliación laboratorio ↔ clínica (muchos-a-muchos)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS laboratorio_clinicas (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  laboratorio_id UUID NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  clinica_id     UUID NOT NULL REFERENCES clinicas(id) ON DELETE CASCADE,
  estado         TEXT NOT NULL DEFAULT 'activa',  -- 'activa' | 'inactiva'
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (laboratorio_id, clinica_id)
);
CREATE INDEX IF NOT EXISTS idx_lab_clinicas_lab     ON laboratorio_clinicas(laboratorio_id);
CREATE INDEX IF NOT EXISTS idx_lab_clinicas_clinica ON laboratorio_clinicas(clinica_id);

-- ------------------------------------------------------------
-- 4. Invitaciones de laboratorio (clínica → laboratorio)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invitaciones_laboratorio (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token              UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  clinica_id         UUID NOT NULL REFERENCES clinicas(id) ON DELETE CASCADE,
  pais_id            UUID REFERENCES configuracion_pais(id) ON DELETE SET NULL,
  email              TEXT NOT NULL,
  nombre_laboratorio TEXT,
  laboratorio_id     UUID REFERENCES empresas_proveedoras(id) ON DELETE SET NULL, -- si ya existe
  estado             TEXT NOT NULL DEFAULT 'pendiente', -- pendiente|aceptada|rechazada|expirada|cancelada
  expires_at         TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at       TIMESTAMPTZ,
  created_by         UUID REFERENCES perfiles(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_inv_lab_token   ON invitaciones_laboratorio(token);
CREATE INDEX IF NOT EXISTS idx_inv_lab_clinica ON invitaciones_laboratorio(clinica_id);
CREATE INDEX IF NOT EXISTS idx_inv_lab_email   ON invitaciones_laboratorio(lower(email));

-- ------------------------------------------------------------
-- 5. Helper: clínica del admin actual
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION mi_clinica_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT clinica_id FROM obtener_clinica_usuario(auth.uid()) LIMIT 1
$$;

-- ============================================================
-- 6. RLS
-- ============================================================
ALTER TABLE laboratorio_clinicas    ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitaciones_laboratorio ENABLE ROW LEVEL SECURITY;

-- Afiliaciones: el lab ve las suyas; el admin de clínica gestiona las de su clínica
DROP POLICY IF EXISTS lab_clinicas_lab_select ON laboratorio_clinicas;
CREATE POLICY lab_clinicas_lab_select ON laboratorio_clinicas
  FOR SELECT USING (laboratorio_id = mi_empresa_proveedor());

DROP POLICY IF EXISTS lab_clinicas_clinica_all ON laboratorio_clinicas;
CREATE POLICY lab_clinicas_clinica_all ON laboratorio_clinicas
  FOR ALL USING (clinica_id = mi_clinica_id()) WITH CHECK (clinica_id = mi_clinica_id());

-- Invitaciones: admin de clínica gestiona; lab ve las dirigidas a él (por empresa o email)
DROP POLICY IF EXISTS inv_lab_clinica_all ON invitaciones_laboratorio;
CREATE POLICY inv_lab_clinica_all ON invitaciones_laboratorio
  FOR ALL USING (clinica_id = mi_clinica_id()) WITH CHECK (clinica_id = mi_clinica_id());

DROP POLICY IF EXISTS inv_lab_lab_select ON invitaciones_laboratorio;
CREATE POLICY inv_lab_lab_select ON invitaciones_laboratorio
  FOR SELECT USING (
    laboratorio_id = mi_empresa_proveedor()
    OR lower(email) = (SELECT lower(email_contacto) FROM empresas_proveedoras WHERE id = mi_empresa_proveedor())
  );

-- examenes: el laboratorio asignado gestiona sus órdenes (ver, recibir, procesar,
-- subir resultado, y crear walk-in). Se SUMA a las políticas existentes de médico/paciente.
DROP POLICY IF EXISTS examenes_laboratorio_all ON examenes;
CREATE POLICY examenes_laboratorio_all ON examenes
  FOR ALL USING (laboratorio_id = mi_empresa_proveedor())
  WITH CHECK (laboratorio_id = mi_empresa_proveedor());

-- ============================================================
-- 7. RPCs (SECURITY DEFINER)
-- ============================================================

-- 7.1 Clínica invita a un laboratorio (por email)
CREATE OR REPLACE FUNCTION invitar_laboratorio(p_email TEXT, p_nombre TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_clinica UUID;
  v_pais    UUID;
  v_lab     UUID;
  v_token   UUID;
BEGIN
  v_clinica := mi_clinica_id();
  IF v_clinica IS NULL THEN
    RAISE EXCEPTION 'Solo el administrador de una clínica puede invitar laboratorios';
  END IF;

  SELECT pais_id INTO v_pais FROM clinicas WHERE id = v_clinica;

  -- ¿el lab ya existe como empresa?
  SELECT id INTO v_lab
  FROM empresas_proveedoras
  WHERE lower(email_contacto) = lower(p_email) AND tipo = 'laboratorio_clinico'
  LIMIT 1;

  IF v_lab IS NOT NULL AND EXISTS (
    SELECT 1 FROM laboratorio_clinicas
    WHERE laboratorio_id = v_lab AND clinica_id = v_clinica AND estado = 'activa'
  ) THEN
    RAISE EXCEPTION 'Ese laboratorio ya está afiliado a tu clínica';
  END IF;

  -- ¿invitación pendiente duplicada?
  IF EXISTS (
    SELECT 1 FROM invitaciones_laboratorio
    WHERE clinica_id = v_clinica AND lower(email) = lower(p_email) AND estado = 'pendiente'
  ) THEN
    RAISE EXCEPTION 'Ya hay una invitación pendiente para ese email';
  END IF;

  INSERT INTO invitaciones_laboratorio (clinica_id, pais_id, email, nombre_laboratorio, laboratorio_id, created_by)
  VALUES (v_clinica, v_pais, lower(p_email), p_nombre, v_lab, auth.uid())
  RETURNING token INTO v_token;

  RETURN jsonb_build_object('token', v_token, 'laboratorio_existe', v_lab IS NOT NULL);
END $$;

-- 7.2 Invitaciones pendientes para el laboratorio actual
CREATE OR REPLACE FUNCTION invitaciones_laboratorio_pendientes()
RETURNS TABLE (id UUID, token UUID, clinica_id UUID, clinica_nombre TEXT, created_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.id, i.token, i.clinica_id, c.nombre, i.created_at
  FROM invitaciones_laboratorio i
  JOIN clinicas c ON c.id = i.clinica_id
  WHERE i.estado = 'pendiente'
    AND (
      i.laboratorio_id = mi_empresa_proveedor()
      OR lower(i.email) = (SELECT lower(email_contacto) FROM empresas_proveedoras WHERE id = mi_empresa_proveedor())
    )
  ORDER BY i.created_at DESC
$$;

-- 7.3 El laboratorio acepta / rechaza una invitación
CREATE OR REPLACE FUNCTION responder_invitacion_laboratorio(p_token UUID, p_aceptar BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lab UUID;
  v_inv invitaciones_laboratorio%ROWTYPE;
BEGIN
  v_lab := mi_empresa_proveedor();
  IF v_lab IS NULL THEN
    RAISE EXCEPTION 'No estás asociado a un laboratorio';
  END IF;

  SELECT * INTO v_inv FROM invitaciones_laboratorio WHERE token = p_token AND estado = 'pendiente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitación no válida o ya respondida';
  END IF;

  IF p_aceptar THEN
    INSERT INTO laboratorio_clinicas (laboratorio_id, clinica_id)
    VALUES (v_lab, v_inv.clinica_id)
    ON CONFLICT (laboratorio_id, clinica_id) DO UPDATE SET estado = 'activa';

    UPDATE invitaciones_laboratorio
    SET estado = 'aceptada', responded_at = NOW(), laboratorio_id = v_lab
    WHERE id = v_inv.id;
  ELSE
    UPDATE invitaciones_laboratorio
    SET estado = 'rechazada', responded_at = NOW()
    WHERE id = v_inv.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'aceptada', p_aceptar);
END $$;

-- 7.4 Afiliaciones activas del laboratorio actual (clínicas)
CREATE OR REPLACE FUNCTION afiliaciones_laboratorio()
RETURNS TABLE (clinica_id UUID, clinica_nombre TEXT, ciudad TEXT, desde TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT lc.clinica_id, c.nombre, NULL::text, lc.created_at
  FROM laboratorio_clinicas lc
  JOIN clinicas c ON c.id = lc.clinica_id
  WHERE lc.laboratorio_id = mi_empresa_proveedor() AND lc.estado = 'activa'
  ORDER BY c.nombre
$$;

-- 7.5 Laboratorios disponibles para el médico (modal de orden)
CREATE OR REPLACE FUNCTION laboratorios_para_medico()
RETURNS TABLE (id UUID, nombre_empresa TEXT, ciudad TEXT, afiliado BOOLEAN, es_preferido BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pais    UUID;
  v_clinica UUID;
  v_pref    UUID;
BEGIN
  SELECT pais_id, laboratorio_preferido_id INTO v_pais, v_pref FROM perfiles WHERE id = auth.uid();
  SELECT clinica_id INTO v_clinica FROM obtener_clinica_principal_medico(auth.uid()) LIMIT 1;

  RETURN QUERY
  SELECT e.id, e.nombre_empresa, e.ciudad,
         EXISTS (
           SELECT 1 FROM laboratorio_clinicas lc
           WHERE lc.laboratorio_id = e.id AND lc.clinica_id = v_clinica AND lc.estado = 'activa'
         ) AS afiliado,
         (e.id = v_pref) AS es_preferido
  FROM empresas_proveedoras e
  WHERE e.tipo = 'laboratorio_clinico'
    AND e.estado = 'activa'
    AND (v_pais IS NULL OR e.pais_id = v_pais)
  ORDER BY afiliado DESC, es_preferido DESC, e.nombre_empresa;
END $$;

-- 7.5b Afiliaciones (labs) de la clínica del admin actual
CREATE OR REPLACE FUNCTION afiliaciones_de_clinica()
RETURNS TABLE (laboratorio_id UUID, nombre_empresa TEXT, ciudad TEXT, desde TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT lc.laboratorio_id, e.nombre_empresa, e.ciudad, lc.created_at
  FROM laboratorio_clinicas lc
  JOIN empresas_proveedoras e ON e.id = lc.laboratorio_id
  WHERE lc.clinica_id = mi_clinica_id() AND lc.estado = 'activa'
  ORDER BY e.nombre_empresa;
$$;

-- 7.5c Clínica principal del médico actual (para snapshot en la orden)
CREATE OR REPLACE FUNCTION mi_clinica_medico()
RETURNS TABLE (clinica_id UUID, clinica_nombre TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.id, c.nombre
  FROM obtener_clinica_principal_medico(auth.uid()) m
  JOIN clinicas c ON c.id = m.clinica_id
  LIMIT 1
$$;

-- 7.6 Notificar a todos los usuarios activos de un laboratorio
CREATE OR REPLACE FUNCTION notificar_laboratorio(
  p_laboratorio_id UUID, p_tipo TEXT, p_titulo TEXT,
  p_mensaje TEXT DEFAULT NULL, p_accion_url TEXT DEFAULT NULL
) RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
  INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
  SELECT cp.id, p_tipo, p_titulo, p_mensaje, p_accion_url
  FROM cuentas_proveedor cp
  WHERE cp.empresa_id = p_laboratorio_id AND cp.activo = true;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

GRANT EXECUTE ON FUNCTION mi_clinica_id() TO authenticated;
GRANT EXECUTE ON FUNCTION invitar_laboratorio(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION invitaciones_laboratorio_pendientes() TO authenticated;
GRANT EXECUTE ON FUNCTION responder_invitacion_laboratorio(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION afiliaciones_laboratorio() TO authenticated;
GRANT EXECUTE ON FUNCTION laboratorios_para_medico() TO authenticated;
GRANT EXECUTE ON FUNCTION afiliaciones_de_clinica() TO authenticated;
GRANT EXECUTE ON FUNCTION mi_clinica_medico() TO authenticated;
GRANT EXECUTE ON FUNCTION notificar_laboratorio(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 7.7 Notificar resultado de examen al médico y al paciente (solo el lab dueño)
CREATE OR REPLACE FUNCTION notificar_resultado_examen(p_examen_id INTEGER)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v examenes%ROWTYPE;
BEGIN
  SELECT * INTO v FROM examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v.laboratorio_id IS DISTINCT FROM mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF v.paciente_id IS NOT NULL THEN
    PERFORM notificar_paciente(
      v.paciente_id, 'examen_resultado', 'Resultado de examen listo',
      'Tu examen ' || v.tipo || ' ya tiene resultado.', '/paciente/examenes');
  END IF;

  IF v.medico_id IS NOT NULL THEN
    INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
    VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
      'El laboratorio subió el resultado de ' || v.tipo || ' (' || COALESCE(v.paciente_nombre, 'paciente') || ').',
      '/medico/citas');
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION notificar_resultado_examen(INTEGER) TO authenticated;
