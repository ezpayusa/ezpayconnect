-- ============================================================================
-- Migración 263: roles comerciales + catálogos de prospección (MAQUINARIA INERTE)
-- ============================================================================
-- QUE HABILITA: primer incremento del módulo de Asesores Comerciales. Da de alta los dos roles
-- nuevos (asesor_comercial, supervisor_comercial) y los dos catálogos de datos que la 264 va a
-- referenciar por FK (tipo de prospecto y estado del pipeline).
--
-- ES INERTE: ningún código del frontend ni de las edge functions consume nada de esto todavía.
-- No hay policy nueva sobre tablas existentes, no se toca ninguna función, y los dos roles no
-- están asignados a ningún perfil. Aplicarla no cambia el comportamiento de prod.
--
-- LA 264 CONSTRUYE ENCIMA: tablas prospectos / asesores_perfil + RLS + RPCs. Los catálogos de acá
-- son el destino de sus FKs, por eso van primero y solos.
--
-- POR QUE LOS ROLES VAN A LOS DOS CATALOGOS: el proyecto arrastra dos sistemas de roles
-- desconectados. (A) perfiles.rol + roles_catalogo es la autoridad REAL (FK de perfiles.rol,
-- get_auth_user_rol, RLS y RPCs). (B) roles + usuario_roles es el RBAC legacy que consumen la
-- edge function crear-empleado y AsignacionRolesPage para el ALTA de staff. Un rol que solo vive
-- en (A) es imposible de crear por UI: exactamente lo que pasó con admin_pais, que necesitó la
-- mig 223 aparte para completarlo en (B). Acá se hace de una sola vez en las dos.
--
-- nivel=1 en public.roles (DELIBERADO, igual que admin_pais en la 223): notificar-admin usa
-- roles.nivel para la escalada jerárquica de notificaciones (los roles con nivel mayor al del
-- rol configurado reciben copia "[Seguimiento]", SIN filtro de país). Con nivel=1 los comerciales
-- NUNCA entran en esa escalada global, consistente con que están acotados a su país.
-- permisos: valor simbólico, no se lee en ningún gate real (solo badges en RolesPage).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- A.1) Roles en public.roles_catalogo — la autoridad real (FK de perfiles.rol).
--      orden 16 y 17: inmediatamente después de admin_pais (15) y antes de admin_clinica (20).
--      Ninguno de los dos órdenes está en uso hoy.
-- ----------------------------------------------------------------------------
INSERT INTO public.roles_catalogo (codigo, descripcion, ambito, es_super, es_staff_clinica, activo, orden)
VALUES
  ('asesor_comercial',     'Asesor comercial de campo (EzPay)',    'sistema', false, false, true, 16),
  ('supervisor_comercial', 'Supervisor comercial de país (EzPay)', 'sistema', false, false, true, 17)
ON CONFLICT (codigo) DO NOTHING;


-- ----------------------------------------------------------------------------
-- A.2) Roles en public.roles — catálogo legacy (crear-empleado / AsignacionRolesPage).
-- ----------------------------------------------------------------------------
INSERT INTO public.roles (nombre, descripcion, nivel, permisos)
VALUES
  ('asesor_comercial',     'Asesor comercial de campo (EzPay)',    1, '["*_comercial"]'::jsonb),
  ('supervisor_comercial', 'Supervisor comercial de país (EzPay)', 1, '["*_comercial"]'::jsonb)
ON CONFLICT (nombre) DO NOTHING;


-- ----------------------------------------------------------------------------
-- B) País obligatorio para los roles comerciales.
--    Constraint NUEVO Y SEPARADO: admin_pais_requiere_pais (mig 216) NO se toca ni se amplía.
--    Son reglas independientes; si mañana una cambia, la otra no se arrastra.
--    Verificación previa fail-closed: si hubiera filas que lo violan, la migración aborta en vez
--    de fallar en el ALTER con un mensaje opaco. (Verificado en vivo antes de escribir: 0 filas.)
--    IDEMPOTENTE: el ADD CONSTRAINT solo corre si el constraint no existe (ADD CONSTRAINT no
--    admite IF NOT EXISTS). Re-ejecutar el archivo entero no rompe nada.
--    ESTILO DEL CHECK: se usa `rol <> 'x' AND rol <> 'y'` y NO `rol NOT IN (...)`. Con NOT IN, un
--    NULL en el conjunto haría que la expresión evalúe NULL y el CHECK pasaría (los CHECK aceptan
--    NULL). Además queda textualmente paralelo a admin_pais_requiere_pais de la mig 216.
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_malas int;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'public.perfiles'::regclass
                AND conname  = 'comercial_requiere_pais') THEN
    RAISE NOTICE 'comercial_requiere_pais ya existe: nada que hacer';
    RETURN;
  END IF;

  SELECT count(*) INTO v_malas
  FROM public.perfiles
  WHERE (rol = 'asesor_comercial' OR rol = 'supervisor_comercial') AND pais_id IS NULL;

  IF v_malas > 0 THEN
    RAISE EXCEPTION 'No se puede crear comercial_requiere_pais: % perfil(es) comercial(es) sin pais_id', v_malas;
  END IF;

  ALTER TABLE public.perfiles
    ADD CONSTRAINT comercial_requiere_pais
    CHECK ((rol <> 'asesor_comercial' AND rol <> 'supervisor_comercial') OR pais_id IS NOT NULL);
END
$$;


