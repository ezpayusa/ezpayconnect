-- ============================================================
-- Hardening INSERT (opción-2) · visitas_agendadas — cuenta_proveedor_id ∈ empresa de la visita. SEGURIDAD.
-- ------------------------------------------------------------
-- ⚠️ POLICY VIVA (no dormant): el ALTER cambia prod de inmediato (l.20). Cierra la atribución a NIVEL FILA:
-- el WITH CHECK actual gatea empresa_id pero NO cuenta_proveedor_id (col caller-libre) → un caller de empresa A
-- podía crear una visita atribuida a una cuenta de empresa B. La opción-1 (notificar_visita_resultado) ya cierra
-- el NOTIFY cross-empresa (skip), pero la FILA con cuenta ajena sí se creaba → esto lo cierra el INSERT.
-- NO toca la asignación intra-empresa a colegas (legítima: admin asigna a un visitador de SU empresa).
--
-- Término CONJUNTIVO (AND sobre el check existente EXACTO, l.33). Sin rama NULL (cuenta_proveedor_id NOT NULL).
-- Helper DEFINER OBLIGATORIO (l.12/36): un EXISTS crudo en el WITH CHECK se evaluaría con la RLS del caller →
-- cuentas_proveedor de otra empresa no es visible → falso-negativo que ROMPERÍA inserts legítimos. El DEFINER lo evita.
-- ============================================================

CREATE OR REPLACE FUNCTION private.cuenta_en_empresa(p_cuenta uuid, p_empresa uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.cuentas_proveedor WHERE id = p_cuenta AND empresa_id = p_empresa);
$function$;
REVOKE EXECUTE ON FUNCTION private.cuenta_en_empresa(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.cuenta_en_empresa(uuid, uuid) TO authenticated;

-- Reproduce el término existente EXACTO (empresa_id ∈ empresas del caller) y SOLO AND-ea el nuevo.
ALTER POLICY "Proveedor crea visitas de su empresa" ON public.visitas_agendadas
  WITH CHECK (
    (empresa_id IN ( SELECT cuentas_proveedor.empresa_id
       FROM cuentas_proveedor
      WHERE ((cuentas_proveedor.id = auth.uid()) AND (cuentas_proveedor.activo = true) AND (cuentas_proveedor.rol_en_empresa = ANY (ARRAY['admin'::text, 'editor'::text, 'visitador_medico'::text])))))
    AND private.cuenta_en_empresa(cuenta_proveedor_id, empresa_id)
  );
