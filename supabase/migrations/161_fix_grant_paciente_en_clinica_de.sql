-- 161 · Fix del grant faltante en private.paciente_en_clinica_de (bug de mig 160).
-- La función se invoca DIRECTAMENTE dentro de las policies RLS sv_insert_captura (WITH CHECK) y
-- sv_update_valida_medico, que se evalúan con el rol del caller (authenticated) — no como definer-owner.
-- En mig 160 quedó con REVOKE ALL FROM PUBLIC pero SIN GRANT a authenticated → toda INSERT/UPDATE de
-- vitales por authenticated reventaba con 42501 "permission denied for function" antes del gate real.
-- Fix: espeja el patrón de private.puede_gestionar_citas / tiene_rol / clinicas_del_usuario (helpers de
-- RLS llamados por authenticated, todos con GRANT a authenticated). private.clinicas_de NO necesita grant
-- porque solo la llaman funciones DEFINER (corren como owner).

GRANT EXECUTE ON FUNCTION private.paciente_en_clinica_de(integer) TO authenticated;
