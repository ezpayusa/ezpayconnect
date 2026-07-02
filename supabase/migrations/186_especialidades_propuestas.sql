-- 186 Trabajo B Parte 1 — cola de aprobación de especialidades propuestas por médicos
-- El médico propone un nombre de especialidad (queda 'pendiente', NO recibe especialidad_id).
-- super_admin aprueba (crea/reusa la especialidad + setea medicos.especialidad_id + marca la propuesta)
-- o rechaza (solo marca). Escritura SOLO por RPC DEFINER (patrón canjes mig 179).
-- Identidad de médico = medicos.id = auth.uid() (patrón del proyecto). Gate super_admin = private.tiene_rol.

-- ============================================================
-- 1) TABLA especialidades_propuestas
-- ============================================================
CREATE TABLE IF NOT EXISTS public.especialidades_propuestas (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  medico_id        uuid NOT NULL REFERENCES public.medicos(id),          -- quién propone
  nombre_propuesto text NOT NULL,                                        -- lo que escribió el médico
  estado           text NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','aprobada','rechazada')),
  especialidad_id  uuid REFERENCES public.especialidades(id),           -- NULL hasta aprobar; fila creada/reusada al aprobar
  created_at       timestamptz NOT NULL DEFAULT now(),
  resolved_at      timestamptz,                                         -- NULL hasta resolver
  resolved_by      uuid                                                 -- super_admin que resolvió; NULL hasta resolver
);

-- Escritura SOLO por RPC DEFINER (proponer / resolver). Nada de INSERT/UPDATE/DELETE directo.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.especialidades_propuestas FROM authenticated;
REVOKE ALL ON public.especialidades_propuestas FROM anon;

ALTER TABLE public.especialidades_propuestas ENABLE ROW LEVEL SECURITY;

-- Lectura: el médico ve SOLO las suyas (medico_id = auth.uid(), patrón del proyecto).
DROP POLICY IF EXISTS "Medico ve sus propuestas" ON public.especialidades_propuestas;
CREATE POLICY "Medico ve sus propuestas" ON public.especialidades_propuestas
  FOR SELECT TO authenticated USING (medico_id = auth.uid());

-- Lectura: super_admin ve todas (para el panel de aprobación).
DROP POLICY IF EXISTS "Super admin ve propuestas" ON public.especialidades_propuestas;
CREATE POLICY "Super admin ve propuestas" ON public.especialidades_propuestas
  FOR SELECT TO authenticated USING (private.tiene_rol(ARRAY['super_admin']));

-- (No hay policies de INSERT/UPDATE: la escritura va exclusivamente por las RPC DEFINER de abajo,
--  que corren como owner y omiten RLS. La resolución NO se hace por UPDATE directo.)

-- ============================================================
-- 2) RPC proponer_especialidad(p_nombre) — la llama el médico
-- ============================================================
CREATE OR REPLACE FUNCTION public.proponer_especialidad(p_nombre text)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_id  uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.medicos WHERE id = v_uid) THEN
    RAISE EXCEPTION 'no_es_medico';
  END IF;
  IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
    RAISE EXCEPTION 'nombre_vacio';
  END IF;

  -- NO toca medicos.especialidad_id: el médico queda con especialidad_id NULL hasta que aprueben.
  INSERT INTO public.especialidades_propuestas (medico_id, nombre_propuesto, estado)
  VALUES (v_uid, btrim(p_nombre), 'pendiente')
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL     ON FUNCTION public.proponer_especialidad(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.proponer_especialidad(text) TO authenticated;

-- ============================================================
-- 3) RPC resolver_propuesta_especialidad(p_propuesta_id, p_aprobar) — SOLO super_admin
--    Aprobación atómica (todo o nada): crear/reusar especialidad + setear médico + marcar propuesta.
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolver_propuesta_especialidad(p_propuesta_id uuid, p_aprobar boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_prop   RECORD;
  v_esp_id uuid;
BEGIN
  -- Gate exacto de super_admin (mismo chequeo que resolver_canje).
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  -- LOCK + anti doble-resolución.
  SELECT id, medico_id, nombre_propuesto, estado
  INTO v_prop
  FROM public.especialidades_propuestas
  WHERE id = p_propuesta_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'propuesta_inexistente'; END IF;
  IF v_prop.estado <> 'pendiente' THEN RAISE EXCEPTION 'propuesta_ya_resuelta'; END IF;

  IF p_aprobar THEN
    -- a) crear especialidad, o REUSAR la existente por nombre exacto (UNIQUE) sin fallar.
    --    ON CONFLICT DO UPDATE (self no-op) permite RETURNING id tanto en insert nuevo como en reuso, y es race-safe.
    INSERT INTO public.especialidades (nombre, activo)
    VALUES (v_prop.nombre_propuesto, true)
    ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
    RETURNING id INTO v_esp_id;

    -- b) setear la especialidad del médico proponente.
    UPDATE public.medicos SET especialidad_id = v_esp_id WHERE id = v_prop.medico_id;

    -- c) marcar la propuesta como aprobada (referencia la especialidad usada).
    UPDATE public.especialidades_propuestas
    SET estado = 'aprobada', especialidad_id = v_esp_id, resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'aprobada', 'especialidad_id', v_esp_id);
  ELSE
    -- Rechazo: NO tocar medicos ni especialidades, solo marcar.
    UPDATE public.especialidades_propuestas
    SET estado = 'rechazada', resolved_at = now(), resolved_by = auth.uid()
    WHERE id = p_propuesta_id;

    RETURN jsonb_build_object('ok', true, 'estado', 'rechazada');
  END IF;
  -- Si cualquier paso de la aprobación falla, la excepción revierte TODA la transacción de la función.
END;
$function$;

REVOKE ALL     ON FUNCTION public.resolver_propuesta_especialidad(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.resolver_propuesta_especialidad(uuid, boolean) TO authenticated;  -- gate interno = super_admin
