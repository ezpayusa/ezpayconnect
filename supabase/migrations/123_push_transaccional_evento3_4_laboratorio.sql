-- ============================================================
-- Fix push transaccional · EVENTOS 3 (orden→lab) y 4 (resultado→médico+paciente). SEGURIDAD. Camino VIVO.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes red-first P366–P372.
--
-- EVT3: wrapper NUEVO notificar_orden_lab(examen_id) — DEFINER ''. Recibe SOLO el ref (examen_id); cero
-- target/contenido del caller; compone título/mensaje server-side; accion_url interna. Gate: el caller es
-- el médico que ordenó (COALESCE fail-closed). Inserta fila(s) staff (lab, fan-out a cuentas activas) +
-- fila paciente, DIRECTO (no delega en notificar_laboratorio/notificar_paciente — esos re-gatean por otra
-- relación; el wrapper es su propio productor gateado). push_notificar por CADA id insertado.
--
-- EVT4: notificar_resultado_examen — SOLO REPARACIÓN (sin fold de push; ver nota abajo):
--   (a) endurece search_path 'public'→'' INNER-FIRST (l.39): sus callees ya tienen su propio search_path
--       (mi_empresa_proveedor='public', notificar_paciente='', push_notificar='') → seguro; se califican
--       todas las refs del outer.
--   (b) REPARA un camino ROTO: hoy llama notificar_paciente (gate médico/clínica) bajo un LAB → siempre
--       RAISE 'No autorizado…' (P0001) + tipo 'examen_resultado' ni está en el CHECK. Se reemplaza por
--       INSERT DIRECTO a la campanita (gate propio = lab dueño), tipo válido 'examen' (el front NO distingue
--       examen vs examen_resultado: ramifica email/in-app/sms; título+url cargan el significado).
--   NO push_notificar aquí: main (useLaboratorio:158) ya dispara push por el edge VIEJO; foldear ahora =
--   DOBLE push hasta mergear el hook. Reparación = single-push por el edge viejo (que ahora recibe dest
--   poblado, antes null por el RAISE). El FOLD de push de evt4 = increment aparte, junto al merge del hook.
--
-- evt3 (notificar_orden_lab) SÍ lleva push (RPC nuevo, dormant en main → no dobla).
-- NO se toca aún la llamabilidad de notificar_laboratorio/notificar_paciente (capstone = cierre final).
-- ============================================================

-- EVT3 — wrapper de orden de examen → laboratorio + paciente
CREATE OR REPLACE FUNCTION public.notificar_orden_lab(p_examen_id integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_nid uuid; v_pid integer; rec record;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Examen no encontrado' USING ERRCODE = 'PT001'; END IF;
  -- gate: el caller ordenó este examen (o super_admin). COALESCE fail-closed.
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']) OR v.medico_id = auth.uid(), false) THEN
    RAISE EXCEPTION 'No autorizado para notificar esta orden' USING ERRCODE = 'PT002'; END IF;
  -- LAB: fan-out a cuentas activas; contenido server-side; push por id. tipo 'orden_examen' (convención staff existente)
  FOR rec IN SELECT cp.id FROM public.cuentas_proveedor cp WHERE cp.empresa_id = v.laboratorio_id AND cp.activo = true LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.id, 'orden_examen', 'Nueva orden de examen', 'El médico envió una orden de examen: '||COALESCE(v.tipo,'')||'.', '/laboratorio/ordenes')
      RETURNING id INTO v_nid;
    PERFORM private.push_notificar('notificaciones', v_nid::text);
  END LOOP;
  -- PACIENTE: campanita; contenido server-side; push
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Nueva orden de examen', 'Tu médico te ordenó un examen: '||COALESCE(v.tipo,'')||'.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text);
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_orden_lab(integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_orden_lab(integer) TO authenticated;   -- gate real = médico de la orden (dentro)

-- EVT4 — resultado de examen → médico + paciente (search_path '' + repara lab→paciente + push)
CREATE OR REPLACE FUNCTION public.notificar_resultado_examen(p_examen_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v public.examenes%ROWTYPE; v_paciente_auth uuid; v_pid integer; v_mid uuid;
BEGIN
  SELECT * INTO v FROM public.examenes WHERE id = p_examen_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  -- gate: SOLO el lab dueño de la orden (null-safe IS DISTINCT FROM → fail-closed)
  IF v.laboratorio_id IS DISTINCT FROM public.mi_empresa_proveedor() THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- PACIENTE: insert DIRECTO (el lab no pasa el gate médico/clínica de notificar_paciente; relación = dueño
  -- de la orden). tipo 'examen' (válido en el CHECK; antes 'examen_resultado' lo violaba). push por id.
  -- NOTA: evt4 NO llama push_notificar aquí (a propósito). notificar_resultado_examen ya lo invoca main
  -- (useLaboratorio:158) con el edge VIEJO (enviar-push) aún vivo; foldear el push ahora = DOBLE push en
  -- prod hasta mergear el hook. Esta migración SOLO REPARA (single-push por el edge viejo, que ahora sí
  -- recibe dest poblado). El fold de push de evt4 = increment aparte, junto al merge de su hook.
  IF v.paciente_id IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v.paciente_id, 'examen', 'Resultado de examen listo', 'Tu examen '||COALESCE(v.tipo,'')||' ya tiene resultado.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    SELECT auth_user_id INTO v_paciente_auth FROM public.pacientes WHERE id = v.paciente_id;
  END IF;
  -- MÉDICO: notificaciones (sin CHECK de tipo; preserva 'examen_resultado')
  IF v.medico_id IS NOT NULL THEN
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (v.medico_id, 'examen_resultado', 'Resultado de examen listo',
              'El laboratorio subió el resultado de '||COALESCE(v.tipo,'')||' ('||COALESCE(v.paciente_nombre,'paciente')||').', '/medico/citas')
      RETURNING id INTO v_mid;
  END IF;
  RETURN jsonb_build_object('medico', v.medico_id, 'paciente', v_paciente_auth);
END;
$function$;
