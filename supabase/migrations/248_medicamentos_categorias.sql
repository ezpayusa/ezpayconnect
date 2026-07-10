-- 248: catalogo de categorias regulatorias. Reemplaza el CHECK por FK.
-- POR QUE: "que es regulado" estaba como lista de strings en DOS lugares
-- (emitir_receta y src/lib/regulados.ts). Tocar uno solo y no el otro rompe
-- en silencio: el front no muestra el acuse y el server rechaza con PR007.
-- Mismo patron que perfiles.rol -> roles_catalogo(codigo).
--
-- 'recetario_especial' NO era una clase de sustancia, era un requisito de
-- proceso. Un psicotropico ES psicotropico Y ADEMAS lleva recetario especial.
-- Pasa a ser columna booleana. Quedan 4 categorias.
BEGIN;

CREATE TABLE public.medicamentos_categorias (
  codigo                      text PRIMARY KEY,
  etiqueta                    text NOT NULL,
  orden                       int  NOT NULL,
  requiere_acuse              boolean NOT NULL DEFAULT false,
  requiere_recetario_especial boolean NOT NULL DEFAULT false,
  created_at                  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.medicamentos_categorias (codigo, etiqueta, orden, requiere_acuse, requiere_recetario_especial) VALUES
  ('venta_libre',    'Venta libre',    1, false, false),
  ('receta_simple',  'Receta simple',  2, false, false),
  ('psicotropico',   'Psicotropico',   3, true,  true),
  ('estupefaciente', 'Estupefaciente', 4, true,  true);

DO $$
DECLARE v_fuera int;
BEGIN
  SELECT count(*) INTO v_fuera
    FROM public.medicamentos m
   WHERE m.categoria_regulatoria IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.medicamentos_categorias c
                      WHERE c.codigo = m.categoria_regulatoria);
  IF v_fuera <> 0 THEN
    RAISE EXCEPTION 'MIG248-A: % medicamentos con categoria fuera del catalogo nuevo (probablemente recetario_especial)', v_fuera;
  END IF;
END $$;

ALTER TABLE public.medicamentos DROP CONSTRAINT chk_categoria_regulatoria;

ALTER TABLE public.medicamentos
  ADD CONSTRAINT fk_medicamentos_categoria
  FOREIGN KEY (categoria_regulatoria)
  REFERENCES public.medicamentos_categorias(codigo)
  ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE public.medicamentos_categorias ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.medicamentos_categorias FROM PUBLIC;
REVOKE ALL ON public.medicamentos_categorias FROM anon;
GRANT SELECT ON public.medicamentos_categorias TO authenticated;

CREATE POLICY medcat_select ON public.medicamentos_categorias
  FOR SELECT TO authenticated USING (true);

COMMIT;
