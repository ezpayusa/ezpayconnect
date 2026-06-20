-- ============================================================
-- Ola 3 · RBAC configurable per-empresa (capa override SOBRE el catálogo global). SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — maquinaria INERTE día-0 (sin overrides = idéntico al catálogo). Probes P330–P342.
--
-- v1 = SOLO farmacia + empresa_afin (labs sin catálogo = deuda preexistente, fuera de alcance).
-- Override per (empresa_id, rol, accion) con concedido bool (TRUE concede / FALSE revoca) SOBRE el
-- default del catálogo permisos_empresa_rol(tipo_empresa, rol, accion). Ausencia de fila = hereda.
-- TECHO (no-editable): pagos_ezpay, publicidad_gestionar, usuarios_roles, sucursales_gestionar.
-- TECHO AUTORITATIVO EN LA RESOLUCIÓN (no solo en el write): tiene_permiso IGNORA el override para
-- acciones de techo → cierra (i) acción añadida al techo tras un override, (ii) super_admin/insert
-- directo que bypassa el RPC, (iii) filas override stale. tiene_permiso = único chokepoint (l.7) →
-- los ~17 consumidores heredan sin tocarse.
-- ============================================================

-- 1) Catálogo de techo (acciones no-editables por empresa)
CREATE TABLE IF NOT EXISTS public.acciones_techo (accion text PRIMARY KEY);
INSERT INTO public.acciones_techo (accion) VALUES
  ('pagos_ezpay'), ('publicidad_gestionar'), ('usuarios_roles'), ('sucursales_gestionar')
  ON CONFLICT DO NOTHING;
ALTER TABLE public.acciones_techo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS acciones_techo_read ON public.acciones_techo;
CREATE POLICY acciones_techo_read  ON public.acciones_techo FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS acciones_techo_write ON public.acciones_techo;
CREATE POLICY acciones_techo_write ON public.acciones_techo FOR ALL TO authenticated
  USING (COALESCE(private.tiene_rol(ARRAY['super_admin']), false))
  WITH CHECK (COALESCE(private.tiene_rol(ARRAY['super_admin']), false));
REVOKE ALL ON public.acciones_techo FROM anon;   -- anon sin nada; authenticated gateado por RLS (super_admin)

-- 2) Tabla override per-empresa (capa sobre el catálogo)
CREATE TABLE IF NOT EXISTS public.permisos_empresa_rol_override (
  empresa_id uuid NOT NULL REFERENCES public.empresas_proveedoras(id) ON DELETE CASCADE,
  rol        text NOT NULL,
  accion     text NOT NULL,
  concedido  boolean NOT NULL,                    -- TRUE concede / FALSE revoca (vs catálogo)
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (empresa_id, rol, accion)
);
ALTER TABLE public.permisos_empresa_rol_override ENABLE ROW LEVEL SECURITY;
-- SELECT: solo su propia empresa (+ super_admin). NO hay write policy → escritura SOLO vía el RPC DEFINER.
DROP POLICY IF EXISTS override_select_own ON public.permisos_empresa_rol_override;
CREATE POLICY override_select_own ON public.permisos_empresa_rol_override FOR SELECT TO authenticated
  USING (COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
         OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false));
-- write SOLO vía RPC: revocar DML directo de anon/authenticated (el RPC DEFINER bypassa como owner)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.permisos_empresa_rol_override FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.permisos_empresa_rol_override FROM anon;
GRANT  SELECT ON public.permisos_empresa_rol_override TO authenticated;   -- lectura gateada por RLS

