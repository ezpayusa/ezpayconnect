-- Barrido authz pre-067: registrar_medico/clinica_desde_invitacion (mig 024) eran DEFINER
-- ejecutables por anon+authenticated, tomando p_user_id del cliente sin cruzarlo contra la
-- identidad del caller -> con token+email válidos se podía forjar el rol privilegiado en una
-- cuenta arbitraria. El ÚNICO caller legítimo es la edge (service_role) registrar-*-invitacion,
-- que valida token+email y crea el auth user server-side pasando ese id. Revocar el acceso
-- directo elimina la forja de p_user_id sin tocar el flujo (que corre por service_role).
-- NO se usa gate auth.uid(): la edge llama con service_role -> auth.uid() seria NULL y rompería el alta.
REVOKE EXECUTE ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) TO service_role;
ALTER  FUNCTION public.registrar_medico_desde_invitacion(uuid,uuid,text,text,text,text) SET search_path = 'public';
REVOKE EXECUTE ON FUNCTION public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text) TO service_role;
ALTER  FUNCTION public.registrar_clinica_desde_invitacion(uuid,uuid,text,text,text) SET search_path = 'public';
