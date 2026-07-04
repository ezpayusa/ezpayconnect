-- ============================================================================
-- Migración 226 (BUG A): fix typo en accion_url de la notificación 'visita_propuesta'.
-- ============================================================================
-- La ruta real registrada en App.tsx es '/proveedor/visitador/aprobar' (AdminAprobarVisitasPage),
-- pero notificar_visita_propuesta insertaba '/proveedor/visitador/admin-aprobar' (con 'admin-') →
-- "Ver detalle" abría una pantalla en blanco. Se corrige (a) el INSERT hacia adelante en el RPC y
-- (b) las filas YA insertadas con la URL vieja (data fix). El texto hardcodeado del email vive en la
-- edge notificar-email y en src/proveedor/lib/notificaciones.ts (se corrigen aparte, mismo lote).
-- notificar_visita_propuesta: cuerpo IDÉNTICO al vigente (mig 224), solo cambia el string de accion_url.
-- ============================================================================

BEGIN;

-- (a) INSERT hacia adelante: RPC con el accion_url corregido (resto del cuerpo sin cambios).
CREATE OR REPLACE FUNCTION public.notificar_visita_propuesta(p_visita_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v RECORD; rec record;
BEGIN
  SELECT empresa_id, propuesta_por INTO v FROM public.visitas_agendadas WHERE id = p_visita_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visita no encontrada' USING ERRCODE = 'PT001'; END IF;
  -- GATE: caller = creador de la visita (propuesta_por, col registrada). COALESCE fail-closed.
  IF NOT COALESCE(v.propuesta_por = auth.uid(), false) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = 'PT002'; END IF;
  -- target: admins/editores de la empresa de la visita (derivado; excluye al proponente)
  FOR rec IN SELECT id FROM public.cuentas_proveedor
             WHERE empresa_id = v.empresa_id AND activo = true AND rol_en_empresa IN ('admin','editor') AND id <> auth.uid() LOOP
    INSERT INTO public.notificaciones (usuario_id, tipo, titulo, mensaje, accion_url)
      VALUES (rec.id, 'visita_propuesta', 'Nueva visita propuesta', 'Tienes una nueva visita propuesta para revisar.', '/proveedor/visitador/aprobar');
  END LOOP;
  -- EMAIL server-side (best-effort, una sola vez por claim idempotente). El resto del cuerpo NO cambió.
  UPDATE public.visitas_agendadas SET email_propuesta_enviado = now()
    WHERE id = p_visita_id AND email_propuesta_enviado IS NULL;
  IF FOUND THEN PERFORM private.email_notificar(p_visita_id, 'propuesta'); END IF;
END;
$function$;

-- (b) Data fix: corregir las notificaciones ya insertadas con la URL vieja.
UPDATE public.notificaciones
  SET accion_url = '/proveedor/visitador/aprobar'
  WHERE accion_url = '/proveedor/visitador/admin-aprobar';

COMMIT;
