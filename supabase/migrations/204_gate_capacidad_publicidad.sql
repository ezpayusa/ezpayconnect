-- 204 Último enganche de capacidad: 'publicidad' en solicitudes_campana (acción del PROVEEDOR).
-- Gate en TRIGGER (no en RLS: WITH CHECK con funcs DEFINER es flaky bajo PostgREST; patrón robusto ya adoptado).
-- Bloquea crear/editar SOLICITUDES nuevas sin el módulo; NO toca publicación/aprobación (acción del admin),
-- ni campanas_publicitarias ya publicadas (siguen su curso hasta fecha_fin; la empresa pagó por ese período).
--
-- CLAVE (opción a): el gate aplica SOLO cuando el ejecutor es el PROVEEDOR dueño (mi_empresa_proveedor() =
-- NEW.empresa_id). Para el admin (u otro), mi_empresa_proveedor() = NULL → NULL = empresa_id es false → NO
-- aplica el gate → el admin siempre puede rechazar/procesar aunque a la empresa se le haya vencido el módulo.
--
-- Trigger NORMAL (no DEFINER): delega en private.empresa_tiene_capacidad (que ya es DEFINER = ventana de
-- lectura). Muro ético: solo lee empresa_capacidades vía el helper. ERRCODE PC014 (familia PC).

CREATE OR REPLACE FUNCTION private.trg_gate_capacidad_publicidad()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public
AS $function$
BEGIN
  -- Solo el proveedor dueño de la solicitud está sujeto al gate de capacidad; el admin procesa sin gate.
  IF public.mi_empresa_proveedor() = NEW.empresa_id THEN
    IF NOT private.empresa_tiene_capacidad(NEW.empresa_id, 'publicidad') THEN
      RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de publicidad. Contactá a soporte para activarlo.'
        USING ERRCODE = 'PC014';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_gate_capacidad_publicidad ON public.solicitudes_campana;
CREATE TRIGGER trigger_gate_capacidad_publicidad
BEFORE INSERT OR UPDATE ON public.solicitudes_campana
FOR EACH ROW EXECUTE FUNCTION private.trg_gate_capacidad_publicidad();
