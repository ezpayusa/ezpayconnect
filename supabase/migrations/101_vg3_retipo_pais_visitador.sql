-- ============================================================
-- V-G3 · Visitas: re-tipo planes_visitador_contratados.pais_id integer→uuid + FK (INERTE)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes red-first (P237–P240). Prerequisito de Vis-A/V-G1/V-G2.
-- La columna pais_id era integer HUÉRFANA (1 fila, pais_id NULL, sin FK, sin tabla integer
-- de países a la cual mapear) → re-tipar a uuid es trivial (USING NULL; 0 datos a migrar) y
-- añadir el FK correcto a configuracion_pais. ON DELETE RESTRICT (fail-closed, igual que el
-- resto del eje país). INERTE: el término país aún NO se cablea a ninguna policy/RPC viva.
-- ============================================================

ALTER TABLE public.planes_visitador_contratados
  ALTER COLUMN pais_id TYPE uuid USING NULL::uuid;   -- la única fila es NULL → sin pérdida

ALTER TABLE public.planes_visitador_contratados
  DROP CONSTRAINT IF EXISTS planes_visitador_contratados_pais_id_fkey;
ALTER TABLE public.planes_visitador_contratados
  ADD CONSTRAINT planes_visitador_contratados_pais_id_fkey
  FOREIGN KEY (pais_id) REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT;
