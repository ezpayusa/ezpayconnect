-- 253: RPC listar_transacciones_pais (país-scoped) para FinanzasPage.
-- transacciones tiene RLS ON + 0 policies → PostgREST directo da 0; se lee por esta RPC DEFINER.
-- super_admin: todos (o filtra p_pais_id). admin_pais: forzado a su país. otro rol: RAISE PC021.

CREATE OR REPLACE FUNCTION public.listar_transacciones_pais(
  p_estado  text DEFAULT NULL,
  p_pais_id uuid DEFAULT NULL,
  p_limit   int  DEFAULT 50
)
RETURNS TABLE (
  id          uuid,
  plan_id     uuid,
  pais_id     uuid,
  monto       numeric,
  estado      text,
  metodo_pago text,
  fecha_pago  timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_rol         text := public.get_auth_user_rol();
  v_pais_caller uuid := public.get_auth_user_pais_id();
  v_filtro_pais uuid;
BEGIN
  -- Gate de rol (cortocircuito super_admin, patrón admin_pais / mig 252)
  IF v_rol = 'super_admin' THEN
    v_filtro_pais := p_pais_id;            -- NULL = todos los países
  ELSIF v_rol = 'admin_pais' THEN
    IF v_pais_caller IS NULL THEN
      RAISE EXCEPTION 'admin_pais sin pais asignado' USING ERRCODE = 'PC021';
    END IF;
    v_filtro_pais := v_pais_caller;        -- forzado al suyo, ignora p_pais_id
  ELSE
    RAISE EXCEPTION 'No autorizado: solo super_admin o admin_pais' USING ERRCODE = 'PC021';
  END IF;

  RETURN QUERY
    SELECT t.id,
           t.plan_id,
           t.pais_id,
           t.monto,
           t.estado::text,
           t.metodo_pago::text,
           t.fecha_pago
      FROM public.transacciones t
     WHERE (p_estado IS NULL OR t.estado = p_estado)
       AND (v_filtro_pais IS NULL OR t.pais_id = v_filtro_pais)
     ORDER BY t.fecha_pago DESC NULLS LAST
     LIMIT GREATEST(1, LEAST(p_limit, 500));   -- cota defensiva
END;
$$;

REVOKE ALL ON FUNCTION public.listar_transacciones_pais(text, uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.listar_transacciones_pais(text, uuid, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.listar_transacciones_pais(text, uuid, int) TO authenticated;
