-- ============================================================
-- INCREMENTO 0 (paneles) — Cerrar huecos del esquema de proveedores + CHECK de tipo
-- ------------------------------------------------------------
-- Va en la rama seguridad/rls-remediacion: son cierres de huecos RLS/fail-open,
-- viajan con el deploy de seguridad. NO rompe el flujo actual de laboratorios.
--
-- Huecos cerrados:
--   1) planes_asignaciones: política [ALL] auth.role()='authenticated' → cualquier
--      autenticado leía/escribía TODAS las asignaciones. Se scopea por DUEÑO real.
--   2) campanas_publicitarias: INSERT/UPDATE/DELETE con solo auth.uid() IS NOT NULL
--      → cualquiera publicaba/editaba/borraba anuncios. Se cierra a super_admin;
--      la publicación canónica pasa por RPC SECURITY DEFINER que revalida caller.
--   3) empresas_proveedoras.tipo: texto libre (fail-open) → CHECK al conjunto válido.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1) planes_asignaciones — scopear por dueño (médico O empresa O super_admin)
--    Tabla DUAL: suscripción de médico (medico_id) Y plan de visitador del
--    proveedor (empresa_id, actualiza visitas_usadas). El predicado cubre los 3
--    escritores legítimos verificados (usePlanes/médico, useVisitasAgendadas/
--    proveedor, useVentas+PagosProveedores/super_admin). COALESCE = NULL-safe
--    (evita el fail-open trivaluado cuando mi_empresa_proveedor()/empresa_id es NULL).
--    Filas EXCLUYENTES (verificado: 0 con ambos; 2 solo-médico, 2 solo-empresa):
--    el WITH CHECK separa por tipo de fila → un médico solo escribe SU fila de
--    médico (sin empresa_id) y un proveedor SU fila de empresa (sin medico_id);
--    así un médico NO puede forjar un empresa_id ajeno (ni viceversa). super_admin
--    sin restricción (crea suscripciones de médico / planes de empresa).
DROP POLICY IF EXISTS "Allow all authenticated asig" ON public.planes_asignaciones;   -- el hueco
DROP POLICY IF EXISTS "Proveedor ve sus planes asignados" ON public.planes_asignaciones; -- la reemplaza la nueva
DROP POLICY IF EXISTS "asig_scoped_all" ON public.planes_asignaciones;
CREATE POLICY "asig_scoped_all" ON public.planes_asignaciones
  FOR ALL TO authenticated
  USING (
       private.tiene_rol(ARRAY['super_admin'])
    OR COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
    OR COALESCE(medico_id = auth.uid(), false)
  )
  WITH CHECK (
       private.tiene_rol(ARRAY['super_admin'])
    OR (COALESCE(medico_id = auth.uid(), false) AND empresa_id IS NULL)
    OR (COALESCE(empresa_id = public.mi_empresa_proveedor(), false) AND medico_id IS NULL)
  );

-- ─────────────────────────────────────────────────────────────
-- 2) campanas_publicitarias — cerrar la ESCRITURA (la lectura de audiencia NO se toca)
--    Quitar los INSERT/UPDATE/DELETE abiertos (auth.uid() IS NOT NULL).
DROP POLICY IF EXISTS "Admin crea campanas" ON public.campanas_publicitarias;     -- INSERT abierto
DROP POLICY IF EXISTS "Admin actualiza campanas" ON public.campanas_publicitarias; -- UPDATE abierto
DROP POLICY IF EXISTS "Admin elimina campanas" ON public.campanas_publicitarias;   -- DELETE abierto
-- super_admin puede INSERTAR directo (PagosProveedoresPage / CampanasAdminContent,
-- todos bajo AdminRoute=super_admin). UPDATE/DELETE de super_admin ya los cubre la
-- política ALL existente "Admin ve campanas de su pais" (USING super_admin).
DROP POLICY IF EXISTS "campanas_superadmin_insert" ON public.campanas_publicitarias;
CREATE POLICY "campanas_superadmin_insert" ON public.campanas_publicitarias
  FOR INSERT TO authenticated
  WITH CHECK (private.tiene_rol(ARRAY['super_admin']));
-- (Se mantienen intactas: "Paciente ve campanas activas" [audiencia] y
--  "Admin ve campanas de su pais" [super_admin SELECT/UPDATE/DELETE].)

-- RPC canónica de publicación: super_admin aprueba una solicitud → publica la
-- campaña + marca la solicitud. SECURITY DEFINER + search_path='' + revalida
-- caller con COALESCE (fail-closed). Reemplaza el insert+update cliente de
-- SolicitudesCampanaPage. Copia pais_id de la solicitud (para que la audiencia
-- por país la vea — antes quedaba NULL).
CREATE OR REPLACE FUNCTION public.aprobar_solicitud_campana(
  p_solicitud_id uuid, p_notas_admin text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_s RECORD;
  v_campana_id integer;
BEGIN
  IF NOT COALESCE(private.tiene_rol(ARRAY['super_admin']), false) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin aprueba campañas';
  END IF;

  SELECT * INTO v_s FROM public.solicitudes_campana WHERE id = p_solicitud_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada';
  END IF;

  INSERT INTO public.campanas_publicitarias
    (titulo, descripcion, tipo, imagen_url, link_url, fecha_inicio, fecha_fin,
     activa, condicion_filtro, genero_filtro, edad_min, edad_max, pais_id)
  VALUES
    (v_s.titulo, v_s.descripcion, v_s.tipo, v_s.imagen_url, v_s.link_url,
     v_s.fecha_inicio, v_s.fecha_fin, true, v_s.condicion_filtro, v_s.genero_filtro,
     v_s.edad_min, v_s.edad_max, v_s.pais_id)
  RETURNING id INTO v_campana_id;

  UPDATE public.solicitudes_campana
    SET estado = 'publicada', notas_admin = COALESCE(p_notas_admin, notas_admin)
    WHERE id = p_solicitud_id;

  RETURN v_campana_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.aprobar_solicitud_campana(uuid,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.aprobar_solicitud_campana(uuid,text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 3) empresas_proveedoras.tipo — CHECK al catálogo válido (cierra fail-open de texto libre)
--    Pre-vuelo verificado: 0 filas con tipo fuera del conjunto.
ALTER TABLE public.empresas_proveedoras
  DROP CONSTRAINT IF EXISTS empresas_proveedoras_tipo_check;
ALTER TABLE public.empresas_proveedoras
  ADD CONSTRAINT empresas_proveedoras_tipo_check
  CHECK (tipo IN ('laboratorio_clinico','laboratorio_farmaceutico','farmacia','empresa_afin'));
