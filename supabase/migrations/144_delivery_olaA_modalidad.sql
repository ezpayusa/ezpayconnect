-- ============================================================
-- 144 · DELIVERY Fase 1 — OLA A: modalidad pickup/delivery (backend puro, INERTE)
-- ------------------------------------------------------------
-- Alcance EXACTO (nada fuera de esto): (1) receta_items.modalidad (default pickup, no-regresivo);
-- (2) trigger de uniformidad por (receta_id, farmacia_id); (3) RPC fijar_modalidad_grupo.
-- NO crea la tabla entregas ni columnas de Ola B/C. NO toca front. NO toca 141/143 ni ruteo 3.3.
-- Inerte: con default pickup y 0 escrituras de modalidad, nada lee la columna (el auto-create es Ola C) →
-- el sistema se comporta idéntico a hoy. Idempotente.
-- ============================================================

-- 1) Columna modalidad ------------------------------------------------------
ALTER TABLE public.receta_items
  ADD COLUMN IF NOT EXISTS modalidad text NOT NULL DEFAULT 'pickup';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.receta_items'::regclass AND conname='chk_receta_items_modalidad') THEN
    ALTER TABLE public.receta_items
      ADD CONSTRAINT chk_receta_items_modalidad CHECK (modalidad IN ('pickup','delivery'));
  END IF;
END $$;

-- 2) Trigger de uniformidad por (receta_id, farmacia_id) ---------------------
--    Todos los ítems de un mismo (receta, farmacia) comparten modalidad. farmacia_id NULL → no aplica
--    (el '=' con NULL no matchea) → el insert directo actual (ítems pickup + farmacia_id null) es no-op.
CREATE OR REPLACE FUNCTION private.receta_items_modalidad_uniforme()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.receta_items x
    WHERE x.receta_id = NEW.receta_id
      AND x.farmacia_id = NEW.farmacia_id          -- NULL = NULL → NULL (no matchea): ítems sin rutear no disparan
      AND x.id <> NEW.id
      AND x.modalidad <> NEW.modalidad
  ) THEN
    RAISE EXCEPTION 'modalidad no uniforme en (receta %, farmacia %)', NEW.receta_id, NEW.farmacia_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_modalidad_uniforme ON public.receta_items;
CREATE TRIGGER trg_modalidad_uniforme
  BEFORE INSERT OR UPDATE OF modalidad, farmacia_id ON public.receta_items
  FOR EACH ROW EXECUTE FUNCTION private.receta_items_modalidad_uniforme();

-- 3) RPC fijar_modalidad_grupo (DEFINER sp'') -------------------------------
--    Único punto de cambio de modalidad para AMBOS paths (médico al rutear / paciente en WebAppRecetas).
--    Gate: médico de la receta OR paciente dueño (paciente_es_mio sobre recetas.paciente_id bigint).
--    Freeze server-side: RAISE si existe >=1 dispensación (dispensado=true) del grupo. Última-escritura-gana
--    solo mientras NO congelado. Escribe TODO el grupo (uniformidad por construcción; el trigger es backstop).
CREATE OR REPLACE FUNCTION public.fijar_modalidad_grupo(
  p_receta_id bigint, p_farmacia_id integer, p_modalidad text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_es_medico boolean; v_es_paciente boolean; v_n integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado: inicia sesión'; END IF;
  IF p_modalidad NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Modalidad inválida'; END IF;

  SELECT EXISTS (SELECT 1 FROM public.recetas r WHERE r.id = p_receta_id AND r.medico_id = v_uid)
    INTO v_es_medico;
  SELECT EXISTS (SELECT 1 FROM public.recetas r
                 WHERE r.id = p_receta_id AND COALESCE(private.paciente_es_mio(r.paciente_id), false))
    INTO v_es_paciente;
  IF NOT (v_es_medico OR v_es_paciente) THEN
    RAISE EXCEPTION 'No autorizado para esta receta';
  END IF;

  -- freeze: editable solo hasta que la sucursal despache el grupo (gate ANTES del efecto)
  IF EXISTS (SELECT 1 FROM public.receta_items
             WHERE receta_id = p_receta_id AND farmacia_id = p_farmacia_id AND dispensado = true) THEN
    RAISE EXCEPTION 'Modalidad congelada: la sucursal ya despachó este grupo';
  END IF;

  UPDATE public.receta_items SET modalidad = p_modalidad
    WHERE receta_id = p_receta_id AND farmacia_id = p_farmacia_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('receta_id', p_receta_id, 'farmacia_id', p_farmacia_id,
                            'modalidad', p_modalidad, 'items', v_n);
END $$;
REVOKE EXECUTE ON FUNCTION public.fijar_modalidad_grupo(bigint, integer, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fijar_modalidad_grupo(bigint, integer, text) TO authenticated;
