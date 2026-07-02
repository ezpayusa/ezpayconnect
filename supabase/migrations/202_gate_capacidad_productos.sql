-- 202 Gate de capacidad 'productos' en TRIGGER (productos_empresa se escribe por INSERT/UPDATE directo,
-- no por RPC → el gate va en un trigger BEFORE INSERT OR UPDATE). Primer gate de capacidad en trigger.
-- Chequea la capacidad de la empresa DUEÑA del producto (NEW.empresa_id), NO de la sesión: lo que importa
-- es si ESA empresa tiene el módulo (un super_admin/flujo interno podría escribir productos de una empresa).
--
-- Trigger function NORMAL (no SECURITY DEFINER): delega en private.empresa_tiene_capacidad, que YA es DEFINER
-- y es la ventana de lectura de empresa_capacidades (cerrada). authenticated tiene USAGE en private + EXECUTE.
-- Muro ético: solo lee empresa_capacidades vía el helper. No toca agenda/pacientes.
-- ERRCODE PC010 (familia PC de capacidades; coherente con PC001-PC004 de las RPCs de activación).
--
-- Nota UPDATE: el gate corre también en UPDATE → si a una empresa se le VENCE 'productos', no puede crear
-- NI editar productos (deseado). Los productos ya creados NO se borran: quedan en la tabla, solo no editables.

CREATE OR REPLACE FUNCTION private.trg_gate_capacidad_productos()
RETURNS trigger
LANGUAGE plpgsql SET search_path = public
AS $function$
BEGIN
  IF NOT private.empresa_tiene_capacidad(NEW.empresa_id, 'productos') THEN
    RAISE EXCEPTION 'Tu empresa no tiene activado el módulo de productos. Contactá a soporte para activarlo.'
      USING ERRCODE = 'PC010';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trigger_gate_capacidad_productos ON public.productos_empresa;
CREATE TRIGGER trigger_gate_capacidad_productos
BEFORE INSERT OR UPDATE ON public.productos_empresa
FOR EACH ROW EXECUTE FUNCTION private.trg_gate_capacidad_productos();
