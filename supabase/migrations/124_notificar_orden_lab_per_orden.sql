-- ============================================================
-- Fix push transaccional · EVT3 re-granularización: notificar_orden_lab POR-ORDEN. SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN. Probes P366–P373 red-first.
--
-- La v(integer) per-examen (mig 123, DORMANT, 0 callers) no matchea ConsultaPage, que crea UNA orden con N
-- exámenes (mismo orden_id) y notifica UNA vez (resumen "N exámenes") a paciente + lab. Se reemplaza por
-- notificar_orden_lab(p_orden_id uuid) per-orden. Recon: 0 órdenes multi-lab/médico/paciente.
--
-- Gate FAIL-CLOSED ante inconsistencia (l.43): si la orden abarca >1 médico/paciente/lab → DENIEGA (no
-- notificar a un derivado equivocado; el multi-lab acotado se evita denegando = cero leak cross-lab). El
-- médico autoritativo se deriva de la orden (único por el guard). COALESCE fail-closed.
--
-- DROP explícito de la v(integer) dormant (sin coexistencia de overloads, l.50). CREATE con SECURITY
-- DEFINER + SET search_path='' RE-declarados desde cero. Contenido server-side; cero params del caller.
-- ============================================================

DROP FUNCTION IF EXISTS public.notificar_orden_lab(integer);   -- dormant (0 callers); sin overloads coexistiendo

CREATE OR REPLACE FUNCTION public.notificar_orden_lab(p_orden_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_count int; v_nlab int; v_nmed int; v_npac int; v_cmed int; v_cpac int; v_clab int;
  v_lab uuid; v_med uuid; v_pac int; v_tipo1 text; v_resumen text; v_nid uuid; v_pid int; rec record;
BEGIN
  -- (uuid no soporta min(); array_agg DISTINCT [1] — unívoco por los guards siguientes). count(col)=no-NULL.
  SELECT count(*), count(DISTINCT laboratorio_id), count(DISTINCT medico_id), count(DISTINCT paciente_id),
         count(medico_id), count(paciente_id), count(laboratorio_id),
         (array_agg(DISTINCT laboratorio_id) FILTER (WHERE laboratorio_id IS NOT NULL))[1],
         (array_agg(DISTINCT medico_id) FILTER (WHERE medico_id IS NOT NULL))[1],
         min(paciente_id), min(tipo)
    INTO v_count, v_nlab, v_nmed, v_npac, v_cmed, v_cpac, v_clab, v_lab, v_med, v_pac, v_tipo1
    FROM public.examenes WHERE orden_id = p_orden_id;
  IF v_count = 0 THEN RAISE EXCEPTION 'Orden no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- FAIL-CLOSED (l.43/P360): cols nullable → el check >1-distinct NO cacha NULL/incompleto. Deniega si:
  --  (a) multi médico/paciente/lab; (b) médico/paciente con algún NULL (cmed/cpac < count → derivado ambiguo);
  --  (c) lab mixto (parte con lab, parte NULL). Lab TODO-NULL es válido (orden sin lab → sólo paciente).
  IF v_nmed > 1 OR v_npac > 1 OR v_nlab > 1 THEN
    RAISE EXCEPTION 'Orden inconsistente (multi médico/paciente/lab)' USING ERRCODE = 'PT003'; END IF;
  IF v_cmed <> v_count OR v_cpac <> v_count THEN
    RAISE EXCEPTION 'Orden con médico/paciente NULL o incompleto' USING ERRCODE = 'PT003'; END IF;
  IF v_clab NOT IN (0, v_count) THEN
    RAISE EXCEPTION 'Orden con laboratorio mixto (parte NULL)' USING ERRCODE = 'PT003'; END IF;
  -- GATE authz: el caller es el médico de la orden (o super_admin). COALESCE fail-closed.
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']) OR v_med = auth.uid(), false) THEN
    RAISE EXCEPTION 'No autorizado para notificar esta orden' USING ERRCODE = 'PT002'; END IF;
  -- resumen server-side (1 examen → su tipo; N → 'N exámenes'); cero contenido del caller
  v_resumen := CASE WHEN v_count = 1 THEN COALESCE(v_tipo1,'examen') ELSE v_count||' exámenes' END;
  -- LAB: sólo si hay lab; fan-out a cuentas activas; UNA notif por cuenta (acotada a este lab/orden); push por id
  IF v_lab IS NOT NULL THEN
    FOR rec IN SELECT cp.id FROM public.cuentas_proveedor cp WHERE cp.empresa_id = v_lab AND cp.activo = true LOOP
      INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
        VALUES (rec.id, 'orden_examen', 'Nueva orden de examen', 'El médico envió una orden: '||v_resumen||'.', '/laboratorio/ordenes')
        RETURNING id INTO v_nid;
      PERFORM private.push_notificar('notificaciones', v_nid::text);
    END LOOP;
  END IF;
  -- PACIENTE: UNA campanita por orden con el resumen/count; push
  IF v_pac IS NOT NULL THEN
    INSERT INTO public.notificaciones_pacientes (paciente_id, tipo, titulo, mensaje, accion_url, leida)
      VALUES (v_pac, 'examen', 'Nueva orden de examen', 'Tu médico te ordenó: '||v_resumen||'.', '/paciente/examenes', false)
      RETURNING id INTO v_pid;
    PERFORM private.push_notificar('notificaciones_pacientes', v_pid::text);
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notificar_orden_lab(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.notificar_orden_lab(uuid) TO authenticated;   -- gate real = médico de la orden (dentro)
