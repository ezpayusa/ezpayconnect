-- 290: validacion de fecha_ingreso y celular en asesores_perfil (pendiente #8)
-- CHECK estructural para celular (no depende del reloj) + guard en la RPC para ambos campos
-- (el limite superior de fecha depende de CURRENT_DATE, por eso NO va en CHECK, igual que
-- PA026/PC012 en este proyecto).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'asesores_perfil_celular_formato'
  ) THEN
    ALTER TABLE public.asesores_perfil
      ADD CONSTRAINT asesores_perfil_celular_formato
      CHECK (celular IS NULL OR length(regexp_replace(celular, '\D', '', 'g')) BETWEEN 7 AND 15);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guardar_asesor_perfil(
  p_asesor_id uuid,
  p_codigo_asesor text,
  p_pais_id uuid,
  p_cargo text DEFAULT NULL,
  p_territorio text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_celular text DEFAULT NULL,
  p_fecha_ingreso date DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_activo boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_pais_actual uuid; v_existe boolean; v_ok_viejo boolean; v_ok_nuevo boolean; v_rol text;
BEGIN
  SELECT ap.pais_id, true INTO v_pais_actual, v_existe
    FROM public.asesores_perfil ap WHERE ap.id = p_asesor_id;

  -- LA LINEA QUE ATA, EN DOS MITADES. En un INSERT no hay fila de donde derivar el pais, asi
  -- que aca p_pais_id es inevitable — es exactamente la forma de la mig 222 que fallaba ABIERTA,
  -- y es correcta SOLO porque puede_admin_pais rechaza NULL y pais ajeno dentro del COALESCE.
  -- En un UPDATE que MUEVE la ficha hacen falta las dos autoridades: con solo la nueva, un admin
  -- se roba fichas del pais vecino; con solo la vieja, las exporta.
  v_ok_nuevo := COALESCE(private.puede_admin_pais(p_pais_id), false);
  v_ok_viejo := CASE WHEN COALESCE(v_existe, false)
                     THEN COALESCE(private.puede_admin_pais(v_pais_actual), false)
                     ELSE v_ok_nuevo END;

  IF NOT (v_ok_viejo OR v_ok_nuevo) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  IF NOT (v_ok_viejo AND v_ok_nuevo) THEN
    RAISE EXCEPTION 'PA014: mover la ficha de % del pais % al pais % exige autoridad sobre los DOS paises',
      p_asesor_id, COALESCE(v_pais_actual::text,'(nuevo)'), COALESCE(p_pais_id::text,'(nulo)')
      USING ERRCODE = 'PA014';
  END IF;

  SELECT p.rol INTO v_rol FROM public.perfiles p WHERE p.id = p_asesor_id;
  IF v_rol IS DISTINCT FROM 'asesor_comercial' AND v_rol IS DISTINCT FROM 'supervisor_comercial' THEN
    RAISE EXCEPTION 'PA009: % tiene rol % y no puede tener ficha comercial', p_asesor_id,
      COALESCE(v_rol,'(perfil inexistente)') USING ERRCODE = 'PA009';
  END IF;

  IF p_fecha_ingreso IS NOT NULL
     AND (p_fecha_ingreso < DATE '2000-01-01'
          OR p_fecha_ingreso > CURRENT_DATE + INTERVAL '1 year') THEN
    RAISE EXCEPTION 'PA033: fecha_ingreso % fuera de rango (2000-01-01 .. hoy+1a)', p_fecha_ingreso
      USING ERRCODE = 'PA033';
  END IF;

  IF p_celular IS NOT NULL
     AND length(regexp_replace(p_celular, '\D', '', 'g')) NOT BETWEEN 7 AND 15 THEN
    RAISE EXCEPTION 'PA034: celular "%" no tiene un formato valido (7 a 15 digitos)', p_celular
      USING ERRCODE = 'PA034';
  END IF;

  -- PA007 (no mover de pais una ficha con subordinados) lo pone el guard de la 264 sobre este
  -- mismo UPDATE. No se revalida.
  INSERT INTO public.asesores_perfil
    (id, codigo_asesor, pais_id, cargo, territorio, telefono, celular, fecha_ingreso, bio, activo)
  VALUES
    (p_asesor_id, btrim(p_codigo_asesor), p_pais_id, p_cargo, p_territorio, p_telefono,
     p_celular, p_fecha_ingreso, p_bio, COALESCE(p_activo, true))
  ON CONFLICT (id) DO UPDATE SET
    codigo_asesor = EXCLUDED.codigo_asesor, pais_id = EXCLUDED.pais_id, cargo = EXCLUDED.cargo,
    territorio = EXCLUDED.territorio, telefono = EXCLUDED.telefono, celular = EXCLUDED.celular,
    fecha_ingreso = EXCLUDED.fecha_ingreso, bio = EXCLUDED.bio, activo = EXCLUDED.activo,
    updated_at = now();
END
$function$;
