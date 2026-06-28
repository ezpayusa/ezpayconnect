-- 168 · Foto de perfil del paciente (PHI). Bucket PRIVADO (calcado de comprobantes/resultados-examenes;
-- NUNCA público). La columna guarda el PATH del objeto (no URL pública); la lectura va por signed URL.
-- Escritura del path por RPC DEFINER (calcado de capturar_signo_vital): gate rol + pertenencia.
-- Path canónico FIJO = {clinica_id}/{paciente_id}/perfil.jpg (extensión .jpg fija, NO <ext>): el front
-- SIEMPRE comprime a image/jpeg (comprimirImagen, q0.8) y sube con upsert:true → el reemplazo PISA el mismo
-- objeto (path estable) → no se acumulan objetos ni hace falta policy DELETE. Precedente: el bucket privado
-- 'comprobantes' usa upsert:true (usePagosProveedor.ts:67) con solo _insert/_select/_update y SIN _delete —
-- upsert sobre objeto existente ejerce UPDATE (no DELETE+INSERT), así que _update basta.
-- El gate confina por el 1er segmento (clinica_id) contra private.clinicas_del_usuario() (mig 166, RETURNS
-- SETOF uuid), comparado como TEXT para que un 1er segmento malformado deniegue limpio (castear a uuid abortaría).

-- ============================================================
-- 1) Columna foto_path (path en bucket privado; NO url pública). Nullable.
-- ============================================================
ALTER TABLE public.pacientes ADD COLUMN IF NOT EXISTS foto_path text;

-- ============================================================
-- 2) Bucket privado.
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('pacientes-fotos', 'pacientes-fotos', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 3) Policies de storage.objects para 'pacientes-fotos'.
--    Confinamiento por clínica: 1er segmento del path ∈ clínicas del caller.
--    INSERT/UPDATE: además rol de captura (medico/asistente_medico) o super_admin.
--    SELECT: cualquier miembro de la clínica (coherente con que ya ven nombre/datos del paciente) o super_admin.
-- ============================================================
DROP POLICY IF EXISTS pacientes_fotos_insert ON storage.objects;
CREATE POLICY pacientes_fotos_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'pacientes-fotos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

DROP POLICY IF EXISTS pacientes_fotos_update ON storage.objects;
CREATE POLICY pacientes_fotos_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'pacientes-fotos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  )
  WITH CHECK (
    bucket_id = 'pacientes-fotos' AND (
      ( split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
        AND private.tiene_rol(ARRAY['medico','asistente_medico']) )
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

DROP POLICY IF EXISTS pacientes_fotos_select ON storage.objects;
CREATE POLICY pacientes_fotos_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'pacientes-fotos' AND (
      split_part(name, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)
      OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
    )
  );

-- ============================================================
-- 4) RPC para escribir foto_path tras la subida (DEFINER, gate rol + pertenencia).
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_foto_paciente(p_paciente_id bigint, p_path text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_id  bigint;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;

  -- Gate fail-closed: rol de captura + pertenencia del paciente (paciente_en_clinica_de toma integer).
  IF NOT (
       private.tiene_rol(ARRAY['medico','asistente_medico'])
   AND private.paciente_en_clinica_de(p_paciente_id::integer)
  ) THEN
    RAISE EXCEPTION 'No autorizado: rol o pertenencia';
  END IF;

  IF p_path IS NULL OR length(trim(p_path)) = 0 THEN
    RAISE EXCEPTION 'Path vacío';
  END IF;

  -- Defensivo: el 1er segmento del path (clinica_id) debe ser una clínica del caller (evita asociar
  -- un path de otra clínica aunque la subida lo gatee aparte).
  IF NOT (split_part(p_path, '/', 1) IN (SELECT cu::text FROM private.clinicas_del_usuario() cu)) THEN
    RAISE EXCEPTION 'Path fuera de tu clínica';
  END IF;

  UPDATE public.pacientes SET foto_path = p_path WHERE id = p_paciente_id
  RETURNING id INTO v_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Paciente inexistente'; END IF;

  RETURN jsonb_build_object('id', v_id, 'foto_path', p_path);
END;
$function$;
REVOKE ALL    ON FUNCTION public.set_foto_paciente(bigint, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_foto_paciente(bigint, text) TO authenticated;

-- NO se tocan policies/grants existentes de public.pacientes ni los grants de tabla (deuda del REVOKE
-- masivo anon/authenticated, anotada; fuera de alcance de esta migración).
