-- ============================================================
-- 061: Límite mensual de visitas según el plan del proveedor.
--  - Sin plan activo -> no puede agendar (SIN_PLAN).
--  - Con plan: cupo mensual = suma de limite_medicos de los planes activos.
--    Si algún plan activo no tiene tope configurado (NULL) -> ilimitado.
--  - El cupo se cuenta por mes (de la fecha de la visita); repetir médico cuenta.
--  - Canceladas/rechazadas/no_asistio liberan su unidad.
-- ============================================================

CREATE OR REPLACE FUNCTION trg_limite_visitas_mes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_tiene_plan boolean; v_ilimitado boolean; v_cupo int; v_cnt int;
BEGIN
  IF NEW.estado IN ('cancelada', 'rechazada', 'no_asistio') THEN RETURN NEW; END IF;

  SELECT EXISTS (
    SELECT 1 FROM planes_asignaciones pa
    WHERE pa.empresa_id = NEW.empresa_id AND pa.estado = 'activo'
      AND (pa.fecha_fin IS NULL OR pa.fecha_fin >= CURRENT_DATE)
  ) INTO v_tiene_plan;

  IF NOT v_tiene_plan THEN
    RAISE EXCEPTION 'SIN_PLAN' USING ERRCODE = 'P0001';
  END IF;

  SELECT bool_or(pb.limite_medicos IS NULL), COALESCE(sum(pb.limite_medicos), 0)::int
  INTO v_ilimitado, v_cupo
  FROM planes_asignaciones pa
  JOIN planes_configuracion pc ON pc.id = pa.plan_config_id
  JOIN planes_base pb ON pb.id = pc.plan_base_id
  WHERE pa.empresa_id = NEW.empresa_id AND pa.estado = 'activo'
    AND (pa.fecha_fin IS NULL OR pa.fecha_fin >= CURRENT_DATE);

  IF COALESCE(v_ilimitado, true) THEN RETURN NEW; END IF; -- sin tope configurado => ilimitado

  SELECT count(*) INTO v_cnt FROM visitas_agendadas v
  WHERE v.empresa_id = NEW.empresa_id
    AND date_trunc('month', v.fecha_visita) = date_trunc('month', NEW.fecha_visita)
    AND v.estado NOT IN ('cancelada', 'rechazada', 'no_asistio');

  IF v_cnt >= v_cupo THEN
    RAISE EXCEPTION 'LIMITE_MENSUAL' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_limite_visitas ON visitas_agendadas;
CREATE TRIGGER trg_limite_visitas BEFORE INSERT ON visitas_agendadas
FOR EACH ROW EXECUTE FUNCTION trg_limite_visitas_mes();

-- Estado del plan de visitas de mi empresa (para el contador y el CTA).
CREATE OR REPLACE FUNCTION estado_plan_visitas()
RETURNS TABLE (tiene_plan boolean, cupo int, ilimitado boolean, usadas_mes int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_empresa uuid;
BEGIN
  v_empresa := mi_empresa_proveedor();
  IF v_empresa IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    EXISTS (SELECT 1 FROM planes_asignaciones pa WHERE pa.empresa_id = v_empresa AND pa.estado = 'activo' AND (pa.fecha_fin IS NULL OR pa.fecha_fin >= CURRENT_DATE)),
    (SELECT COALESCE(sum(pb.limite_medicos), 0)::int FROM planes_asignaciones pa
       JOIN planes_configuracion pc ON pc.id = pa.plan_config_id JOIN planes_base pb ON pb.id = pc.plan_base_id
       WHERE pa.empresa_id = v_empresa AND pa.estado = 'activo' AND (pa.fecha_fin IS NULL OR pa.fecha_fin >= CURRENT_DATE)),
    (SELECT COALESCE(bool_or(pb.limite_medicos IS NULL), false) FROM planes_asignaciones pa
       JOIN planes_configuracion pc ON pc.id = pa.plan_config_id JOIN planes_base pb ON pb.id = pc.plan_base_id
       WHERE pa.empresa_id = v_empresa AND pa.estado = 'activo' AND (pa.fecha_fin IS NULL OR pa.fecha_fin >= CURRENT_DATE)),
    (SELECT count(*)::int FROM visitas_agendadas v WHERE v.empresa_id = v_empresa
       AND date_trunc('month', v.fecha_visita) = date_trunc('month', CURRENT_DATE)
       AND v.estado NOT IN ('cancelada', 'rechazada', 'no_asistio'));
END; $$;
GRANT EXECUTE ON FUNCTION estado_plan_visitas() TO authenticated;
