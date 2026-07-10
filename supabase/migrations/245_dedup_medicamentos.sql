-- 245: (s)+(t) deduplicacion del catalogo de medicamentos
-- Fantasmas = activo IS NULL (ids 1-20). Solo existen en la prod actual.
-- DRIFT: 001_inicial.sql:154 declara activo NOT NULL DEFAULT true, pero prod
-- lo tiene nullable sin default. Una base limpia da 0 fantasmas: eso es valido.
-- Verificado en prod 10 jul:
--   0 receta_items apuntan a ellos
--   0 FKs referencian public.medicamentos
--   dispensaciones.medicamentos_dispensados usa item_id, no medicamento_id
--   farmacia_medicamentos NO tiene columna medicamento_id
-- Backup de las 20 filas en /c/dev/_meds_fantasmas_backup.txt
BEGIN;

DO $$
DECLARE
  v_fantasmas int;
  v_usados    int;
  v_huerfanos int;
BEGIN
  SELECT count(*) INTO v_fantasmas
    FROM public.medicamentos WHERE activo IS NULL;
  IF v_fantasmas NOT IN (0, 20) THEN
    RAISE EXCEPTION 'MIG245-A: se esperaban 0 (base limpia) o 20 (prod), hay %', v_fantasmas;
  END IF;

  SELECT count(*) INTO v_usados
    FROM public.receta_items ri
    JOIN public.medicamentos m ON m.id = ri.medicamento_id
   WHERE m.activo IS NULL;
  IF v_usados <> 0 THEN
    RAISE EXCEPTION 'MIG245-B: % receta_items apuntan a fantasmas', v_usados;
  END IF;

  SELECT count(*) INTO v_huerfanos
    FROM public.medicamentos g
   WHERE g.activo IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.medicamentos v
        WHERE v.activo IS TRUE
          AND lower(btrim(v.nombre_generico, E' \t\r\n'))
            = lower(btrim(g.nombre_generico, E' \t\r\n'))
          AND lower(btrim(coalesce(v.concentracion,''), E' \t\r\n'))
            = lower(btrim(coalesce(g.concentracion,''), E' \t\r\n'))
          AND lower(btrim(coalesce(v.presentacion,''), E' \t\r\n'))
            = lower(btrim(coalesce(g.presentacion,''), E' \t\r\n'))
     );
  IF v_huerfanos <> 0 THEN
    RAISE EXCEPTION 'MIG245-C: % fantasmas sin gemelo vivo, borrarlos perderia el farmaco', v_huerfanos;
  END IF;
END $$;

DELETE FROM public.medicamentos WHERE activo IS NULL;

ALTER TABLE public.medicamentos ALTER COLUMN activo SET DEFAULT true;
ALTER TABLE public.medicamentos ALTER COLUMN activo SET NOT NULL;

CREATE UNIQUE INDEX uq_medicamentos_identidad
  ON public.medicamentos (
    lower(btrim(nombre_generico, E' \t\r\n')),
    lower(btrim(coalesce(concentracion,''), E' \t\r\n')),
    lower(btrim(coalesce(presentacion,''), E' \t\r\n'))
  );

ALTER TABLE public.medicamentos
  ADD CONSTRAINT chk_medicamentos_sin_whitespace CHECK (
        nombre_generico = btrim(nombre_generico, E' \t\r\n')
    AND coalesce(nombre_comercial,'') = btrim(coalesce(nombre_comercial,''), E' \t\r\n')
    AND coalesce(presentacion,'')     = btrim(coalesce(presentacion,''), E' \t\r\n')
    AND coalesce(concentracion,'')    = btrim(coalesce(concentracion,''), E' \t\r\n')
  );

COMMIT;
