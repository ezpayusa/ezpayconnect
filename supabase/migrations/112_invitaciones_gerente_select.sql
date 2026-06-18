-- ============================================================
-- Ola 2 · invitaciones_visitador: el Gerente ve las invitaciones de SU empresa (SEGURIDAD, lectura)
-- ------------------------------------------------------------
-- ⚠️ PAQUETE DE REVISIÓN — cambio de LECTURA viva (nota 20). Probes red-first P299–P303.
--
-- HOY: SELECT policy exige rol_en_empresa IN ('admin','editor') → el Gerente queda fuera.
-- Rol autoritativo = cuentas_proveedor.rol_en_empresa vía public.mi_rol_proveedor() (lección 4;
-- NO perfiles.rol='gerente' que es staff de clínica). Tenant = empresa_id (sin país).
-- Cardinalidad confirmada 1:1 (un usuario en ≤1 empresa) → forma con helpers (mi_empresa_proveedor
-- =empresa_id AND mi_rol_proveedor()=ANY(array)), fail-closed, sin subquery cruda (lección 12/36).
-- 'editor' = 0 filas (rol muerto) → se quita. Roles que ven = {admin, gerente_farmacia, gerente}.
--
-- EXTENSIÓN SOLO DE LECTURA: la INSERT policy (invitaciones_insert_admin) NO se toca → el Gerente
-- NO crea; no hay UPDATE policy → no acepta/usa (eso sigue por edge function DEFINER).
-- OR-trap (lección 41): se REEMPLAZA la única SELECT policy (no se añade una segunda) → el set
-- OReado = exactamente {admin,gerente_farmacia,gerente} de su empresa; no-proveedor/anon → fail-closed 0.
-- ============================================================

DROP POLICY IF EXISTS invitaciones_select_admin ON public.invitaciones_visitador;

CREATE POLICY invitaciones_select_admin ON public.invitaciones_visitador
  FOR SELECT TO authenticated
  USING (
    COALESCE(public.mi_empresa_proveedor() = empresa_id, false)                       -- tenant, fail-closed
    AND COALESCE(public.mi_rol_proveedor() = ANY (ARRAY['admin','gerente_farmacia','gerente']), false)  -- rol gestor
  );
