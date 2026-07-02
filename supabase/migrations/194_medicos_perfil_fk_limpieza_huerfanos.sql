-- 194 Invariante medicos.id = perfiles.id — borrar 3 médicos-catálogo huérfanos (fixtures 2026-05-22) + FK
-- TODO en un bloque atómico (DO): si cualquier paso falla o una guarda defensiva no se cumple,
-- se revierte TODO (no queremos ni fixtures borrados sin FK, ni FK sin limpiar).
-- Los 3 ids no tienen perfil, no son doctor_id de ninguna clínica (verificado antes; y se re-verifica acá).

DO $$
DECLARE
  v_ids uuid[] := ARRAY[
    '44012d1e-fc08-46b6-83c2-246a1e755e02',  -- Dr. Juan Pérez
    '8161d065-760a-4e35-946d-902e53499bf5',  -- Dr. Carlos Ramírez
    '8c593e7d-09b5-4172-bfb4-c08a19319b83'   -- Dra. María González
  ]::uuid[];
  v_exist int; v_conperfil int; v_esdueno int;
  v_c_citas int; v_c_mc int; v_c_ep int;
  v_del_citas int; v_del_ep int; v_del_mc int; v_del_med int;
  v_total int; v_huerfanos int;
BEGIN
  -- ===== PASO 0: re-verificación defensiva =====
  SELECT count(*) INTO v_exist FROM public.medicos WHERE id = ANY(v_ids);
  IF v_exist <> 3 THEN
    RAISE EXCEPTION 'ABORT: se esperaban 3 médicos huérfanos, existen % — algo cambió', v_exist;
  END IF;

  SELECT count(*) INTO v_conperfil FROM public.perfiles WHERE id = ANY(v_ids);
  IF v_conperfil <> 0 THEN
    RAISE EXCEPTION 'ABORT: % de los 3 ids YA tienen perfil — revisar a mano', v_conperfil;
  END IF;

  SELECT count(*) INTO v_esdueno FROM public.clinicas WHERE doctor_id = ANY(v_ids);
  IF v_esdueno <> 0 THEN
    RAISE EXCEPTION 'ABORT: % de los 3 son doctor_id de alguna clínica — no dejar clínica sin dueño', v_esdueno;
  END IF;

  SELECT count(*) INTO v_c_citas FROM public.citas                    WHERE medico_id = ANY(v_ids);
  SELECT count(*) INTO v_c_mc    FROM public.medico_clinicas          WHERE medico_id = ANY(v_ids);
  SELECT count(*) INTO v_c_ep    FROM public.especialidades_propuestas WHERE medico_id = ANY(v_ids);
  RAISE NOTICE 'PASO0 dependencias: citas=% medico_clinicas=% especialidades_propuestas=%', v_c_citas, v_c_mc, v_c_ep;

  -- ===== PASO 1: borrado hijos primero, solo para esos 3 ids =====
  DELETE FROM public.citas                     WHERE medico_id = ANY(v_ids); GET DIAGNOSTICS v_del_citas = ROW_COUNT;
  DELETE FROM public.especialidades_propuestas WHERE medico_id = ANY(v_ids); GET DIAGNOSTICS v_del_ep    = ROW_COUNT;
  DELETE FROM public.medico_clinicas           WHERE medico_id = ANY(v_ids); GET DIAGNOSTICS v_del_mc    = ROW_COUNT;
  DELETE FROM public.medicos                   WHERE id        = ANY(v_ids); GET DIAGNOSTICS v_del_med   = ROW_COUNT;
  RAISE NOTICE 'PASO1 borrados: citas=% especialidades_propuestas=% medico_clinicas=% medicos=%',
    v_del_citas, v_del_ep, v_del_mc, v_del_med;

  -- ===== PASO 2: validar estado post-borrado =====
  SELECT count(*) INTO v_total FROM public.medicos;
  IF v_total <> 8 THEN
    RAISE EXCEPTION 'ABORT: medicos quedó en % (esperado 8)', v_total;
  END IF;
  SELECT count(*) INTO v_huerfanos
  FROM public.medicos m WHERE NOT EXISTS (SELECT 1 FROM public.perfiles p WHERE p.id = m.id);
  IF v_huerfanos <> 0 THEN
    RAISE EXCEPTION 'ABORT: quedan % medicos sin perfil — la FK fallaría', v_huerfanos;
  END IF;

  -- ===== PASO 3: FK que hace cumplir la invariante hacia adelante =====
  EXECUTE 'ALTER TABLE public.medicos
             ADD CONSTRAINT medicos_id_perfiles_fkey
             FOREIGN KEY (id) REFERENCES public.perfiles(id) ON DELETE CASCADE';

  RAISE NOTICE 'OK: medicos=% · FK medicos_id_perfiles_fkey (ON DELETE CASCADE) creada', v_total;
END $$;