-- 3) tiene_permiso: catálogo MODIFICADO por override, con TECHO AUTORITATIVO en la resolución.
CREATE OR REPLACE FUNCTION private.tiene_permiso(p_accion text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  WITH me AS (
    SELECT cp.empresa_id AS emp, cp.rol_en_empresa AS rol, e.tipo AS tipo
    FROM public.cuentas_proveedor cp
    JOIN public.empresas_proveedoras e ON e.id = cp.empresa_id
    WHERE cp.id = auth.uid() AND cp.activo = true
    LIMIT 1
  ),
  cat AS (   -- default del catálogo para (tipo de SU empresa, su rol, accion)
    SELECT EXISTS (
      SELECT 1 FROM public.permisos_empresa_rol per JOIN me ON per.tipo_empresa = me.tipo AND per.rol = me.rol
      WHERE per.accion = p_accion
    ) AS d
  ),
  ovr AS (   -- override per (empresa, rol, accion)
    SELECT o.concedido AS c
    FROM public.permisos_empresa_rol_override o JOIN me ON o.empresa_id = me.emp AND o.rol = me.rol
    WHERE o.accion = p_accion
    LIMIT 1
  )
  SELECT COALESCE(
    CASE
      WHEN EXISTS (SELECT 1 FROM public.acciones_techo t WHERE t.accion = p_accion)
        THEN (SELECT d FROM cat)                           -- TECHO: ignora el override
      ELSE COALESCE((SELECT c FROM ovr), (SELECT d FROM cat))
    END, false);                                            -- fail-closed
$function$;
-- (grants/EXECUTE de tiene_permiso intactos por CREATE OR REPLACE)

-- 4) RPC de edición (único write path del override). 5 gates conjuntivos + SQLSTATE custom por clase.
CREATE OR REPLACE FUNCTION public.set_permiso_override(p_rol text, p_accion text, p_concedido boolean)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_emp uuid; v_tipo text;
BEGIN
  -- (a) empresa del actor (fail-closed, sin subquery cruda)
  v_emp := public.mi_empresa_proveedor();
  IF v_emp IS NULL THEN RAISE EXCEPTION 'No autorizado: sin empresa proveedora' USING ERRCODE = 'PR001'; END IF;
  -- (b) actor gestiona usuarios (incluye override en su resolución)
  IF NOT COALESCE(private.tiene_permiso('usuarios_roles'), false) THEN
    RAISE EXCEPTION 'No autorizado: requiere usuarios_roles' USING ERRCODE = 'PR001'; END IF;
  -- (c) techo
  IF EXISTS (SELECT 1 FROM public.acciones_techo WHERE accion = p_accion) THEN
    RAISE EXCEPTION 'Acción de techo no editable por empresa: %', p_accion USING ERRCODE = 'PR002'; END IF;
  -- (d) validez: rol válido para el tipo + accion del PROPIO tipo (universo concedible acotado)
  SELECT e.tipo INTO v_tipo FROM public.empresas_proveedoras e WHERE e.id = v_emp;
  IF NOT EXISTS (SELECT 1 FROM public.roles_empresa_catalogo r WHERE r.tipo_empresa = v_tipo AND r.rol = p_rol) THEN
    RAISE EXCEPTION 'Rol inválido para el tipo de empresa' USING ERRCODE = 'PR003'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.permisos_empresa_rol per WHERE per.tipo_empresa = v_tipo AND per.accion = p_accion) THEN
    RAISE EXCEPTION 'Acción inválida para el tipo de empresa' USING ERRCODE = 'PR003'; END IF;
  -- (e) anti-lockout: GARANTIZADO porque usuarios_roles ∈ techo → no revocable vía override (eco l.14).
  -- UPSERT scopeado a la empresa propia
  INSERT INTO public.permisos_empresa_rol_override (empresa_id, rol, accion, concedido, created_by)
    VALUES (v_emp, p_rol, p_accion, p_concedido, auth.uid())
    ON CONFLICT (empresa_id, rol, accion) DO UPDATE SET concedido = EXCLUDED.concedido, updated_at = now(), created_by = auth.uid();
  RETURN p_concedido;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.set_permiso_override(text,text,boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_permiso_override(text,text,boolean) TO authenticated;

-- 5) Higiene de grants en el catálogo existente: revocar ANON (ruido). authenticated WRITE se MANTIENE
--    (load-bearing: super_admin comparte el rol DB authenticated y edita el catálogo directo; RLS
--    perm_emp_write lo gatea). Mover edición de catálogo a RPC = fuera de alcance de este paquete.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.permisos_empresa_rol FROM anon;
