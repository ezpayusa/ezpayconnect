-- ============================================================
-- O1 (RPC) · emitir_receta atomico. DORMANT hasta que el flag se prenda.
-- Ref: DISENO-REGULATORIO.md §B8 + las 4 correcciones acordadas (2026-07-10).
--
-- CORRECCIONES AL DOC (verificadas en prod):
--  (1) §B8 decia "recetas_avanzadas NO se toca aqui". FALSO: sin la fila, la receta
--      no es despachable en ninguna farmacia. Se crea en la MISMA transaccion.
--  (2) emitida_at: momento real de emision (created_at de la fila mentia).
--  (4) el bump del doc (UPDATE + IF NOT FOUND THEN INSERT) revienta con duplicate key
--      en dos emisiones concurrentes del PRIMER correlativo de un medico.
--      Se usa INSERT ... ON CONFLICT DO UPDATE ... RETURNING: una sentencia, toma el lock.
--
-- ROLLBACK TOTAL en cualquier fallo → el correlativo NO se consume (gapless).
-- notificar_receta queda FUERA (best-effort, la llama el front despues del OK).
-- trg_historial_receta dispara dentro del INSERT a recetas (sin cambios).
-- ============================================================

CREATE OR REPLACE FUNCTION public.emitir_receta(
  p_paciente_id             bigint,
  p_instrucciones_generales text,
  p_items                   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid        uuid;
  v_num        bigint;
  v_receta_id  bigint;
  v_pais_id    uuid;
  v_nombre     text;
  v_cedula     text;
  v_n_items    int;
  v_item       jsonb;
  v_med_id     bigint;
  v_categoria  text;
  v_acuse      text;
  v_regulado   boolean;
BEGIN
  -- ===== (1) GATE. Antes de consumir numero. Fallo aqui => nada se toca. =====
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autorizado: inicia sesion' USING ERRCODE = 'PR001';
  END IF;

  IF NOT COALESCE(private.tiene_rol(ARRAY['medico']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo un medico puede emitir recetas' USING ERRCODE = 'PR002';
  END IF;

  IF p_paciente_id IS NULL THEN
    RAISE EXCEPTION 'Paciente requerido' USING ERRCODE = 'PR003';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.pacientes WHERE id = p_paciente_id) THEN
    RAISE EXCEPTION 'Paciente no encontrado' USING ERRCODE = 'PR003';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Items debe ser un arreglo' USING ERRCODE = 'PR004';
  END IF;

  v_n_items := jsonb_array_length(p_items);
  IF v_n_items = 0 THEN
    RAISE EXCEPTION 'La receta debe tener al menos un medicamento' USING ERRCODE = 'PR004';
  END IF;

  -- ===== (2) VALIDACION POR ITEM. medicamento_id OBLIGATORIO + acuse de regulados. =====
  -- Fail-safe: categoria NULL = sin_clasificar = NO regulado => no exige acuse (decision A1).
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_med_id := NULLIF(v_item->>'medicamento_id', '')::bigint;

    IF v_med_id IS NULL THEN
      RAISE EXCEPTION 'Todo medicamento debe venir del catalogo (medicamento_id ausente en "%")',
        COALESCE(v_item->>'nombre_medicamento', '?') USING ERRCODE = 'PR005';
    END IF;

    SELECT m.categoria_regulatoria INTO v_categoria
      FROM public.medicamentos m WHERE m.id = v_med_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Medicamento % no existe en el catalogo', v_med_id USING ERRCODE = 'PR005';
    END IF;

    IF COALESCE(NULLIF(trim(v_item->>'dosis'), ''), '') = '' THEN
      RAISE EXCEPTION 'Dosis requerida en "%"', COALESCE(v_item->>'nombre_medicamento','?') USING ERRCODE = 'PR006';
    END IF;

    IF COALESCE(NULLIF(trim(v_item->>'frecuencia'), ''), '') = '' THEN
      RAISE EXCEPTION 'Frecuencia requerida en "%"', COALESCE(v_item->>'nombre_medicamento','?') USING ERRCODE = 'PR006';
    END IF;

    v_regulado := v_categoria IN ('psicotropico','estupefaciente','recetario_especial');
    v_acuse    := NULLIF(trim(COALESCE(v_item->>'acuse_iniciales','')), '');

    IF COALESCE(v_regulado, false) AND v_acuse IS NULL THEN
      RAISE EXCEPTION 'El medicamento "%" es % y requiere el acuse (iniciales) del medico',
        COALESCE(v_item->>'nombre_medicamento','?'), v_categoria USING ERRCODE = 'PR007';
    END IF;
  END LOOP;

  -- ===== (3) DATOS DEL MEDICO. pais_id server-side: no se confia en el cliente. =====
  SELECT COALESCE(pf.nombre_completo, pf.nombre), pf.pais_id
    INTO v_nombre, v_pais_id
    FROM public.perfiles pf WHERE pf.id = v_uid;

  SELECT md.cedula_profesional INTO v_cedula
    FROM public.medicos md WHERE md.id = v_uid;

  -- Decision (C): la cedula NO bloquea la emision. El folio se compone al LEER
  -- y se auto-repara cuando se cargue. El gate va en el alta del medico.
  IF v_cedula IS NULL THEN
    RAISE WARNING 'emitir_receta: medico % sin cedula_profesional (folio degradado)', v_uid;
  END IF;

  -- ===== (4) BUMP GAPLESS. Una sentencia. Toma el lock de fila y resuelve el alta. =====
  INSERT INTO public.medico_correlativos (medico_id, ultimo_numero)
  VALUES (v_uid, 1)
  ON CONFLICT (medico_id) DO UPDATE
    SET ultimo_numero = public.medico_correlativos.ultimo_numero + 1,
        updated_at    = now()
  RETURNING ultimo_numero INTO v_num;

  -- ===== (5) INSERT recetas. Dispara trg_historial_receta. =====
  INSERT INTO public.recetas (paciente_id, instrucciones_generales, medico_id, estado, pais_id, numero_correlativo)
  VALUES (p_paciente_id, NULLIF(trim(COALESCE(p_instrucciones_generales,'')), ''), v_uid, 'activa', v_pais_id, v_num)
  RETURNING id INTO v_receta_id;

  -- ===== (6) INSERT receta_items + acuse persistido (b1). =====
  INSERT INTO public.receta_items
    (receta_id, medicamento_id, nombre_medicamento, dosis, frecuencia, duracion,
     instrucciones, cantidad, farmacia_id, precio_unitario, stock_actual,
     acuse_iniciales, acuse_at, acuse_categoria)
  SELECT
    v_receta_id,
    (it->>'medicamento_id')::bigint,
    it->>'nombre_medicamento',
    it->>'dosis',
    it->>'frecuencia',
    NULLIF(it->>'duracion',''),
    NULLIF(it->>'instrucciones',''),
    COALESCE(NULLIF(it->>'cantidad','')::int, 1),
    NULLIF(it->>'farmacia_id','')::int,
    NULLIF(it->>'precio_unitario','')::numeric,
    NULLIF(it->>'stock_actual','')::int,
    NULLIF(trim(COALESCE(it->>'acuse_iniciales','')), ''),
    CASE WHEN NULLIF(trim(COALESCE(it->>'acuse_iniciales','')), '') IS NOT NULL THEN now() END,
    (SELECT m.categoria_regulatoria FROM public.medicamentos m WHERE m.id = (it->>'medicamento_id')::bigint)
  FROM jsonb_array_elements(p_items) it;

  -- ===== (7) CORRECCION (1): la fila despachable nace ACA, no en un boton escondido. =====
  -- dispatch_token y dispatch_token_expira_at salen de sus DEFAULT de columna.
  -- La edge ya no firma: su upsert tiene ignoreDuplicates y quedaria en no-op.
  INSERT INTO public.recetas_avanzadas
    (receta_base_id, paciente_id, medico_id, firma_digital, estado_dispensacion, emitida_at)
  VALUES
    (v_receta_id, p_paciente_id::text, v_uid::text,
     'FIRMADO-' || COALESCE(v_nombre, 'Medico') || '-' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
     'pendiente', now());

  RETURN jsonb_build_object(
    'receta_id',          v_receta_id,
    'numero_correlativo', v_num,
    'numero_formateado',  COALESCE(v_cedula, 'SINCED') || '-' || lpad(v_num::text, 6, '0') || '-' || to_char(now(), 'YYYYMMDD')
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.emitir_receta(bigint, text, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.emitir_receta(bigint, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.emitir_receta(bigint, text, jsonb) IS
  'Emision atomica de receta: gate -> bump gapless -> recetas -> receta_items -> recetas_avanzadas. Rollback total en fallo. DORMANT hasta private.emision_flags.emitir_receta_rpc = true.';
