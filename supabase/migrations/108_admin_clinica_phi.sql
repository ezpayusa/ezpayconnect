-- ============================================================
-- Ola 2 · admin_clinica/gerente ven el PHI de SU clínica (SEGURIDAD, lectura viva)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20). Probes red-first P269–P281.
--
-- HALLAZGO: hoy admin_clinica/gerente solo ven `citas` de su clínica (policy + clinica_id).
-- En el resto del PHI no ven NADA salvo que sean el médico. Esta ola les da lectura del PHI
-- AUTORADO por los médicos de SU clínica (medico_id ∈ médicos de clinicas_del_usuario()).
--
-- Vínculo AUTORITATIVO admin→clínica = el MISMO que ya usa la policy de citas:
-- private.clinicas_del_usuario() (= obtener_clinica_usuario(uid) [clinicas.doctor_id ∪
-- medico_clinicas] ∪ medico_clinicas(uid)). Consistencia total con lo que el admin ya ve.
--
-- Anti-OR-trap (lección 41): el helper GATEA POR ROL PRIMERO (admin_clinica|gerente) →
-- un médico/paciente puro obtiene false → la policy nueva NO les otorga filas (no pueden
-- usar la pertenencia a clínica para ver PHI de colegas). Fail-closed estricto, sin IS NULL OR.
-- Helpers DEFINER '' con refs calificadas, anidando solo funciones ya endurecidas.
-- Scope: 8 tablas (NO dispensaciones, NO citas). examenes: solo eje médico (no toca laboratorio).
--
-- ⚠️ FRAGILIDAD id-space (NO forzada — DEUDA aparte): hay DOS identidades de médico:
--   medico_clinicas/citas → medicos.id   ·   PHI (expediente/signos/examenes) → perfiles.id.
-- El join del helper (medico_clinicas.medico_id = PHI.medico_id) es correcto SOLO porque hoy,
-- para los médicos que SON usuarios de la app, medicos.id == perfiles.id == auth.uid() (los
-- 7/10 que coinciden). Esto NO está forzado: no hay FK medicos↔perfiles, medicos.id default
-- = gen_random_uuid(), sin trigger de sincronización. Los 3 médicos solo-catálogo (sin perfil)
-- NO autoran PHI (sin login) → hoy no hay leak. Mecánicamente la divergencia produce falso-
-- NEGATIVO (admin no ve algo que debería), NO leak — un falso-positivo exigiría colisión de
-- uuid aleatorio (irreal). Probado por P282. RECOMENDACIÓN (deuda): forzar el invariante
-- (FK medicos.id→perfiles.id o sincronización) si un médico de catálogo llegara a tener login.
-- ============================================================

-- 1a) Helper núcleo (medico_id uuid): ¿el médico autor pertenece a una clínica que administro?
CREATE OR REPLACE FUNCTION private.medico_es_de_mi_clinica(p_medico_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT private.tiene_rol(ARRAY['admin_clinica','gerente'])     -- gate de ROL primero
     AND EXISTS (
       SELECT 1 FROM public.medico_clinicas mc
       WHERE mc.medico_id = p_medico_id
         AND mc.clinica_id IN (SELECT private.clinicas_del_usuario())
     );
$function$;
REVOKE EXECUTE ON FUNCTION private.medico_es_de_mi_clinica(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.medico_es_de_mi_clinica(uuid) TO authenticated;

-- 1b) Overload TEXT con parseo SEGURO (texto no-uuid → false, SIN RAISE): para columnas
--     medico_id TEXT (historial_medico, recetas_avanzadas). NO ::uuid crudo en el USING.
CREATE OR REPLACE FUNCTION private.medico_es_de_mi_clinica(p_medico_id text)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uuid uuid;
BEGIN
  IF p_medico_id IS NULL THEN RETURN false; END IF;
  BEGIN
    v_uuid := p_medico_id::uuid;            -- parseo defensivo
  EXCEPTION WHEN others THEN
    RETURN false;                            -- dato malformado → no rompe el SELECT de nadie
  END;
  RETURN private.medico_es_de_mi_clinica(v_uuid);
END;
$function$;
REVOKE EXECUTE ON FUNCTION private.medico_es_de_mi_clinica(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.medico_es_de_mi_clinica(text) TO authenticated;

-- 1c) Helper para receta_items (sin medico_id): resuelve el médico autor vía recetas (bigint).
--     receta_items.receta_id (bigint) referencia public.recetas (id bigint); recetas_avanzadas
--     es tabla aparte (id uuid) y NO es destino de receta_items.
CREATE OR REPLACE FUNCTION private.receta_de_mi_clinica(p_receta_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.recetas r
    WHERE r.id = p_receta_id
      AND COALESCE(private.medico_es_de_mi_clinica(r.medico_id), false)
  );
$function$;
REVOKE EXECUTE ON FUNCTION private.receta_de_mi_clinica(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.receta_de_mi_clinica(bigint) TO authenticated;

-- 2) Policies aditivas FOR SELECT TO authenticated (las existentes NO se tocan; citas NO se toca)
CREATE POLICY "Admin clinica ve historial de su clinica" ON public.historial_medico
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- medico_id TEXT → overload text

CREATE POLICY "Admin clinica ve recetas de su clinica" ON public.recetas
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- uuid

CREATE POLICY "Admin clinica ve recetas avanzadas de su clinica" ON public.recetas_avanzadas
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- medico_id TEXT → overload text

CREATE POLICY "Admin clinica ve items de recetas de su clinica" ON public.receta_items
  FOR SELECT TO authenticated
  USING (COALESCE(private.receta_de_mi_clinica(receta_id), false));

CREATE POLICY "Admin clinica ve expediente de su clinica" ON public.expediente_notas
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- uuid

CREATE POLICY "Admin clinica ve signos vitales de su clinica" ON public.signos_vitales
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- uuid

CREATE POLICY "Admin clinica ve examenes de su clinica" ON public.examenes
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- uuid (solo eje médico)

CREATE POLICY "Admin clinica ve pacientes de su clinica" ON public.pacientes
  FOR SELECT TO authenticated
  USING (COALESCE(private.medico_es_de_mi_clinica(medico_id), false));   -- uuid (scoping por medico_id base)
