-- 205 Personalización de tema por tenant (clínica / empresa proveedora) — modelo + RPCs.
-- Escritura de columnas de tema (logo_url + colores) EXCLUSIVA por RPC aprobado (guard por trigger).
-- Muro ético: no toca agenda de paciente. ERRCODEs familia PT (personalización tema).

-- ===== Columnas de tema en los tenants =====
ALTER TABLE public.clinicas
  ADD COLUMN IF NOT EXISTS logo_url         text,
  ADD COLUMN IF NOT EXISTS color_primario   text,
  ADD COLUMN IF NOT EXISTS color_secundario text,
  ADD COLUMN IF NOT EXISTS color_fondo      text;
ALTER TABLE public.empresas_proveedoras
  ADD COLUMN IF NOT EXISTS color_primario   text,
  ADD COLUMN IF NOT EXISTS color_secundario text,
  ADD COLUMN IF NOT EXISTS color_fondo      text;  -- logo_url ya existía

-- ===== Tabla de solicitudes =====
CREATE TABLE IF NOT EXISTS public.solicitudes_personalizacion (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_tipo      text NOT NULL CHECK (tenant_tipo IN ('clinica','empresa_proveedora')),
  tenant_id        uuid NOT NULL,
  logo_url         text,
  color_primario   text,
  color_secundario text,
  color_fondo      text,
  estado           text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobada','rechazada')),
  solicitado_por   uuid NOT NULL REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  revisado_por     uuid REFERENCES auth.users(id),
  revisado_at      timestamptz,
  motivo_rechazo   text
);
CREATE INDEX IF NOT EXISTS idx_sol_pers_tenant ON public.solicitudes_personalizacion(tenant_tipo, tenant_id);
CREATE INDEX IF NOT EXISTS idx_sol_pers_pend   ON public.solicitudes_personalizacion(estado) WHERE estado='pendiente';

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.solicitudes_personalizacion FROM authenticated;
REVOKE ALL ON public.solicitudes_personalizacion FROM anon;

