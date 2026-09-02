-- ============================================================================
-- Migración 264: módulo comercial — ESTRUCTURA Y LECTURA (MAQUINARIA INERTE)
-- ============================================================================
-- QUE HABILITA: las 3 tablas del módulo de Asesores Comerciales (asesores_perfil, prospectos,
-- prospecto_contactos), el chokepoint de visibilidad `private.asesores_a_cargo()`, el guard de
-- integridad de la jerarquía asesor→supervisor, y la RLS de LECTURA de las 3 tablas.
--
-- SIGUE SIENDO INERTE: las tablas nacen VACÍAS, ningún frontend ni edge function las consume, y
-- NINGUNA escritura pasa por policy. Aplicarla no cambia el comportamiento de prod.
--
-- LO QUE ESTA MIGRACIÓN **NO** TRAE, A PROPÓSITO: cero policies de INSERT/UPDATE/DELETE. La
-- escritura llega en la 265 por RPC SECURITY DEFINER. Con `REVOKE INSERT/UPDATE/DELETE` + cero
-- policies, hoy la única forma de escribir estas tablas es como owner (postgres/service_role).
-- Eso es deliberado: la superficie de escritura se diseña entera de una vez, no a pedazos.
--
-- CONSTRUYE SOBRE LA 263: los catálogos catalogo_prospecto_tipo / catalogo_pipeline_estado y los
-- roles asesor_comercial / supervisor_comercial ya están vivos. Esta migración los referencia por
-- FK; si la 263 no estuviera aplicada, el ADD CONSTRAINT falla (fail-closed, correcto).
--
-- FAMILIA DE ERRCODE: **PA** (PA001–PA007). Elegida contra el censo vivo de `pg_proc.prosrc`
-- (public+private) del 2026-09-02: en uso están 22023, 23505, 28000, 42501, P0001, P0002 y las
-- familias PC, PP, PR, PT, PV. PA estaba libre y queda reservada para el módulo comercial.
--
-- IDEMPOTENTE de punta a punta: CREATE TABLE IF NOT EXISTS, DO+pg_constraint para cada constraint
-- nombrado (ADD CONSTRAINT no admite IF NOT EXISTS), DROP POLICY IF EXISTS antes de cada CREATE
-- POLICY (CREATE POLICY tampoco lo admite), CREATE OR REPLACE en funciones, DROP TRIGGER IF EXISTS
-- antes del CREATE TRIGGER. Sin BEGIN/COMMIT: el archivo se aplica con `supabase db query -f`,
-- que ya lo envuelve en una transacción.
-- ============================================================================


-- ============================================================================
-- A) HELPERS (esquema private)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A.1) Normalización del nombre de prospecto — dedup por país.
--
-- IMMUTABLE es OBLIGATORIO, no cosmético: la usa la columna GENERATED prospectos.nombre_norm, y
-- Postgres solo acepta funciones IMMUTABLE ahí.
--
-- ANTI-DRIFT (lección de la 088/089 con norm_med_nombre): una vez que existan filas, esta función
-- NO se puede "arreglar" con un CREATE OR REPLACE. Los valores de nombre_norm quedan
-- MATERIALIZADOS (STORED) y el UNIQUE está construido sobre ellos: cambiar el cuerpo deja los
-- viejos calculados con la regla vieja y los nuevos con la nueva, y el UNIQUE deja de significar lo
-- que dice. Para cambiar la regla hay que DROP UNIQUE → DROP COLUMN → re-ADD COLUMN → re-CREATE
-- UNIQUE, como hizo la 088. Mientras las tablas estén vacías (hoy) el cambio es libre; después no.
--
-- ORDEN de la normalización (documentado, importa):
--   1. translate acentos→base (á→a, ñ→n, ç→c) y lower()
--   2. conectores -/\&+ → ESPACIO  (no se borran: "Coca-Cola" -> "coca cola", no "cocacola")
--   3. puntuación pura .,;:()[]{}"'`´¡!¿?*#@_ → se BORRA  ("S.A." -> "sa", "Fármaco," -> "farmaco")
--   4. colapsar espacios y btrim   (va al final: los pasos 2 y 3 pueden generar espacios dobles)
--
-- LIMITACIÓN CONOCIDA Y ACEPTADA: 'S.A.' normaliza a 'sa' pero 'S. A.' (con espacio interno)
-- normaliza a 's a' — no colisionan. Pegar letras sueltas sería una regla más agresiva que puede
-- fusionar razones sociales distintas. El dedup duro (UNIQUE) cubre el caso frecuente; el fuzzy
-- ("¿quisiste decir…?") es trabajo del RPC de alta de la 265, no del constraint.
--
-- NO ES SECURITY DEFINER, a diferencia del resto de los helpers del módulo. La función no toca
-- ninguna tabla: es puro texto. DEFINER acá no habilitaría nada que el caller no pueda hacer ya, y
-- una función DEFINER de más es superficie extra a cambio de nada. Corre con los privilegios de
-- quien inserta, que es lo correcto.
--
-- EL `SET search_path = ''` SÍ SE QUEDA, aunque no haya DEFINER: el cuerpo referencia btrim,
-- regexp_replace, lower y translate, y no queremos que la resolución de esos nombres dependa del
-- search_path del caller. Con search_path vacío igual resuelven, porque pg_catalog está siempre
-- implícito. Costo asumido: el SET bloquea el inlining y agrega un save/restore de GUC por fila.
-- Es aceptable porque solo se evalúa en INSERT/UPDATE de prospectos (volumen de prospección, no de
-- transacciones). Es la única diferencia con norm_med_nombre (088), que no fija search_path.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.norm_prospecto_nombre(p_nombre text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = ''
AS $function$
  SELECT btrim(
    regexp_replace(                                        -- 4) colapsa espacios
      regexp_replace(                                      -- 3) puntuación pura -> se borra
        regexp_replace(                                    -- 2) conectores -> espacio
          lower(translate(p_nombre,                        -- 1) minúsculas sin acentos
            'áéíóúàèìòùâêîôûäëïöñçüÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÄËÏÖÑÇÜ',
            'aeiouaeiouaeiouaeioncuAEIOUAEIOUAEIOUAEIONCU')),
        '[-/\\&+]', ' ', 'g'),
      '[.,;:()\[\]{}"''`´¡!¿?*#@_]', '', 'g'),
    '\s+', ' ', 'g')
  );
