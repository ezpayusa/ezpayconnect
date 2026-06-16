-- ============================================================
-- PAÍS-0 · Helpers de país para tablas sin pais_id propio (INERTE)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — probes rojo-primero (P191–P194). Aditivo/reversible.
-- NINGUNA policy/RPC viva tocada. Estos helpers no se referencian en ningún predicado
-- todavía (los increments #2–#5 los activan). Como una subquery dentro de una policy
-- corre con la RLS del caller (nota 12), la derivación de país que cruza a otra tabla
-- va en funciones SECURITY DEFINER (bypassean RLS para resolver pais_id de forma estable).
--
-- mi_pais() NO se toca (ya es COALESCE(perfiles.pais_id, cuentas_proveedor.pais_id,
-- empresa.pais_id), DEFINER, search_path=''). FAIL-CLOSED: mi_pais() NULL → 0 filas →
-- false (sin grandfather; país es borde de tenant duro).
-- ============================================================

CREATE OR REPLACE FUNCTION private.farmacia_en_mi_pais(p_farmacia_id integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.farmacias f
    WHERE f.id = p_farmacia_id
      AND f.pais_id = private.mi_pais()   -- mi_pais() NULL → '= NULL' → false (fail-closed); p_id NULL → false
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.farmacia_en_mi_pais(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.farmacia_en_mi_pais(integer) TO authenticated;

CREATE OR REPLACE FUNCTION private.lab_en_mi_pais(p_laboratorio_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.empresas_proveedoras e
    WHERE e.id = p_laboratorio_id
      AND e.pais_id = private.mi_pais()   -- fail-closed igual
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.lab_en_mi_pais(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.lab_en_mi_pais(uuid) TO authenticated;
