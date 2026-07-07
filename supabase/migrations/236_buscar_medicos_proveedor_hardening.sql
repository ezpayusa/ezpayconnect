-- ============================================================================
-- Migración 236: reconstruir buscar_medicos_proveedor(text) endurecida (A5)
-- ============================================================================
-- Cierra A5 de AUDITORIA-PROFUNDA-2026-07-05.md + hallazgo adicional confirmado
-- por recon (Codex, Management API): la función existe SOLO en prod (drift, nunca
-- estuvo en migraciones) y su definición viva es SECURITY DEFINER, EJECUTABLE POR
-- ANON, sin search_path fijo, sin scope por país, sin filtro activo → devolvía
-- nombre+email de TODOS los médicos a cualquiera (autenticado o no).
--
-- Definición viva en prod (a reemplazar):
--   CREATE FUNCTION public.buscar_medicos_proveedor(p_query text)
--   RETURNS TABLE(id uuid, nombre_completo text, email text)
--   -- SELECT p.id, p.nombre_completo, p.email FROM perfiles p
--   --  WHERE p.rol='medico'
--   --    AND (p_query IS NULL OR p_query='' OR p.nombre_completo ILIKE '%'||p_query||'%')
--   --  ORDER BY p.nombre_completo LIMIT 50;
--
-- No hay drop-in equivalente (confirmado por recon): buscar_medicos no trae email
-- y exige p_pais_id; buscar_medicos_paciente está atada a paciente autenticado.
-- Por eso se reconstruye ESTA función, conservando su shape de retorno
-- (id, nombre_completo, email) para no romper sus 2 call sites:
--   src/proveedor/hooks/useMedicosDisponibles.ts:20
--   src/proveedor/hooks/useVisitasAgendadas.ts:60
--
-- Endurecimiento (convención fase0/mig 067+ y patrón de buscar_medicos_paciente):
--   * SET search_path = '' + refs calificadas.
--   * REVOKE de PUBLIC/anon → sólo authenticated ejecuta.
--   * Gate de auth: RAISE si no hay caller (defensivo; anon ya queda revocado).
--   * Scope por país vía private.mi_pais() (helper existente, mig 073: deriva el
--     país del caller desde perfiles / cuentas_proveedor / empresa del proveedor).
--     FAIL-CLOSED: "(v_pais IS NOT NULL AND pais_id = v_pais)" → un proveedor sólo
--     ve médicos de su país, y si no se puede derivar país del caller devuelve 0
--     filas (más estricto que buscar_medicos_paciente/184, superficie proveedor).
--   * Filtro activo = true (columna confirmada en perfiles; hoy los 4 médicos son
--     activo=true, así que no altera el resultado visible actual).
-- Verificado en dry-run: para un proveedor autorizado (visitador.qa, GT) el
-- conjunto devuelto NO cambia (mismos médicos antes/después).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.buscar_medicos_proveedor(p_query text DEFAULT NULL)
RETURNS TABLE (
  id              uuid,
  nombre_completo text,
  email           text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_pais uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no_auth';   -- defensivo: anon ya queda revocado abajo
  END IF;

  v_pais := private.mi_pais();   -- país del caller (perfil / proveedor / empresa)

  RETURN QUERY
  SELECT p.id, p.nombre_completo, p.email
  FROM public.perfiles p
  WHERE p.rol = 'medico'
    AND p.activo = true
    AND (v_pais IS NOT NULL AND p.pais_id = v_pais)            -- aislamiento por país (fail-closed: sin país ⇒ 0 filas)
    AND (p_query IS NULL OR p_query = ''
         OR p.nombre_completo ILIKE '%' || p_query || '%')      -- filtro de búsqueda (idéntico al vivo)
  ORDER BY p.nombre_completo
  LIMIT 50;
END;
$$;

REVOKE ALL     ON FUNCTION public.buscar_medicos_proveedor(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.buscar_medicos_proveedor(text) TO authenticated;

-- ============================================================================
-- Verificación post-aplicación (probes de solo lectura):
--   anon NO ejecuta:
--     SELECT has_function_privilege('anon',
--       'public.buscar_medicos_proveedor(text)','EXECUTE');            -- false
--   search_path fijo:
--     SELECT proconfig FROM pg_proc WHERE proname='buscar_medicos_proveedor'; -- {search_path=""}
-- ============================================================================