$function$;

REVOKE EXECUTE ON FUNCTION private.norm_prospecto_nombre(text) FROM PUBLIC, anon;
-- Al no ser DEFINER, estos GRANT son todavía MÁS necesarios: una columna GENERATED se evalúa con los
-- privilegios de QUIEN inserta, no del owner de la tabla, y acá tampoco hay un owner que preste los
-- suyos. Sin el GRANT a service_role, un INSERT desde una edge function (que usa la service key)
-- fallaría con "permission denied for function". Es el mismo razonamiento que documenta la 088.
GRANT EXECUTE ON FUNCTION private.norm_prospecto_nombre(text) TO authenticated, service_role;

COMMENT ON FUNCTION private.norm_prospecto_nombre(text) IS
  'Normaliza el nombre de un prospecto para el dedup por país (mig 264). IMMUTABLE porque la usa la '
  'columna GENERATED prospectos.nombre_norm. NO es SECURITY DEFINER a propósito: no toca ninguna tabla, '
  'así que DEFINER sería superficie extra por nada; conserva SET search_path='''' para no depender del '
  'search_path del caller al resolver btrim/regexp_replace/lower/translate. '
  'ANTI-DRIFT: con filas cargadas NO se cambia con CREATE OR '
  'REPLACE — los valores están STORED y el UNIQUE se construyó sobre ellos; hay que DROP UNIQUE → DROP '
  'COLUMN → re-ADD → re-CREATE UNIQUE (ver mig 088/089). Limitación aceptada: "S.A."->"sa" pero '
  '"S. A."->"s a" (no colisionan); el fuzzy es trabajo del RPC de alta de la 265.';


-- ----------------------------------------------------------------------------
-- A.2) EL CHOKEPOINT DEL MÓDULO — quién ve la cartera de quién.
--
-- SECURITY DEFINER NO ES OPCIONAL ACÁ, por dos razones distintas:
--   (1) ANTI-RECURSIÓN: esta función lee public.asesores_perfil y se usa DENTRO de la policy de
--       public.asesores_perfil. Sin DEFINER, el SELECT interno vuelve a evaluar la policy, que
--       vuelve a llamar a la función → recursión infinita. Es exactamente el problema que la
--       mig 031 resolvió para perfiles con get_auth_user_rol().
--   (2) CORRECTITUD: un chokepoint que lee a través de la RLS del caller devuelve un conjunto que
--       depende de lo que el caller ya podía ver — o sea, no decide nada.
--
-- FAIL-CLOSED POR CONSTRUCCIÓN, no por negación: no hay ningún `IF rol NOT IN (...) THEN RETURN`.
-- La función solo emite filas dentro de una rama de rol RECONOCIDA; el camino por defecto es el
-- `RETURN` final sin filas. Un rol nuevo que nadie contempló no hereda visibilidad por accidente:
-- hay que agregarle su rama a propósito.
--
-- super_admin va PRIMERO y corta: es la rama más barata y evita evaluar mi_pais() de más.
--
-- OJO con el uso en policies: SIEMPRE con EXISTS (SELECT 1 FROM private.asesores_a_cargo() a
-- WHERE a = <col>), NUNCA con `<col> IN (SELECT ...)`. Con IN, un NULL en el conjunto vuelve la
-- expresión NULL en vez de false y el gate se saltea entero.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.asesores_a_cargo()
RETURNS SETOF uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rol text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;                       -- sin sesión -> conjunto vacío
  END IF;

  SELECT p.rol INTO v_rol FROM public.perfiles p WHERE p.id = v_uid;

  IF v_rol = 'super_admin' THEN
    RETURN QUERY SELECT ap.id FROM public.asesores_perfil ap;
    RETURN;
  END IF;

  IF v_rol = 'admin_pais' THEN
    RETURN QUERY SELECT ap.id FROM public.asesores_perfil ap WHERE ap.pais_id = private.mi_pais();
    RETURN;
  END IF;

  IF v_rol = 'supervisor_comercial' THEN
    -- su equipo + él mismo (un supervisor también tiene cartera propia)
    RETURN QUERY
      SELECT ap.id FROM public.asesores_perfil ap WHERE ap.supervisor_id = v_uid
      UNION
      SELECT v_uid;
    RETURN;
  END IF;

  IF v_rol = 'asesor_comercial' THEN
    RETURN QUERY SELECT v_uid;
    RETURN;
  END IF;

  RETURN;                         -- cualquier otro rol -> conjunto vacío
END
$function$;

REVOKE EXECUTE ON FUNCTION private.asesores_a_cargo() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.asesores_a_cargo() TO authenticated;

COMMENT ON FUNCTION private.asesores_a_cargo() IS
  'CHOKEPOINT ÚNICO de visibilidad del módulo comercial (mig 264): devuelve los asesores cuya cartera '
  'puede ver el caller. super_admin=todos; admin_pais=los de su país; supervisor_comercial=su equipo + '
  'él mismo; asesor_comercial=solo él; cualquier otro rol o sin sesión=CONJUNTO VACÍO (fail-closed por '
  'construcción: solo emite filas dentro de una rama de rol reconocida). '
  'CONTRATO: toda pantalla, vista o RPC nueva del módulo DEBE consumir esta función en vez de escribir '
  'su propio predicado de visibilidad — si el criterio cambia, se cambia acá y en ningún otro lado. '
  'Se usa SIEMPRE con EXISTS(...), nunca con IN(...): un NULL en el conjunto saltearía el gate. '
  'Es SECURITY DEFINER por anti-recursión (se usa en la policy de la tabla que lee, lección mig 031) y '
  'porque un chokepoint que lee a través de la RLS del caller no decide nada. '
  'El término de país en las policies es ADICIONAL y CONJUNTIVO: doble candado, no redundancia.';


-- ----------------------------------------------------------------------------
-- A.3) ¿El caller es del módulo comercial?
--      `rol = 'x' OR rol = 'y'` y NO `rol IN (...)`, igual que el CHECK de la 263: con IN, un NULL
--      vuelve la expresión NULL. COALESCE(...,false) porque el helper se usa en gates.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.es_comercial()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE(
    (SELECT p.rol = 'asesor_comercial' OR p.rol = 'supervisor_comercial'
       FROM public.perfiles p WHERE p.id = auth.uid()),
    false);
$function$;

REVOKE EXECUTE ON FUNCTION private.es_comercial() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.es_comercial() TO authenticated;

COMMENT ON FUNCTION private.es_comercial() IS
  'true si el caller tiene rol asesor_comercial o supervisor_comercial (mig 264). COALESCE(...,false): '
  'nunca devuelve NULL, para poder usarse directo en un gate sin abrirlo por lógica de tres valores.';


-- ----------------------------------------------------------------------------
-- A.4) private.prospecto_visible(uuid) VIVÍA ACÁ Y SE MOVIÓ A C.3, después de las tablas.
--
-- MOTIVO (lección del intento de aplicación que falló con 42P01): es LANGUAGE **sql**, y Postgres
-- valida el cuerpo de una función SQL AL CREARLA. Referencia public.prospectos, que nace en la
-- sección B, así que acá el CREATE moría con 'relation "public.prospectos" does not exist'.
--
-- Por qué asesores_a_cargo() SÍ puede quedarse en A aunque también lea public.asesores_perfil: es
-- **plpgsql**, y ahí el cuerpo NO se valida al crear — cada sentencia se planifica en su primera
-- ejecución. O sea: el orden de creación importa solo para las funciones sql.
-- ----------------------------------------------------------------------------


-- ============================================================================
-- B) TABLAS
--    Las 3 llevan país (directo, o heredado del prospecto por FK) y ON DELETE RESTRICT en TODO eje
--    de aislamiento: un DELETE que arrastre en cascada es un borrado de evidencia comercial y una
--    forma silenciosa de mover filas entre países. Se prefiere el error.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- B.1) asesores_perfil — extensión 1:1 de perfiles para el rol comercial.
--      El PK ES el id del perfil (no hay id propio): hace el 1:1 estructural, sin trigger que lo
--      vigile ni posibilidad de dos filas para el mismo usuario.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asesores_perfil (
  id                 uuid        PRIMARY KEY,
  pais_id            uuid        NOT NULL,
  supervisor_id      uuid        NULL,
  codigo_asesor      text        NOT NULL,
  cargo              text,
  telefono           text,
  celular            text,
  territorio         text,
  fecha_ingreso      date,
  bio                text,
  foto_path          text,       -- bucket PRIVADO (uso interno del backoffice)
  foto_publica_path  text,       -- bucket público de la tarjeta comercial; OPT-IN explícito del asesor
  activo             boolean     NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asesores_perfil'::regclass AND conname='asesores_perfil_id_fkey') THEN
    ALTER TABLE public.asesores_perfil ADD CONSTRAINT asesores_perfil_id_fkey
      FOREIGN KEY (id) REFERENCES public.perfiles(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asesores_perfil'::regclass AND conname='asesores_perfil_pais_id_fkey') THEN
    ALTER TABLE public.asesores_perfil ADD CONSTRAINT asesores_perfil_pais_id_fkey
      FOREIGN KEY (pais_id) REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asesores_perfil'::regclass AND conname='asesores_perfil_supervisor_id_fkey') THEN
    ALTER TABLE public.asesores_perfil ADD CONSTRAINT asesores_perfil_supervisor_id_fkey
      FOREIGN KEY (supervisor_id) REFERENCES public.perfiles(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asesores_perfil'::regclass AND conname='asesores_perfil_pais_codigo_uniq') THEN
    ALTER TABLE public.asesores_perfil ADD CONSTRAINT asesores_perfil_pais_codigo_uniq
      UNIQUE (pais_id, codigo_asesor);
  END IF;
  -- No auto-supervisión. El caso "me pongo de supervisor de mí mismo" NO lo cubre el trigger de
  -- jerarquía (ahí el supervisor sería válido en rol, país y estado): lo corta este CHECK.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.asesores_perfil'::regclass AND conname='asesores_perfil_no_autosupervision') THEN
    ALTER TABLE public.asesores_perfil ADD CONSTRAINT asesores_perfil_no_autosupervision
      CHECK (supervisor_id IS NULL OR supervisor_id <> id);
  END IF;
END $$;

COMMENT ON TABLE public.asesores_perfil IS
  'Extensión 1:1 de public.perfiles para los roles comerciales (mig 264, módulo de Asesores '
  'Comerciales). El PK ES el id del perfil: el 1:1 es estructural, no vigilado por trigger. '
  'MAQUINARIA INERTE: nace vacía, sin UI y SIN NINGUNA policy de escritura — la escritura llega en la '
  '265 por RPC SECURITY DEFINER. La jerarquía supervisor→asesor la valida el trigger '
  'trg_asesores_perfil_guard_supervisor (ERRCODEs PA001–PA005); el candado de país de esa jerarquía '
  '(PA003) es lo que impide que un supervisor de otro país se vuelva vector de fuga. '
  'foto_path es bucket PRIVADO (interno); foto_publica_path es el bucket público de la tarjeta '
  'comercial y es OPT-IN explícito del asesor — no se llena por defecto.';


-- ----------------------------------------------------------------------------
-- B.2) prospectos
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.prospectos (
  id                     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  pais_id                uuid        NOT NULL,
  asesor_id              uuid        NOT NULL,
  tipo                   text        NOT NULL,
  estado_pipeline        text        NOT NULL DEFAULT 'nuevo',
  nombre                 text        NOT NULL,
  nombre_norm            text        GENERATED ALWAYS AS (private.norm_prospecto_nombre(nombre)) STORED,
  direccion              text,
  lat                    numeric(10,8),
  lng                    numeric(11,8),
  empresa_proveedora_id  uuid        NULL,
  motivo_perdida         text,
  notas                  text,
  creado_por             uuid        NOT NULL,
  activo                 boolean     NOT NULL DEFAULT true,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

-- Red de seguridad de idempotencia: si la tabla ya existiera SIN la columna generada (drift), se
-- agrega acá. Con la columna presente es un no-op.
ALTER TABLE public.prospectos
  ADD COLUMN IF NOT EXISTS nombre_norm text GENERATED ALWAYS AS (private.norm_prospecto_nombre(nombre)) STORED;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_pais_id_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_pais_id_fkey
      FOREIGN KEY (pais_id) REFERENCES public.configuracion_pais(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_asesor_id_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_asesor_id_fkey
      FOREIGN KEY (asesor_id) REFERENCES public.perfiles(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_tipo_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_tipo_fkey
      FOREIGN KEY (tipo) REFERENCES public.catalogo_prospecto_tipo(codigo) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_estado_pipeline_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_estado_pipeline_fkey
      FOREIGN KEY (estado_pipeline) REFERENCES public.catalogo_pipeline_estado(codigo) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_empresa_proveedora_id_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_empresa_proveedora_id_fkey
      FOREIGN KEY (empresa_proveedora_id) REFERENCES public.empresas_proveedoras(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_creado_por_fkey') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_creado_por_fkey
      FOREIGN KEY (creado_por) REFERENCES public.perfiles(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_nombre_no_vacio') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_nombre_no_vacio
      CHECK (nombre = btrim(nombre) AND length(btrim(nombre)) > 0);
  END IF;
  -- DEDUP: el mismo laboratorio no se carga dos veces en el mismo país. Es por PAÍS, no global:
  -- una cadena regional es un prospecto legítimo y distinto en cada país.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospectos'::regclass AND conname='prospectos_pais_nombrenorm_uniq') THEN
    ALTER TABLE public.prospectos ADD CONSTRAINT prospectos_pais_nombrenorm_uniq
      UNIQUE (pais_id, nombre_norm);
  END IF;
END $$;

COMMENT ON TABLE public.prospectos IS
  'Prospectos del pipeline comercial (mig 264, módulo de Asesores Comerciales). MAQUINARIA INERTE: '
  'nace vacía, sin UI y SIN NINGUNA policy de escritura — la escritura llega en la 265 por RPC '
  'SECURITY DEFINER. Visibilidad: private.asesores_a_cargo() (chokepoint) Y pais_id = private.mi_pais(), '
  'conjuntivo. nombre_norm es GENERATED STORED sobre private.norm_prospecto_nombre y sostiene el UNIQUE '
  '(pais_id, nombre_norm): cambiar esa función con filas cargadas rompe el significado del UNIQUE '
  '(ver mig 088/089). '
  'COHERENCIA DE PAÍS: el trigger trg_prospectos_guard_pais (PA006) obliga a que pais_id sea IGUAL al '
  'país de la ficha del asesor_id. La incoherencia es IMPOSIBLE en la base, no solo improbable por la '
  'aplicación: vale para el owner, para service_role y para un fix manual por SQL, no solo para la RPC. '
  'Efecto de borde deliberado: un prospecto solo puede pertenecer a un asesor CON ficha en '
  'asesores_perfil (sin ficha, la lectura del país es NULL y PA006 corta). El RPC de alta de la 265 '
  'igual derivará pais_id del asesor server-side, pero como CONVENIENCIA, no como control. '
  'El probe P477 es el negativo de PA006.';


-- ----------------------------------------------------------------------------
-- B.3) prospecto_contactos — personas dentro del prospecto.
--      No lleva pais_id propio: lo hereda del prospecto por FK RESTRICT. Duplicarlo acá sería una
--      segunda fuente de verdad del país, que es justo lo que hay que evitar.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.prospecto_contactos (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  prospecto_id  uuid        NOT NULL,
  nombre        text        NOT NULL,
  puesto        text,
  telefono      text,
  celular       text,
  email         text,
  es_decisor    boolean     NOT NULL DEFAULT false,
  notas         text,
  activo        boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospecto_contactos'::regclass AND conname='prospecto_contactos_prospecto_id_fkey') THEN
    ALTER TABLE public.prospecto_contactos ADD CONSTRAINT prospecto_contactos_prospecto_id_fkey
      FOREIGN KEY (prospecto_id) REFERENCES public.prospectos(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.prospecto_contactos'::regclass AND conname='prospecto_contactos_nombre_no_vacio') THEN
    ALTER TABLE public.prospecto_contactos ADD CONSTRAINT prospecto_contactos_nombre_no_vacio
      CHECK (nombre = btrim(nombre) AND length(btrim(nombre)) > 0);
  END IF;
END $$;

COMMENT ON TABLE public.prospecto_contactos IS
  'Contactos (personas) dentro de un prospecto comercial (mig 264). MAQUINARIA INERTE: nace vacía, sin '
  'UI y SIN NINGUNA policy de escritura — la escritura llega en la 265 por RPC SECURITY DEFINER. '
  'NO lleva pais_id propio a propósito: lo hereda del prospecto por FK RESTRICT; duplicarlo sería una '
  'segunda fuente de verdad del país. Su visibilidad delega en private.prospecto_visible(prospecto_id), '
  'que replica el predicado de prospectos — no una subquery cruda, que quedaría atada a cualquier '
  'policy futura de prospectos.';


-- ============================================================================
-- C) TRIGGER DE INTEGRIDAD DE LA JERARQUÍA — la pieza de seguridad de esta migración
--
-- POR QUÉ ES SECURITY DEFINER (decidido, no heredado):
-- El guard lee public.perfiles y public.asesores_perfil, y las dos tienen RLS. Si NO fuera DEFINER,
-- esas lecturas correrían bajo la RLS del caller y el veredicto del guard dependería de lo que el
-- caller ALCANZA A VER, no de los datos:
--   - La RLS de asesores_perfil es el propio chokepoint: un supervisor NO ve a los asesores de otro
--     supervisor. Un alta legítima hecha por alguien que no ve la fila del supervisor daría PA002
--     ("no tiene ficha o está inactivo") — el guard estaría informando un dato falso.
--   - Peor: PA003 compara el país del supervisor. Con la fila invisible, esa lectura es NULL. Acá se
--     escribió `IS DISTINCT FROM` (NULL => corta, fail-closed); con un `<>` normal habría sido
--     NULL => el IF no se cumple => se saltea la validación => FAIL-OPEN silencioso. Un guard que
--     valida contra lecturas filtradas por RLS es exactamente la forma en que aparece ese fail-open.
-- DEFINER no abre ninguna superficie de lectura: la función no devuelve filas ni las expone — solo
-- RAISE o RETURN NEW. Con search_path='' y todo calificado, tampoco es hijackable.
--
-- ORDEN DE LAS VALIDACIONES (importa para leer los probes): PA005 y PA007 se evalúan ANTES del corte
-- por `supervisor_id IS NULL`, así que una fila cuyo propio rol es supervisor_comercial Y que trae
-- supervisor_id da PA005 aunque el supervisor apuntado también fuera inválido. Es la lección del
-- bloque 262: cuando dos controles pueden disparar, el que corre primero enmascara al otro.
--
-- PA007 — POR QUÉ EXISTE (agujero real, cerrado acá):
-- PA003 valida la fila QUE CAMBIA, pero no revalidaba a los subordinados cuando cambiaba el país DEL
-- SUPERVISOR. La secuencia era: armo la jerarquía correcta en GT (pasa PA003) y después hago
-- `UPDATE asesores_perfil SET pais_id = <SV> WHERE id = <supervisor>`. El trigger disparaba sobre la
-- fila del supervisor, que no tiene supervisor_id, y salía por el `RETURN NEW` del corte por NULL sin
-- validar nada — dejando fichas subordinadas apuntando a un supervisor de otro país, exactamente el
-- estado que PA003 existe para impedir, alcanzado por la puerta de al lado.
-- El cierre es FAIL-CLOSED y simple: si cambia el país de una ficha que tiene subordinados, se
-- rechaza. Reasignar un equipo es una operación deliberada, no un efecto colateral de mover a alguien
-- de país. La alternativa (arrastrar a los subordinados al país nuevo en cascada) movería datos de
-- tenant sin que nadie lo pida, que es peor.
-- ============================================================================
CREATE OR REPLACE FUNCTION private.guard_supervisor_asesor()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_rol_self    text;
  v_rol_sup     text;
  v_hay_fila    boolean := false;
  v_pais_sup    uuid;
  v_activo_sup  boolean;
  v_sup_del_sup uuid;
  v_subs        bigint;
BEGIN
  -- (PA005) un supervisor no cuelga de nadie: la jerarquía es de 2 niveles.
  SELECT p.rol INTO v_rol_self FROM public.perfiles p WHERE p.id = NEW.id;
  IF v_rol_self = 'supervisor_comercial' AND NEW.supervisor_id IS NOT NULL THEN
    RAISE EXCEPTION
      'PA005: % tiene rol supervisor_comercial, por lo tanto supervisor_id debe ser NULL (jerarquía de 2 niveles)',
      NEW.id USING ERRCODE = 'PA005';
  END IF;

  -- (PA007) no se cambia el país de una ficha que tiene subordinados. Va ANTES del corte por
  -- supervisor_id IS NULL a propósito: el caso peligroso es justamente el de un SUPERVISOR (que tiene
  -- supervisor_id NULL y por eso salía por ese RETURN sin validar nada) al que le mueven el país
  -- dejando a su equipo apuntando cross-país. Ver el bloque de comentarios de arriba.
  IF TG_OP = 'UPDATE' AND NEW.pais_id IS DISTINCT FROM OLD.pais_id THEN
    SELECT count(*) INTO v_subs FROM public.asesores_perfil ap WHERE ap.supervisor_id = NEW.id;
    IF v_subs > 0 THEN
      RAISE EXCEPTION
        'PA007: % tiene % asesor(es) a cargo; desvinculalos antes de cambiarle el país (de % a %)',
        NEW.id, v_subs, COALESCE(OLD.pais_id::text,'(nulo)'), COALESCE(NEW.pais_id::text,'(nulo)')
        USING ERRCODE = 'PA007';
    END IF;
  END IF;

  IF NEW.supervisor_id IS NULL THEN
    RETURN NEW;                   -- asesor sin supervisor asignado: válido
  END IF;

  -- (PA001) el supervisor existe y su rol es EXACTAMENTE supervisor_comercial
  SELECT p.rol INTO v_rol_sup FROM public.perfiles p WHERE p.id = NEW.supervisor_id;
  IF v_rol_sup IS DISTINCT FROM 'supervisor_comercial' THEN
    RAISE EXCEPTION
      'PA001: supervisor_id % no es un supervisor_comercial (rol=%)',
      NEW.supervisor_id, COALESCE(v_rol_sup, '(perfil inexistente)') USING ERRCODE = 'PA001';
  END IF;

  -- (PA002) el supervisor tiene ficha en asesores_perfil y está activo
  SELECT true, ap.pais_id, ap.activo, ap.supervisor_id
    INTO v_hay_fila, v_pais_sup, v_activo_sup, v_sup_del_sup
    FROM public.asesores_perfil ap WHERE ap.id = NEW.supervisor_id;
  IF NOT COALESCE(v_hay_fila, false) OR NOT COALESCE(v_activo_sup, false) THEN
    RAISE EXCEPTION
      'PA002: supervisor_id % no tiene ficha en asesores_perfil o está inactivo (ficha=%, activo=%)',
      NEW.supervisor_id, COALESCE(v_hay_fila, false), COALESCE(v_activo_sup::text, '(sin ficha)')
      USING ERRCODE = 'PA002';
  END IF;

  -- (PA003) MISMO PAÍS. Sin esta validación la jerarquía es EL vector de fuga: un supervisor de otro
  -- país entraría al conjunto de asesores_a_cargo() de su lado. El término de país de las policies lo
  -- corta igual (doble candado), pero el dato no debe poder existir en primer lugar.
  -- IS DISTINCT FROM y no `<>`: con `<>` un NULL daría NULL y la validación se saltearía (fail-open).
  IF v_pais_sup IS DISTINCT FROM NEW.pais_id THEN
    RAISE EXCEPTION
      'PA003: el supervisor % es del país % y la ficha es del país % — la jerarquía no cruza países',
      NEW.supervisor_id, COALESCE(v_pais_sup::text, '(nulo)'), COALESCE(NEW.pais_id::text, '(nulo)')
      USING ERRCODE = 'PA003';
  END IF;

  -- (PA004) el supervisor no tiene supervisor propio: 2 niveles, sin cadenas ni recursión que auditar
  IF v_sup_del_sup IS NOT NULL THEN
    RAISE EXCEPTION
      'PA004: el supervisor % cuelga a su vez de % — la jerarquía es de 2 niveles',
      NEW.supervisor_id, v_sup_del_sup USING ERRCODE = 'PA004';
  END IF;

  RETURN NEW;
END
$function$;

COMMENT ON FUNCTION private.guard_supervisor_asesor() IS
  'Guard de integridad de la jerarquía comercial (mig 264): valida supervisor_id contra rol (PA001), '
  'ficha activa (PA002), MISMO PAÍS (PA003), 2 niveles (PA004), que un supervisor no cuelgue de nadie '
  '(PA005) y que no se cambie el país de una ficha CON subordinados (PA007). '
  'PA007 cierra el agujero simétrico de PA003: sin él se armaba la jerarquía correcta en un país y '
  'después se movía de país al SUPERVISOR — su fila no tiene supervisor_id, salía por el corte por NULL '
  'sin validar nada, y el equipo quedaba apuntando cross-país. Por eso PA005 y PA007 van ANTES de ese '
  'corte. Es SECURITY DEFINER a propósito: lee perfiles y asesores_perfil, ambas con RLS, y un guard '
  'que valida contra lecturas filtradas por RLS da veredictos que dependen de quién escribe (y con `<>` '
  'en vez de IS DISTINCT FROM se volvería fail-open). No devuelve filas: solo RAISE o RETURN NEW.';

DROP TRIGGER IF EXISTS trg_asesores_perfil_guard_supervisor ON public.asesores_perfil;
CREATE TRIGGER trg_asesores_perfil_guard_supervisor
  BEFORE INSERT OR UPDATE OF supervisor_id, pais_id ON public.asesores_perfil
  FOR EACH ROW EXECUTE FUNCTION private.guard_supervisor_asesor();


-- ----------------------------------------------------------------------------
-- C.2) COHERENCIA DE PAÍS DEL PROSPECTO (PA006) — el eje del tenant, modelado desde el día 1.
--
-- Regla: prospectos.pais_id DEBE ser igual al país de la ficha del asesor_id.
--
-- POR QUÉ ES UN TRIGGER Y NO "que lo derive la RPC de la 265": una RPC puede tener bugs, y además NO
-- es la única vía de escritura — quedan el owner, service_role y cualquier fix manual por SQL. El dato
-- incoherente tiene que ser IMPOSIBLE en la base, no solo improbable por la aplicación.
--
-- Sin esta regla existe un caso que sí filtra: un prospecto marcado en el país B cuyo asesor es del
-- país A pero cuelga de un supervisor de B. Los DOS términos de la policy de prospectos pasan
-- (pais_id = mi_pais() del supervisor B, y el asesor ∈ asesores_a_cargo() de B) y el prospecto se ve
-- desde el país equivocado. Con PA006 ese estado no se puede escribir.
--
-- IS DISTINCT FROM, no `<>`: si el asesor no tiene ficha en asesores_perfil, la lectura del país es
-- NULL y con `<>` la comparación daría NULL, el IF no se cumpliría y la validación se saltearía —
-- fail-open. Con IS DISTINCT FROM, ese caso corta. Efecto deliberado: un prospecto solo puede
-- pertenecer a un asesor CON ficha.
--
-- SECURITY DEFINER por el mismo motivo que el guard de jerarquía: lee asesores_perfil, que tiene RLS,
-- y una validación que lee filtrado por el escritor no valida nada. No devuelve filas.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_pais_prospecto()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_pais_asesor uuid;
BEGIN
  SELECT ap.pais_id INTO v_pais_asesor
    FROM public.asesores_perfil ap WHERE ap.id = NEW.asesor_id;

  IF NEW.pais_id IS DISTINCT FROM v_pais_asesor THEN
    RAISE EXCEPTION
      'PA006: el prospecto se está marcando en el país % pero la ficha del asesor % es del país % — el país del prospecto se deriva del asesor',
      COALESCE(NEW.pais_id::text,'(nulo)'), NEW.asesor_id,
      COALESCE(v_pais_asesor::text,'(el asesor no tiene ficha en asesores_perfil)')
      USING ERRCODE = 'PA006';
  END IF;

  RETURN NEW;
END
$function$;

COMMENT ON FUNCTION private.guard_pais_prospecto() IS
  'Obliga a que prospectos.pais_id sea igual al país de la ficha del asesor_id (mig 264, PA006). Es un '
  'trigger y no una derivación en la RPC porque la RPC puede tener bugs y NO es la única vía de '
  'escritura (owner, service_role, fix manual por SQL): el dato incoherente debe ser IMPOSIBLE, no solo '
  'improbable. Sin esto, un prospecto marcado en el país B con asesor del país A colgado de un '
  'supervisor de B pasa los dos términos de la policy y se ve desde el país equivocado. '
  'IS DISTINCT FROM y no `<>`: sin ficha la lectura es NULL y `<>` saltearía la validación (fail-open). '
  'SECURITY DEFINER porque lee asesores_perfil, que tiene RLS.';

DROP TRIGGER IF EXISTS trg_prospectos_guard_pais ON public.prospectos;
CREATE TRIGGER trg_prospectos_guard_pais
  BEFORE INSERT OR UPDATE OF pais_id, asesor_id ON public.prospectos
  FOR EACH ROW EXECUTE FUNCTION private.guard_pais_prospecto();


-- ----------------------------------------------------------------------------
-- C.3) Visibilidad de un prospecto — MISMO predicado que la policy de prospectos, en UN solo lugar.
--      (Conceptualmente es un helper de la sección A; vive acá por la dependencia de creación
--       explicada en A.4: es LANGUAGE sql y su cuerpo se valida al crear la función, así que
--       public.prospectos ya tiene que existir. El cuerpo es idéntico al que estaba en A.4.)
--
-- Existe para que la policy de prospecto_contactos NO lleve una subquery cruda contra prospectos.
-- Una subquery dentro de una policy se evalúa bajo la RLS del caller sobre la tabla referenciada
-- (lección de la mig 106 / hardening de visitas). Acá eso daría hoy el mismo resultado — pero ata
-- la visibilidad de los contactos al CONJUNTO de policies que tenga prospectos en el futuro: si
-- alguien agrega mañana una policy permisiva a prospectos, los contactos la heredan en silencio.
-- Con el helper DEFINER, el criterio de contactos es explícito y no se mueve solo.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.prospecto_visible(p_prospecto_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT COALESCE((
    SELECT COALESCE(public.get_auth_user_rol() = 'super_admin', false)
        OR ( pr.pais_id = private.mi_pais()
             AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = pr.asesor_id) )
      FROM public.prospectos pr
     WHERE pr.id = p_prospecto_id
  ), false);
$function$;

REVOKE EXECUTE ON FUNCTION private.prospecto_visible(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.prospecto_visible(uuid) TO authenticated;

COMMENT ON FUNCTION private.prospecto_visible(uuid) IS
  'Replica en UN solo lugar el predicado de visibilidad de prospectos, para que la policy de '
  'prospecto_contactos no lleve una subquery cruda (mig 264). Si cambia el criterio, se cambia en la '
  'policy de prospectos Y acá — son las dos únicas copias, y el probe P476 vigila que coincidan.';


-- ============================================================================
-- D) RLS — SOLO LECTURA
--
-- REGLAS INNEGOCIABLES DE ESTE MÓDULO (valen para toda policy futura acá):
--   1. El término de país va SIEMPRE CONJUNTIVO, también para el supervisor. DOBLE CANDADO: si un
--      supervisor_id quedara mal apuntado (por un bug, por un UPDATE directo, por un trigger
--      deshabilitado), el país corta igual. El probe P475 es el centinela de esto.
--   2. EXISTS, NUNCA IN. Con `col IN (SELECT ...)`, un NULL en el conjunto vuelve la expresión NULL
--      en vez de false y el gate se saltea entero.
--   3. PROHIBIDO `pais_id IS NULL OR ...` en el eje de aislamiento. Una fila sin país no es "visible
--      para todos": es un dato roto. Por eso pais_id es NOT NULL en las tablas que lo llevan.
--   4. Todo helper booleano usado en un gate va COALESCE(...,false).
--   5. super_admin va como PRIMERA rama del OR: corta antes de evaluar mi_pais() y el chokepoint.
--
-- HIGIENE DE PRIVILEGIOS: toda tabla nueva en public nace con ALL para authenticated (y anon) por los
-- default privileges de Supabase. Un GRANT SELECT es ADITIVO y NO alcanza: hay que REVOCAR el resto
-- explícitamente. El GRANT SELECT posterior es defensivo (deja la tabla correcta aunque los defaults
-- cambien). Misma lección que la 263 y la memoria supabase-default-privileges-revoke.
-- ============================================================================

ALTER TABLE public.asesores_perfil     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prospectos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prospecto_contactos ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.asesores_perfil     FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.prospectos          FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.prospecto_contactos FROM authenticated;

REVOKE ALL ON public.asesores_perfil     FROM anon;
REVOKE ALL ON public.prospectos          FROM anon;
REVOKE ALL ON public.prospecto_contactos FROM anon;

GRANT SELECT ON public.asesores_perfil     TO authenticated;
GRANT SELECT ON public.prospectos          TO authenticated;
GRANT SELECT ON public.prospecto_contactos TO authenticated;

-- CREATE POLICY no admite IF NOT EXISTS: el DROP previo hace el archivo re-ejecutable.
DROP POLICY IF EXISTS asesores_perfil_select     ON public.asesores_perfil;
DROP POLICY IF EXISTS prospectos_select          ON public.prospectos;
DROP POLICY IF EXISTS prospecto_contactos_select ON public.prospecto_contactos;

CREATE POLICY asesores_perfil_select
  ON public.asesores_perfil
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(public.get_auth_user_rol() = 'super_admin', false)
    OR (
      pais_id = private.mi_pais()
      AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = asesores_perfil.id)
    )
  );

CREATE POLICY prospectos_select
  ON public.prospectos
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(public.get_auth_user_rol() = 'super_admin', false)
    OR (
      pais_id = private.mi_pais()
      AND EXISTS (SELECT 1 FROM private.asesores_a_cargo() a WHERE a = prospectos.asesor_id)
    )
  );

CREATE POLICY prospecto_contactos_select
  ON public.prospecto_contactos
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(private.prospecto_visible(prospecto_id), false)
  );


-- ============================================================================
-- FIN 264. Lo que sigue (265): RPCs SECURITY DEFINER de escritura — alta/edición de ficha de asesor
-- (con los guards de jerarquía ya puestos), alta/edición/avance de pipeline de prospectos y CRUD de
-- contactos. La RPC derivará pais_id del asesor server-side por CONVENIENCIA (para no pedirle al
-- cliente un dato que ya se conoce), no como control: el control es PA006 y vive en la base.
-- ============================================================================
