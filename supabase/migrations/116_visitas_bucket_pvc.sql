-- ============================================================
-- Ola 3 · Opción B — visitas = BUCKET por contrato en pvc (única fuente). SEGURIDAD + reconciliación.
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de gate + lectura viva + migración de datos. Probes P320–P333.
--
-- pvc = ÚNICA fuente para visitas (país + bolsa juntos, único write super_admin). planes_asignaciones
-- NO se borra: se DESACOPLA (se retiran sus 2 filas empresa_cuota + el trigger mensual); las filas
-- medico_id (suscripciones SaaS) quedan INTACTAS.
--
-- DECISIONES (Oscar): cap = BOLSA por contrato (no mensual). no_show CONSUME; cancelada/rechazada
-- DEVUELVEN (vía conteo DERIVADO sobre estados no-cancelados). cc17afe8 = bolsa canónica 5 (pvc
-- existente; se descarta el "ilimitado" de PA). Multi-país = una bolsa por país. 411d6f8c = pvc
-- incluidas=2, vigencia 1 año desde inicio, país derivado de empresa_paises_operacion.
--
-- CONTEO DERIVADO (sin contador almacenado → auto-corrige, cancelación se resuelve sola):
--   usadas = COUNT(visitas de la empresa con pais_id = país del pvc, dentro de vigencia,
--            estado NOT IN ('cancelada','rechazada'))   [no_asistio NO excluido → consume].
-- ESTAMPADO: el gate fija visitas_agendadas.pais_id = país del médico al agendar → atribución
-- CONGELADA (si el médico cambia de país luego, las visitas ya consumidas no se re-atribuyen).
-- CONCURRENCIA: el gate lockea la fila pvc (FOR UPDATE) → serializa el check usadas<incluidas (anti-TOCTOU).
-- ============================================================

-- 1) "ilimitado" = NULL (hoy NOT NULL default 0)
ALTER TABLE public.planes_visitador_contratados ALTER COLUMN cantidad_visitas_incluidas DROP NOT NULL;

-- 2) Conteo derivado de la bolsa (DRY: gate + RPCs). p_exclude = id a excluir (la propia fila en UPDATE).
CREATE OR REPLACE FUNCTION private.pvc_usadas(p_empresa uuid, p_pais uuid, p_inicio date, p_fin date, p_exclude uuid DEFAULT NULL)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT count(*)::int FROM public.visitas_agendadas v
  WHERE v.empresa_id = p_empresa
    AND v.pais_id = p_pais
    AND v.fecha_visita BETWEEN p_inicio AND p_fin
    AND v.estado NOT IN ('cancelada','rechazada')      -- no_asistio CONSUME; cancelada/rechazada DEVUELVEN
    AND (p_exclude IS NULL OR v.id <> p_exclude);
$function$;
REVOKE EXECUTE ON FUNCTION private.pvc_usadas(uuid,uuid,date,date,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.pvc_usadas(uuid,uuid,date,date,uuid) TO authenticated;

-- 3) GATE UNIFICADO (país + bucket) sobre el trigger existente trg_gate_visita_pais.
--    Reemplaza la función; reusa la localización pvc de visitador_ve_medico; estampa país; lockea bolsa.
CREATE OR REPLACE FUNCTION private.gate_visita_pais()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_pais uuid; v_pvc record; v_usadas int;
BEGIN
  SELECT p.pais_id INTO v_pais FROM public.perfiles p WHERE p.id = NEW.medico_id;

  -- pvc activo+vigente de la empresa del visitador que cubre el país del médico (= visitador_ve_medico)
  SELECT pvc.* INTO v_pvc
  FROM public.planes_visitador_contratados pvc
  WHERE pvc.empresa_id = public.mi_empresa_proveedor()
    AND pvc.estado = 'activo'
    AND CURRENT_DATE BETWEEN pvc.fecha_inicio AND pvc.fecha_fin
    AND COALESCE(pvc.pais_id = v_pais, false)
  ORDER BY pvc.fecha_fin DESC
  LIMIT 1
  FOR UPDATE;                                          -- serializa el check de bolsa (anti-TOCTOU)

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autorizado: sin plan de visitas activo que cubra el país del médico'
      USING ERRCODE = 'P0001';                         -- error PAÍS
  END IF;

  NEW.pais_id := v_pais;                               -- ESTAMPAR (atribución congelada)

  IF v_pvc.cantidad_visitas_incluidas IS NULL THEN
    RETURN NEW;                                        -- ilimitado
  END IF;

  v_usadas := private.pvc_usadas(v_pvc.empresa_id, v_pvc.pais_id, v_pvc.fecha_inicio, v_pvc.fecha_fin, NEW.id);
  IF v_usadas >= v_pvc.cantidad_visitas_incluidas THEN
    RAISE EXCEPTION 'Bolsa de visitas agotada para el país (% de % usadas)', v_usadas, v_pvc.cantidad_visitas_incluidas
      USING ERRCODE = 'PV001';                         -- error BUCKET. SQLSTATE custom (NO P0002=no_data_found
                                                       -- reservado): distinguible de país (P0001) sin pisar built-ins.
  END IF;

  RETURN NEW;
END;
$function$;

-- 4) RETIRAR el conteo mensual (planes_asignaciones empresa_cuota)
DROP TRIGGER IF EXISTS trg_limite_visitas ON public.visitas_agendadas;
DROP FUNCTION IF EXISTS public.trg_limite_visitas_mes();

