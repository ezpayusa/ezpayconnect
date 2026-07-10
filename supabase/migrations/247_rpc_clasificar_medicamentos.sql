-- 247: O2b. RPC de clasificacion regulatoria. Lote atomico.
-- Gate super_admin DENTRO del cuerpo: la RPC es DEFINER, corre como postgres,
-- la policy medicamentos_write_admin NO la evalua.
-- Errores PCnnn: los lee un super_admin, no un medico (PR = contrato del medico).
BEGIN;

CREATE OR REPLACE FUNCTION public.clasificar_medicamentos(
  p_items  jsonb,
  p_motivo text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_actor   uuid := auth.uid();
  v_rol     text;
  v_item    jsonb;
  v_med_id  bigint;
  v_cat_new text;
  v_cat_old text;
  v_n       int := 0;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'PC001: sesion no autenticada' USING ERRCODE = 'PC001';
  END IF;

  SELECT private.rol_usuario() INTO v_rol;
  IF NOT private.tiene_rol(ARRAY['super_admin']) THEN
    RAISE EXCEPTION 'PC002: solo super_admin puede clasificar medicamentos' USING ERRCODE = 'PC002';
  END IF;

  IF p_motivo IS NULL OR btrim(p_motivo, E' \t\r\n') = '' THEN
    RAISE EXCEPTION 'PC003: el motivo es obligatorio' USING ERRCODE = 'PC003';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'PC004: p_items debe ser un array no vacio' USING ERRCODE = 'PC004';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_med_id  := (v_item ->> 'medicamento_id')::bigint;
    v_cat_new := v_item ->> 'categoria';

    IF v_med_id IS NULL THEN
      RAISE EXCEPTION 'PC005: medicamento_id ausente en un item' USING ERRCODE = 'PC005';
    END IF;

    IF v_cat_new IS NULL OR btrim(v_cat_new, E' \t\r\n') = '' THEN
      RAISE EXCEPTION 'PC006: no se puede desclasificar (categoria NULL) el medicamento %', v_med_id
        USING ERRCODE = 'PC006';
    END IF;

    SELECT m.categoria_regulatoria INTO v_cat_old
      FROM public.medicamentos m WHERE m.id = v_med_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'PC007: medicamento % no existe', v_med_id USING ERRCODE = 'PC007';
    END IF;

    UPDATE public.medicamentos
       SET categoria_regulatoria = v_cat_new
     WHERE id = v_med_id;

    INSERT INTO public.medicamentos_clasificacion_log
      (medicamento_id, categoria_antes, categoria_despues, motivo, actor_id, actor_rol)
    VALUES
      (v_med_id, v_cat_old, v_cat_new, btrim(p_motivo, E' \t\r\n'), v_actor, v_rol);

    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('clasificados', v_n);
END;
$fn$;

REVOKE ALL ON FUNCTION public.clasificar_medicamentos(jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clasificar_medicamentos(jsonb, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.clasificar_medicamentos(jsonb, text) TO authenticated;

COMMIT;