-- ===== Helper: ¿el tenant es del caller? (para RLS de lectura) =====
CREATE OR REPLACE FUNCTION private.es_mi_tenant(p_tenant_tipo text, p_tenant_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
  SELECT CASE p_tenant_tipo
    WHEN 'empresa_proveedora' THEN p_tenant_id = public.mi_empresa_proveedor()
    WHEN 'clinica'            THEN p_tenant_id IN (SELECT private.clinicas_de(auth.uid()))
    ELSE false END;
$function$;
REVOKE ALL     ON FUNCTION private.es_mi_tenant(text,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.es_mi_tenant(text,uuid) TO authenticated;

ALTER TABLE public.solicitudes_personalizacion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant ve sus solicitudes" ON public.solicitudes_personalizacion;
CREATE POLICY "Tenant ve sus solicitudes" ON public.solicitudes_personalizacion
  FOR SELECT TO authenticated USING (private.es_mi_tenant(tenant_tipo, tenant_id));
DROP POLICY IF EXISTS "Super admin ve solicitudes" ON public.solicitudes_personalizacion;
CREATE POLICY "Super admin ve solicitudes" ON public.solicitudes_personalizacion
  FOR SELECT TO authenticated USING (private.tiene_rol(ARRAY['super_admin']));

-- ===== Guard: columnas de tema solo escribibles dentro del RPC (que setea el GUC) =====
CREATE OR REPLACE FUNCTION private.trg_guard_tema_columns()
RETURNS trigger LANGUAGE plpgsql SET search_path = public
AS $function$
BEGIN
  IF current_setting('app.personalizacion_rpc', true) = 'on' THEN
    RETURN NEW;  -- viene de aprobar_personalizacion
  END IF;
  IF NEW.logo_url         IS DISTINCT FROM OLD.logo_url
     OR NEW.color_primario   IS DISTINCT FROM OLD.color_primario
     OR NEW.color_secundario IS DISTINCT FROM OLD.color_secundario
     OR NEW.color_fondo      IS DISTINCT FROM OLD.color_fondo THEN
    RAISE EXCEPTION 'Las columnas de tema solo se cambian por el flujo de personalización aprobada.'
      USING ERRCODE = 'PT001';
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trigger_guard_tema_clinicas ON public.clinicas;
CREATE TRIGGER trigger_guard_tema_clinicas BEFORE UPDATE ON public.clinicas
  FOR EACH ROW EXECUTE FUNCTION private.trg_guard_tema_columns();
DROP TRIGGER IF EXISTS trigger_guard_tema_empresas ON public.empresas_proveedoras;
CREATE TRIGGER trigger_guard_tema_empresas BEFORE UPDATE ON public.empresas_proveedoras
  FOR EACH ROW EXECUTE FUNCTION private.trg_guard_tema_columns();

-- ===== RPC (a) solicitar_personalizacion — deriva tenant del caller =====
CREATE OR REPLACE FUNCTION public.solicitar_personalizacion(
  p_logo_url text, p_color_primario text, p_color_secundario text, p_color_fondo text)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_empresa uuid; v_clinica uuid; v_tipo text; v_tenant uuid; v_id uuid;
BEGIN
  v_empresa := public.mi_empresa_proveedor();
  IF v_empresa IS NOT NULL THEN
    IF public.mi_rol_proveedor() <> 'admin' THEN RAISE EXCEPTION 'rol_insuficiente' USING ERRCODE='PT003'; END IF;
    v_tipo := 'empresa_proveedora'; v_tenant := v_empresa;
  ELSE
    IF NOT COALESCE(private.tiene_rol(ARRAY['admin_clinica','gerente']), false) THEN
      RAISE EXCEPTION 'rol_insuficiente' USING ERRCODE='PT003'; END IF;
    SELECT s.clinica_id INTO v_clinica
    FROM (SELECT private.clinicas_de(auth.uid()) AS clinica_id) s
    ORDER BY (EXISTS (SELECT 1 FROM public.medico_clinicas mc
                      WHERE mc.medico_id=auth.uid() AND mc.clinica_id=s.clinica_id AND mc.es_principal)) DESC
    LIMIT 1;
    IF v_clinica IS NULL THEN RAISE EXCEPTION 'sin_tenant' USING ERRCODE='PT006'; END IF;
    v_tipo := 'clinica'; v_tenant := v_clinica;
  END IF;

  INSERT INTO public.solicitudes_personalizacion
    (tenant_tipo, tenant_id, logo_url, color_primario, color_secundario, color_fondo, solicitado_por)
  VALUES (v_tipo, v_tenant, p_logo_url, p_color_primario, p_color_secundario, p_color_fondo, auth.uid())
  RETURNING id INTO v_id;

  -- TODO push a super_admin (patrón push-in-RPC pg_net→edge) — se cablea tras confirmar el helper exacto.
  RETURN v_id;
END;
$function$;
REVOKE ALL     ON FUNCTION public.solicitar_personalizacion(text,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.solicitar_personalizacion(text,text,text,text) TO authenticated;

-- ===== RPC (b) aprobar_personalizacion — super_admin, atómico =====
CREATE OR REPLACE FUNCTION public.aprobar_personalizacion(p_solicitud_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_s RECORD;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;

  SELECT * INTO v_s FROM public.solicitudes_personalizacion WHERE id = p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_s.estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;

  PERFORM set_config('app.personalizacion_rpc','on', true);  -- habilita el guard SOLO en esta tx

  IF v_s.tenant_tipo = 'clinica' THEN
    UPDATE public.clinicas
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  ELSE
    UPDATE public.empresas_proveedoras
      SET logo_url=v_s.logo_url, color_primario=v_s.color_primario,
          color_secundario=v_s.color_secundario, color_fondo=v_s.color_fondo
      WHERE id = v_s.tenant_id;
  END IF;

  UPDATE public.solicitudes_personalizacion
    SET estado='aprobada', revisado_por=auth.uid(), revisado_at=now()
    WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok',true,'estado','aprobada','tenant_tipo',v_s.tenant_tipo,'tenant_id',v_s.tenant_id);
END;
$function$;
REVOKE ALL     ON FUNCTION public.aprobar_personalizacion(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.aprobar_personalizacion(uuid) TO authenticated;

-- ===== RPC (c) rechazar_personalizacion — super_admin, no copia datos =====
CREATE OR REPLACE FUNCTION public.rechazar_personalizacion(p_solicitud_id uuid, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_estado text;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE='PT001'; END IF;
  SELECT estado INTO v_estado FROM public.solicitudes_personalizacion WHERE id=p_solicitud_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_inexistente' USING ERRCODE='PT004'; END IF;
  IF v_estado <> 'pendiente' THEN RAISE EXCEPTION 'solicitud_ya_resuelta' USING ERRCODE='PT005'; END IF;
  UPDATE public.solicitudes_personalizacion
    SET estado='rechazada', revisado_por=auth.uid(), revisado_at=now(), motivo_rechazo=p_motivo
    WHERE id=p_solicitud_id;
  RETURN jsonb_build_object('ok',true,'estado','rechazada');
END;
$function$;
REVOKE ALL     ON FUNCTION public.rechazar_personalizacion(uuid,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.rechazar_personalizacion(uuid,text) TO authenticated;
