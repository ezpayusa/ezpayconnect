-- ============================================================
-- 145 · DELIVERY Ola A — FIX del trigger de uniformidad (ROW-level → STATEMENT-level) + CHECK delivery⇒sucursal
-- ------------------------------------------------------------
-- DEFECTO detectado por el smoke de 144: el trigger era FOR EACH ROW → el UPDATE de grupo de
-- fijar_modalidad_grupo (`SET modalidad=... WHERE receta_id AND farmacia_id`) se AUTO-rechazaba a mitad de
-- statement: al actualizar la 1ª fila a 'delivery', las hermanas seguían en 'pickup' → divergencia TRANSITORIA
-- → RAISE. En la práctica nunca se podía poner delivery en un grupo de 2+ ítems.
-- FIX: trigger AFTER ... FOR EACH STATEMENT con transition table → evalúa el estado FINAL del statement
-- (sin divergencia transitoria). El UPDATE de grupo uniforme pasa; un UPDATE divergente de 1 sola fila sigue
-- siendo rechazado (count distinct modalidad > 1).
--
-- CASO #1 (re-ruteo: UPDATE de farmacia_id): NEW TABLE basta. Quitar un ítem del grupo ORIGEN no puede volverlo
--   no-uniforme (un subconjunto de un conjunto uniforme es uniforme o vacío). El único grupo que puede romperse
--   es el DESTINO, que SÍ viene en newtab (con su farmacia_id nuevo) → cubierto. No se requiere OLD TABLE.
--   Fase 1 NO tiene guard separado que prohíba re-rutear un ítem ya 'delivery'; si el re-ruteo crea un grupo
--   destino mixto, el trigger lo rechaza (fuerza consistencia). En el flujo normal el ruteo ocurre ANTES de fijar
--   modalidad, así que este es un borde.
-- CASO #2 (delivery con farmacia_id NULL): delivery exige sucursal → CHECK nuevo lo impide (un ítem no ruteado
--   no puede ser delivery). El trigger ignora grupos farmacia_id NULL (son siempre pickup por este CHECK).
-- ============================================================

-- (a) CHECK: delivery exige sucursal (farmacia_id NOT NULL) ------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.receta_items'::regclass AND conname='chk_modalidad_delivery_farmacia') THEN
    ALTER TABLE public.receta_items
      ADD CONSTRAINT chk_modalidad_delivery_farmacia
      CHECK (modalidad <> 'delivery' OR farmacia_id IS NOT NULL);
  END IF;
END $$;

-- (b) Trigger de uniformidad: STATEMENT-level (estado final), NEW TABLE ------
CREATE OR REPLACE FUNCTION private.receta_items_modalidad_uniforme()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (SELECT DISTINCT receta_id, farmacia_id FROM newtab WHERE farmacia_id IS NOT NULL) g
    JOIN public.receta_items ri ON ri.receta_id = g.receta_id AND ri.farmacia_id = g.farmacia_id
    GROUP BY g.receta_id, g.farmacia_id
    HAVING count(DISTINCT ri.modalidad) > 1          -- grupo (receta, farmacia) con modalidad mezclada
  ) THEN
    RAISE EXCEPTION 'modalidad no uniforme en grupo (receta, farmacia)';
  END IF;
  RETURN NULL;
END $$;
-- Postgres no permite transition tables en un trigger multi-evento → un trigger por evento (misma función).
DROP TRIGGER IF EXISTS trg_modalidad_uniforme     ON public.receta_items;   -- el ROW-level de 144
DROP TRIGGER IF EXISTS trg_modalidad_uniforme_ins ON public.receta_items;
DROP TRIGGER IF EXISTS trg_modalidad_uniforme_upd ON public.receta_items;
CREATE TRIGGER trg_modalidad_uniforme_ins
  AFTER INSERT ON public.receta_items
  REFERENCING NEW TABLE AS newtab
  FOR EACH STATEMENT EXECUTE FUNCTION private.receta_items_modalidad_uniforme();
-- NOTA: Postgres prohíbe `UPDATE OF col` junto con transition tables → el trigger de UPDATE NO lleva lista de
-- columnas → dispara en CUALQUIER UPDATE de receta_items (incl. dispensado en el despacho). Nunca RECHAZA grupos
-- uniformes (count distinct=1) → sin cambio de semántica del despacho; el costo es un lookup indexado por UPDATE
-- (despreciable). Solo evalúa los grupos tocados (newtab), no toda la tabla.
CREATE TRIGGER trg_modalidad_uniforme_upd
  AFTER UPDATE ON public.receta_items
  REFERENCING NEW TABLE AS newtab
  FOR EACH STATEMENT EXECUTE FUNCTION private.receta_items_modalidad_uniforme();