-- 5) estado_plan_visitas → por país, desde pvc (país + bolsa restante derivada). FORMA NUEVA.
DROP FUNCTION IF EXISTS public.estado_plan_visitas();
CREATE OR REPLACE FUNCTION public.estado_plan_visitas()
RETURNS TABLE(pais_id uuid, pais_nombre text, tiene_pvc boolean, incluidas integer, usadas integer, restante integer, ilimitado boolean, fecha_fin date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_empresa uuid;
BEGIN
  v_empresa := mi_empresa_proveedor();
  IF v_empresa IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT pvc.pais_id, cp.nombre::text, true,
         pvc.cantidad_visitas_incluidas,
         private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin),
         CASE WHEN pvc.cantidad_visitas_incluidas IS NULL THEN NULL
              ELSE GREATEST(0, pvc.cantidad_visitas_incluidas - private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin)) END,
         (pvc.cantidad_visitas_incluidas IS NULL),
         pvc.fecha_fin
  FROM planes_visitador_contratados pvc
  JOIN configuracion_pais cp ON cp.id = pvc.pais_id
  WHERE pvc.empresa_id = v_empresa AND pvc.estado = 'activo'
    AND CURRENT_DATE BETWEEN pvc.fecha_inicio AND pvc.fecha_fin;
END;
$function$;

-- 6) get_planes_visitador_proveedor → desde pvc. FORMA NUEVA. (overload uuid usado por el frontend + no-arg)
DROP FUNCTION IF EXISTS public.get_planes_visitador_proveedor(uuid);
DROP FUNCTION IF EXISTS public.get_planes_visitador_proveedor();
CREATE OR REPLACE FUNCTION public.get_planes_visitador_proveedor(p_empresa_id uuid DEFAULT NULL)
RETURNS TABLE(pvc_id uuid, pais_id uuid, pais_nombre text, plan_visitador_id integer, incluidas integer, usadas integer, restante integer, ilimitado boolean, fecha_inicio date, fecha_fin date, estado text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_empresa uuid;
BEGIN
  v_empresa := COALESCE(p_empresa_id, mi_empresa_proveedor());
  -- autz: solo la propia empresa (o super_admin)
  IF v_empresa IS NULL THEN RETURN; END IF;
  IF v_empresa <> mi_empresa_proveedor() AND NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT pvc.id, pvc.pais_id, cp.nombre::text, pvc.plan_visitador_id,
         pvc.cantidad_visitas_incluidas,
         private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin),
         CASE WHEN pvc.cantidad_visitas_incluidas IS NULL THEN NULL
              ELSE GREATEST(0, pvc.cantidad_visitas_incluidas - private.pvc_usadas(pvc.empresa_id, pvc.pais_id, pvc.fecha_inicio, pvc.fecha_fin)) END,
         (pvc.cantidad_visitas_incluidas IS NULL),
         pvc.fecha_inicio, pvc.fecha_fin, pvc.estado::text
  FROM planes_visitador_contratados pvc
  JOIN configuracion_pais cp ON cp.id = pvc.pais_id
  WHERE pvc.empresa_id = v_empresa AND pvc.estado = 'activo';
END;
$function$;

-- 7) MIGRACIÓN de datos: las 2 filas empresa_cuota de planes_asignaciones → pvc (médico-subs INTACTAS).
DO $$
DECLARE v_pa record; v_pais uuid; v_cap int; v_inicio date;
BEGIN
  FOR v_pa IN
    SELECT pa.id, pa.empresa_id, pa.fecha_inicio, pa.fecha_fin, pb.limite_medicos AS cap
    FROM public.planes_asignaciones pa
    LEFT JOIN public.planes_configuracion pc ON pc.id = pa.plan_config_id
    LEFT JOIN public.planes_base pb ON pb.id = pc.plan_base_id
    WHERE pa.empresa_id IS NOT NULL
  LOOP
    -- cc17afe8 (cap NULL en PA) ya tiene pvc canónico (incluidas=5) → solo se desacopla (DELETE PA).
    -- Para empresas SIN pvc, crear uno por país operado (una bolsa por país), cap = limite_medicos del PA.
    v_inicio := v_pa.fecha_inicio::date;
    FOR v_pais IN
      SELECT epo.pais_id FROM public.empresa_paises_operacion epo
      WHERE epo.empresa_id = v_pa.empresa_id AND epo.activo
    LOOP
      IF NOT EXISTS (SELECT 1 FROM public.planes_visitador_contratados pvc
                     WHERE pvc.empresa_id = v_pa.empresa_id AND pvc.pais_id = v_pais) THEN
        INSERT INTO public.planes_visitador_contratados
          (empresa_id, plan_visitador_id, pais_id, cantidad_visitas_incluidas, visitas_usadas, precio_pagado, fecha_inicio, fecha_fin, estado)
        VALUES
          (v_pa.empresa_id, 1, v_pais, v_pa.cap, 0, 0, v_inicio,
           COALESCE(v_pa.fecha_fin::date, v_inicio + INTERVAL '1 year'), 'activo');   -- fin=null → 1 año
      END IF;
    END LOOP;
    -- desacoplar: retirar la fila empresa_cuota de planes_asignaciones
    DELETE FROM public.planes_asignaciones WHERE id = v_pa.id;
  END LOOP;
END $$;