-- ----------------------------------------------------------------------------
-- C.1) Catálogo de tipos de prospecto.
--      Los 4 primeros códigos COINCIDEN EXACTAMENTE con empresas_proveedoras.tipo
--      (CHECK vivo verificado: laboratorio_clinico, laboratorio_farmaceutico, farmacia,
--      empresa_afin). De esa coincidencia depende la conversión prospecto -> empresa de la 264:
--      el tipo se copia tal cual, sin tabla de traducción.
--      cadena_farmacias y clinica son solo de prospección (no tienen contraparte en
--      empresas_proveedoras) y por eso NO están en ese CHECK.
--      Es catálogo-dato con FK, no strings mágicos en un CHECK: se puede extender sin migración.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalogo_prospecto_tipo (
  codigo   text    PRIMARY KEY,
  etiqueta text    NOT NULL,
  orden    int     NOT NULL DEFAULT 100,
  activo   boolean NOT NULL DEFAULT true
);

COMMENT ON TABLE public.catalogo_prospecto_tipo IS
  'Catálogo de tipos de prospecto comercial (módulo de Asesores Comerciales, mig 263). '
  'Es catálogo-DATO con FK, no strings mágicos en un CHECK: se extiende con un INSERT, sin migración '
  '(y se retira con activo=false, nunca con DELETE, para no romper FKs históricas). '
  'CONTRATO: los 4 códigos que se solapan con empresas_proveedoras.tipo '
  '(laboratorio_clinico, laboratorio_farmaceutico, farmacia, empresa_afin) deben seguir coincidiendo '
  'EXACTAMENTE con ese CHECK: la conversión prospecto -> empresa copia el tipo tal cual, sin tabla de '
  'traducción. cadena_farmacias y clinica son solo de prospección y no tienen contraparte. '
  'El probe P452 del harness vigila esa coincidencia contra el CHECK vivo.';

INSERT INTO public.catalogo_prospecto_tipo (codigo, etiqueta, orden, activo)
VALUES
  ('laboratorio_farmaceutico', 'Laboratorio farmacéutico', 10, true),
  ('laboratorio_clinico',      'Laboratorio clínico',      20, true),
  ('empresa_afin',             'Empresa afín',             30, true),
  ('farmacia',                 'Farmacia',                 40, true),
  ('cadena_farmacias',         'Cadena de farmacias',      50, true),
  ('clinica',                  'Clínica',                  60, true)
ON CONFLICT (codigo) DO NOTHING;


-- ----------------------------------------------------------------------------
-- C.2) Catálogo de estados del pipeline comercial.
--      es_terminal marca los estados que cierran el prospecto (ganado / perdido).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalogo_pipeline_estado (
  codigo      text    PRIMARY KEY,
  etiqueta    text    NOT NULL,
  orden       int     NOT NULL,
  es_terminal boolean NOT NULL DEFAULT false,
  activo      boolean NOT NULL DEFAULT true
);

COMMENT ON TABLE public.catalogo_pipeline_estado IS
  'Catálogo de estados del pipeline comercial (módulo de Asesores Comerciales, mig 263). '
  'Es catálogo-DATO con FK, no strings mágicos en un CHECK: se extiende con un INSERT, sin migración '
  '(y se retira con activo=false, nunca con DELETE, para no romper FKs históricas). '
  '`orden` define la secuencia del pipeline y debe ser único; `es_terminal` marca los estados que '
  'cierran el prospecto (ganado / perdido). El probe P453 del harness vigila 6 filas, 2 terminales '
  'y órdenes sin duplicados.';

INSERT INTO public.catalogo_pipeline_estado (codigo, etiqueta, orden, es_terminal, activo)
VALUES
  ('nuevo',       'Nuevo',        10, false, true),
  ('contactado',  'Contactado',   20, false, true),
  ('demo',        'Demo',         30, false, true),
  ('negociacion', 'Negociación',  40, false, true),
  ('ganado',      'Ganado',       50, true,  true),
  ('perdido',     'Perdido',      60, true,  true)
ON CONFLICT (codigo) DO NOTHING;


-- ----------------------------------------------------------------------------
-- D) HIGIENE de privilegios en las 2 tablas nuevas.
--    Toda tabla nueva en public nace con ALL a authenticated y anon por los default privileges
--    de Supabase. Un GRANT SELECT es ADITIVO y no alcanza: hay que REVOCAR lo demás explícitamente.
--    El GRANT SELECT posterior es defensivo (deja la tabla correcta aunque los defaults cambien).
--    Escritura: SIN policy. Solo super_admin por SQL, o por una RPC SECURITY DEFINER futura.
-- ----------------------------------------------------------------------------
ALTER TABLE public.catalogo_prospecto_tipo  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogo_pipeline_estado ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.catalogo_prospecto_tipo  FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.catalogo_pipeline_estado FROM authenticated;

REVOKE ALL ON public.catalogo_prospecto_tipo  FROM anon;
REVOKE ALL ON public.catalogo_pipeline_estado FROM anon;

GRANT SELECT ON public.catalogo_prospecto_tipo  TO authenticated;
GRANT SELECT ON public.catalogo_pipeline_estado TO authenticated;

-- CREATE POLICY no admite IF NOT EXISTS: el DROP previo hace el archivo re-ejecutable.
DROP POLICY IF EXISTS catalogo_prospecto_tipo_select  ON public.catalogo_prospecto_tipo;
DROP POLICY IF EXISTS catalogo_pipeline_estado_select ON public.catalogo_pipeline_estado;

CREATE POLICY catalogo_prospecto_tipo_select
  ON public.catalogo_prospecto_tipo
  FOR SELECT
  TO authenticated
  USING (activo);

CREATE POLICY catalogo_pipeline_estado_select
  ON public.catalogo_pipeline_estado
  FOR SELECT
  TO authenticated
  USING (activo);
