-- =========================================================
-- CENSO FRENTE #7 — funciones de búsqueda de médicos sin gate
-- =========================================================
SELECT
  p.proname,
  p.prosecdef                                          AS security_definer,
  p.proconfig                                          AS config_search_path,
  has_function_privilege('anon', p.oid, 'EXECUTE')          AS exec_anon,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS exec_authenticated,
  has_function_privilege('service_role', p.oid, 'EXECUTE')  AS exec_service_role,
  pg_get_functiondef(p.oid)                            AS definicion
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname IN (
  'listar_medicos_por_pais',
  'buscar_medicos',
  'obtener_medicos_por_ids',
  'contar_medicos_por_pais',
  'contar_medicos_por_ids'
)
ORDER BY p.proname;

-- =========================================================
-- MINI-FRENTE — visitas_agendadas / reasignación de proveedor
-- =========================================================
SELECT relrowsecurity AS rls_enabled, relforcerowsecurity AS rls_forced
FROM pg_class WHERE relname = 'visitas_agendadas';

SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'visitas_agendadas'
ORDER BY policyname;

SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'visitas_agendadas'
ORDER BY grantee, privilege_type;

-- columnas de la tabla (para confirmar cuenta_proveedor_id, pais_id, etc.)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'visitas_agendadas'
ORDER BY ordinal_position;
