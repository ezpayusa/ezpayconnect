-- 176 Ola 3 backend "invitar amigo" — atribución segura en el PRIMER LOGIN del amigo (opción A).
-- Reemplaza la firma insegura registrar_referido_atribucion(text,bigint) [param-based, sin exponer en 175]
-- por registrar_mi_referido(text) que DERIVA el paciente del auth.uid() del propio amigo (no falsificable).
--
-- Robustez: best-effort en el login del amigo. Solo 'no_auth' hace RAISE; codigo_invalido/auto_referido
-- se DEVUELVEN como { ok:false, motivo } (no rompen el login). Éxito → { ok:true, estado }.

CREATE OR REPLACE FUNCTION public.registrar_mi_referido(_codigo text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid       uuid;
  v_mi_pid    bigint;
  v_referidor bigint;
  v_inserted  bigint;
BEGIN
  -- Identidad del AMIGO derivada del JWT (NUNCA por parámetro).
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  SELECT id INTO v_mi_pid FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_mi_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;  -- el caller no es un paciente

  -- Código → referidor. best-effort: no rompe el login del amigo.
  SELECT referidor_paciente_id INTO v_referidor
  FROM public.referidos_paciente WHERE codigo = _codigo;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'codigo_invalido');
  END IF;

  -- Anti auto-referido (no rompe).
  IF v_referidor = v_mi_pid THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'auto_referido');
  END IF;

  -- Idempotente: el UNIQUE en referido_nuevo_paciente_id bloquea doble atribución.
  INSERT INTO public.referidos_atribucion (codigo, referido_nuevo_paciente_id)
  VALUES (_codigo, v_mi_pid)
  ON CONFLICT (referido_nuevo_paciente_id) DO NOTHING
  RETURNING id INTO v_inserted;

  IF v_inserted IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'estado', 'ya_atribuido');
  END IF;
  RETURN jsonb_build_object('ok', true, 'estado', 'registrado');
END;
$function$;

-- Ahora SÍ se expone: es seguro porque deriva el paciente de auth.uid().
REVOKE ALL     ON FUNCTION public.registrar_mi_referido(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_mi_referido(text) TO authenticated;

-- La firma vieja insegura (param-based) no tiene consumidores (recon: solo aparecía en mig 175) → DROP.
DROP FUNCTION IF EXISTS public.registrar_referido_atribucion(text, bigint);
