-- Barrido authz pre-067: cerrar enum anon en 3 RPCs DEFINER (recon 8 jul, verificado en prod).
-- Las 3 eran SECURITY DEFINER, ejecutables por anon+authenticated, sin cruzar el id del cliente
-- contra auth.uid() → un anon podía enumerar user_ids / membresías iterando UUIDs.
-- Callers: verificado 0 en supabase/functions/. Ver grep repo para callers cliente/internos.

-- obtener_admins_clinica(p_clinica_id): 0 callers cliente; solo DEFINER internos (125/127, push).
REVOKE EXECUTE ON FUNCTION public.obtener_admins_clinica(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.obtener_admins_clinica(uuid) TO service_role;

-- obtener_usuarios_empresa(p_empresa_id): 0 callers cliente; solo DEFINER internos (131/222, notif).
REVOKE EXECUTE ON FUNCTION public.obtener_usuarios_empresa(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.obtener_usuarios_empresa(uuid) TO service_role;

-- obtener_clinicas_medico(p_medico_id): caller cliente vivo (AgendarCitaModal, paciente logueado).
ALTER FUNCTION public.obtener_clinicas_medico(uuid) SET search_path = 'public';
REVOKE EXECUTE ON FUNCTION public.obtener_clinicas_medico(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.obtener_clinicas_medico(uuid) TO authenticated, service_role;
