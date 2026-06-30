-- 178 Ola 2 backend "catálogo de premios por país"
-- Premios definidos por la plataforma, SEGMENTADOS POR PAÍS, stock limitado + imagen. Canje con aprobación = Ola 3.
-- País del paciente = pacientes.pais_id (uuid → configuracion_pais.id); NO se deriva de clínica (puede ser null).
-- Imágenes: bucket PÚBLICO 'premios' (catálogo no-PHI, patrón de 'productos'); escritura solo super_admin.

-- ============================================================
-- 1) TABLA premios
-- ============================================================
CREATE TABLE IF NOT EXISTS public.premios (
  id           bigserial PRIMARY KEY,
  nombre       text NOT NULL,
  descripcion  text,
  costo_puntos int  NOT NULL CHECK (costo_puntos > 0),
  pais_id      uuid NOT NULL REFERENCES public.configuracion_pais(id),  -- premio pertenece a UN país
  tipo         text NOT NULL CHECK (tipo IN ('descuento','fisico','sorteo')),
  stock        int  NOT NULL DEFAULT 0 CHECK (stock >= 0),               -- 0 = agotado
  imagen_path  text,                                                      -- path en bucket público 'premios'
  activo       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Escritura por super_admin/RPC admin (fuera del flujo paciente), NO por paciente.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.premios FROM authenticated;
REVOKE ALL ON public.premios FROM anon;

ALTER TABLE public.premios ENABLE ROW LEVEL SECURITY;
-- authenticated ve solo activos (el RPC afina por país); super_admin ve todo.
DROP POLICY IF EXISTS "Authenticated ve premios activos" ON public.premios;
CREATE POLICY "Authenticated ve premios activos" ON public.premios
  FOR SELECT TO authenticated USING (activo = true);
DROP POLICY IF EXISTS "Super admin ve todos los premios" ON public.premios;
CREATE POLICY "Super admin ve todos los premios" ON public.premios
  FOR SELECT TO authenticated USING (private.tiene_rol(ARRAY['super_admin']));

-- ============================================================
-- 2) BUCKET público 'premios' + escritura solo super_admin (lectura = URL pública)
-- ============================================================
INSERT INTO storage.buckets (id, name, public) VALUES ('premios','premios', true)
ON CONFLICT (id) DO NOTHING;

-- Escritura (subir/editar/borrar imágenes) solo super_admin. La LECTURA es por URL pública (bucket public=true).
DROP POLICY IF EXISTS "premios_admin_write" ON storage.objects;
CREATE POLICY "premios_admin_write" ON storage.objects
  FOR ALL TO authenticated
  USING      (bucket_id = 'premios' AND private.tiene_rol(ARRAY['super_admin']))
  WITH CHECK (bucket_id = 'premios' AND private.tiene_rol(ARRAY['super_admin']));

-- ============================================================
-- 3) RPC listar_premios_disponibles() — premios del país del paciente + su saldo
-- ============================================================
CREATE OR REPLACE FUNCTION public.listar_premios_disponibles()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid   uuid;
  v_pid   bigint;
  v_pais  uuid;
  v_saldo int;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT id, pais_id INTO v_pid, v_pais FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  v_saldo := COALESCE((SELECT sum(puntos) FROM public.puntos_movimientos WHERE paciente_id = v_pid), 0);

  RETURN jsonb_build_object(
    'saldo', v_saldo,
    'premios', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'nombre', p.nombre, 'descripcion', p.descripcion,
               'costo_puntos', p.costo_puntos, 'tipo', p.tipo, 'stock', p.stock,
               'imagen_path', p.imagen_path
             ) ORDER BY p.costo_puntos)
      FROM public.premios p
      WHERE p.activo = true AND p.stock > 0 AND p.pais_id = v_pais  -- v_pais NULL ⇒ sin match ⇒ []
    ), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL     ON FUNCTION public.listar_premios_disponibles() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.listar_premios_disponibles() TO authenticated;

-- ============================================================
-- 4) RPC saldo_puntos_paciente() — saldo del paciente logueado
-- ============================================================
CREATE OR REPLACE FUNCTION public.saldo_puntos_paciente()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid; v_pid bigint; v_saldo int;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  SELECT id INTO v_pid FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  v_saldo := COALESCE((SELECT sum(puntos) FROM public.puntos_movimientos WHERE paciente_id = v_pid), 0);
  RETURN jsonb_build_object('saldo', v_saldo);
END;
$function$;

REVOKE ALL     ON FUNCTION public.saldo_puntos_paciente() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.saldo_puntos_paciente() TO authenticated;
