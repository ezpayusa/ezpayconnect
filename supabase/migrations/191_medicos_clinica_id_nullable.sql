-- 191 Auto-registro clínica FASE 4 — medicos.clinica_id NULLABLE (reversible, desbloquea el alta)
-- Solo DROP NOT NULL. NO se hace DROP COLUMN (queda para un paso 6 opcional, decisión de Oscar).
-- La FK medicos_clinica_id_fkey (ON DELETE CASCADE) se mantiene por ahora (se quita junto con el drop futuro).
-- Con esto, registrar_medico_desde_invitacion (mig 190) puede crear el médico sin clinica_id → alta por
-- invitación funciona de punta a punta (era el bug que rompía el auto-registro).

ALTER TABLE public.medicos ALTER COLUMN clinica_id DROP NOT NULL;
