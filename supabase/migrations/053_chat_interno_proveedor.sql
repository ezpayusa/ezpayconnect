-- ============================================================
-- 053: Chat interno del proveedor (con confidencialidad por rol/equipo)
-- ------------------------------------------------------------
-- Canales:
--   administracion: admin + administrativos (catalogo/marketing/finanzas) + supervisores
--   equipo:         supervisor + sus visitadores (uno por equipo)
--   directo:        1-a-1 entre pares permitidos por la matriz
-- Membresía de administracion/equipo es DINÁMICA (por rol/equipo, sin sync).
-- Auditoría: admin o quien tenga audita_chat=true puede LEER (no escribir) las
-- conversaciones de operación (equipo/directo) de su empresa.
-- ============================================================

ALTER TABLE cuentas_proveedor ADD COLUMN IF NOT EXISTS audita_chat boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS chat_conversaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas_proveedoras(id) ON DELETE CASCADE,
  tipo text NOT NULL CHECK (tipo IN ('administracion','equipo','directo')),
  equipo_id uuid REFERENCES equipos_visitadores(id) ON DELETE CASCADE,
  nombre text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_chat_admin_empresa ON chat_conversaciones(empresa_id) WHERE tipo='administracion';
CREATE UNIQUE INDEX IF NOT EXISTS ux_chat_equipo ON chat_conversaciones(equipo_id) WHERE tipo='equipo';

CREATE TABLE IF NOT EXISTS chat_participantes (
  conversacion_id uuid NOT NULL REFERENCES chat_conversaciones(id) ON DELETE CASCADE,
  cuenta_id uuid NOT NULL REFERENCES cuentas_proveedor(id) ON DELETE CASCADE,
  PRIMARY KEY (conversacion_id, cuenta_id)
);

CREATE TABLE IF NOT EXISTS chat_mensajes_internos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversacion_id uuid NOT NULL REFERENCES chat_conversaciones(id) ON DELETE CASCADE,
  autor_id uuid NOT NULL REFERENCES cuentas_proveedor(id),
  cuerpo text NOT NULL,
  eliminado boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_chat_msg_conv ON chat_mensajes_internos(conversacion_id, created_at);

CREATE TABLE IF NOT EXISTS chat_lecturas (
  conversacion_id uuid NOT NULL REFERENCES chat_conversaciones(id) ON DELETE CASCADE,
  cuenta_id uuid NOT NULL REFERENCES cuentas_proveedor(id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversacion_id, cuenta_id)
);

-- ---------- Helpers ----------
CREATE OR REPLACE FUNCTION mi_equipo_proveedor()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT equipo_id FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true LIMIT 1; $$;

CREATE OR REPLACE FUNCTION puede_auditar_chat()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true AND (rol_en_empresa='admin' OR audita_chat=true)); $$;

-- ¿soy miembro (puedo escribir) de la conversación?
CREATE OR REPLACE FUNCTION es_miembro_conversacion(p_conv uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE c_empresa uuid; c_tipo text; c_equipo uuid; v_rol text; v_empresa uuid; v_equipo uuid;
BEGIN
  SELECT empresa_id, tipo, equipo_id INTO c_empresa, c_tipo, c_equipo FROM chat_conversaciones WHERE id = p_conv;
  IF c_empresa IS NULL THEN RETURN false; END IF;
  SELECT rol_en_empresa, empresa_id, equipo_id INTO v_rol, v_empresa, v_equipo FROM cuentas_proveedor WHERE id = auth.uid() AND activo = true;
  IF v_empresa IS NULL OR v_empresa <> c_empresa THEN RETURN false; END IF;
  IF c_tipo = 'administracion' THEN
    RETURN v_rol IN ('admin','editor','supervisor','catalogo','marketing','finanzas');
  ELSIF c_tipo = 'equipo' THEN
    RETURN v_equipo = c_equipo OR EXISTS (SELECT 1 FROM equipos_visitadores WHERE id = c_equipo AND supervisor_id = auth.uid());
  ELSIF c_tipo = 'directo' THEN
    RETURN EXISTS (SELECT 1 FROM chat_participantes WHERE conversacion_id = p_conv AND cuenta_id = auth.uid());
  END IF;
  RETURN false;
END; $$;

-- ¿puedo VER la conversación? (miembro o auditor de operación)
CREATE OR REPLACE FUNCTION puede_ver_conversacion(p_conv uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE c_empresa uuid; c_tipo text;
BEGIN
  IF es_miembro_conversacion(p_conv) THEN RETURN true; END IF;
  SELECT empresa_id, tipo INTO c_empresa, c_tipo FROM chat_conversaciones WHERE id = p_conv;
  IF c_empresa IS NULL THEN RETURN false; END IF;
  RETURN puede_auditar_chat() AND c_empresa = mi_empresa_proveedor() AND c_tipo IN ('equipo','directo');
END; $$;

-- ---------- RLS ----------
ALTER TABLE chat_conversaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chat_conv_select ON chat_conversaciones;
CREATE POLICY chat_conv_select ON chat_conversaciones FOR SELECT USING (puede_ver_conversacion(id));

ALTER TABLE chat_participantes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chat_part_select ON chat_participantes;
CREATE POLICY chat_part_select ON chat_participantes FOR SELECT USING (puede_ver_conversacion(conversacion_id));

ALTER TABLE chat_mensajes_internos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chat_msg_select ON chat_mensajes_internos;
CREATE POLICY chat_msg_select ON chat_mensajes_internos FOR SELECT USING (puede_ver_conversacion(conversacion_id));

ALTER TABLE chat_lecturas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chat_lect_own ON chat_lecturas;
CREATE POLICY chat_lect_own ON chat_lecturas FOR ALL USING (cuenta_id = auth.uid()) WITH CHECK (cuenta_id = auth.uid());

-- Realtime para mensajes
ALTER PUBLICATION supabase_realtime ADD TABLE chat_mensajes_internos;
