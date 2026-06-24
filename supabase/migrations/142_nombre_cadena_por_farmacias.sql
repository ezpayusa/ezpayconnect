-- ============================================================
-- 142 · Fix nombre-de-cadena en el selector del médico (RPC de enriquecimiento) — DORMANT hasta el deploy
-- ------------------------------------------------------------
-- El médico NO lee empresas_proveedoras (RLS → 0 filas) → el embed nombre_empresa del selector (3.3) viene
-- null → la agrupación cae al fallback farmacia.nombre. Este RPC DEFINER expone SOLO (farmacia_id, nombre_empresa)
-- de las farmacias que el médico YA ve (ids de su búsqueda) — sin abrir la RLS de empresas_proveedoras y sin
-- exponer NINGUNA columna de contacto (ruc_nit/email_contacto/telefono/direccion). search_path='' + calificado.
-- Gate: médico/super_admin (mismo universo que farm_med_disp_medico). No-médico → 0 filas (fail-closed). anon revocado.
-- Acotado a los ids recibidos: no permite barrer el padrón; aun con ids inventados solo devuelve el nombre de
-- cadena (marca, baja sensibilidad) — nunca contacto.
-- ============================================================
CREATE OR REPLACE FUNCTION public.nombre_cadena_por_farmacias(p_farmacia_ids integer[])
RETURNS TABLE(farmacia_id integer, nombre_empresa text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  -- Gate: solo médico/super_admin. No-médico (incl. proveedor/paciente autenticado) → 0 filas (fail-closed).
  IF NOT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid() AND p.rol = ANY (ARRAY['medico','super_admin'])
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT f.id, e.nombre_empresa            -- SOLO id + nombre_empresa; NUNCA ruc_nit/email_contacto/telefono/direccion
    FROM public.farmacias f
    JOIN public.empresas_proveedoras e ON e.id = f.empresa_id
    WHERE f.id = ANY (p_farmacia_ids)
      AND f.empresa_id IS NOT NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.nombre_cadena_por_farmacias(integer[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.nombre_cadena_por_farmacias(integer[]) TO authenticated;
