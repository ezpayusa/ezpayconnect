-- ============================================================
-- CIERRE FINAL · Bloque 1 (BD) — revokes + drop + REVOKE INSERT directo + split policies ALL→. SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ Mezcla DORMANT-safe (1a/1b) + POLICY VIVA (1c/1d = prod inmediato, l.20). Pre-requisito ya cumplido:
-- ambas ramas de hooks mergeadas (main 5b1dab1) + re-censo en vivo = 0 callers en todos los ítems.
-- Bloque 2 (stub-410 de enviar-push/enviar-notificacion) = deploy de edge APARTE (no SQL). Bloque 3 (borrar
-- helpers muertos crearNotificacion/crearNotificacionInApp) = frontend aparte.
-- ============================================================

-- 1a. REVOKE EXECUTE notificar_paciente (0 callers: citas/examen migrados a RPCs propios; receta→notificar_receta)
REVOKE EXECUTE ON FUNCTION public.notificar_paciente(integer, text, text, text, text) FROM PUBLIC, anon, authenticated;

-- 1b. DROP notificar_laboratorio (0 callers: ConsultaPage migrado a notificar_orden_lab; firma única, sin overloads)
REVOKE EXECUTE ON FUNCTION public.notificar_laboratorio(uuid, text, text, text, text) FROM PUBLIC, anon, authenticated;
DROP FUNCTION public.notificar_laboratorio(uuid, text, text, text, text);

-- 1c. REVOKE INSERT directo (0 inserts directos en frontend; todos los inserters son DEFINER → no usan el grant)
REVOKE INSERT ON public.notificaciones FROM anon, authenticated;
REVOKE INSERT ON public.notificaciones_pacientes FROM anon, authenticated;

-- 1d. SPLIT policies dual-use ALL → quitar INSERT/DELETE directos, PRESERVAR lectura + gestión legítima.
-- notificaciones: la ALL "Admin ve notificaciones de su pais" (qual real = super_admin) → SELECT + UPDATE.
-- ⚠️ MANTIENE UPDATE super_admin: useNotificacionesAdmin (panel admin-ezpay) archiva seguimientos cross-usuario
-- (UPDATE … WHERE evento_id=… es_seguimiento, sin filtrar usuario_id) → depende del super_admin; quitarlo lo rompe.
-- Solo se retira el INSERT/DELETE directo (nadie los usa; las notifs entran por RPC DEFINER).
DROP POLICY "Admin ve notificaciones de su pais" ON public.notificaciones;
CREATE POLICY "notificaciones_select_super_admin" ON public.notificaciones
  FOR SELECT USING (get_auth_user_rol() = 'super_admin'::text);
CREATE POLICY "notificaciones_update_super_admin" ON public.notificaciones
  FOR UPDATE USING (get_auth_user_rol() = 'super_admin'::text) WITH CHECK (get_auth_user_rol() = 'super_admin'::text);
-- (notificaciones_select_propia/_propias [r] + _update_propia/_propias [w] quedan INTACTAS para usuarios normales.)

-- notificaciones_pacientes: la única policy era ALL (paciente self) → split en SELECT (leer) + UPDATE (marcar leída).
DROP POLICY "Paciente ve sus notificaciones" ON public.notificaciones_pacientes;
CREATE POLICY "notif_pac_select_propia" ON public.notificaciones_pacientes
  FOR SELECT USING (paciente_id IN ( SELECT pacientes.id FROM public.pacientes WHERE pacientes.auth_user_id = auth.uid()));
CREATE POLICY "notif_pac_update_leida" ON public.notificaciones_pacientes
  FOR UPDATE USING  (paciente_id IN ( SELECT pacientes.id FROM public.pacientes WHERE pacientes.auth_user_id = auth.uid()))
            WITH CHECK (paciente_id IN ( SELECT pacientes.id FROM public.pacientes WHERE pacientes.auth_user_id = auth.uid()));
-- column-scope: RLS no acota columnas → grant a nivel columna para que el paciente SOLO toque 'leida'
-- (no mensaje/paciente_id/etc.). El webapp solo hace update({leida:true}) → seguro. DEFINER bypassa grants.
REVOKE UPDATE ON public.notificaciones_pacientes FROM anon, authenticated;
GRANT  UPDATE (leida) ON public.notificaciones_pacientes TO authenticated;
-- INSERT/DELETE directos quedan SIN policy → solo entran por los RPC DEFINER (notificar_*). Lectura + marca-leída intactas.
