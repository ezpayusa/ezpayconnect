-- ############################################################################################
-- 284 — `anon` deja de tener privilegios sobre public.perfiles
-- ############################################################################################
-- DE DONDE SALEN ESTOS PRIVILEGIOS
-- --------------------------------
-- De ningun lado deliberado: son el **ACL default de Supabase**. Toda tabla creada en `public`
-- nace con ALL para `anon` y para `authenticated`, y `perfiles` nunca se reboco. Medido antes de
-- escribir esto: **no hay un solo `GRANT ... ON perfiles` en todo el repo**. Nadie se los dio; se
-- quedaron desde el dia que se creo la tabla.
--
-- Estado medido en prod, los 7 privilegios de tabla:
--   anon          -> SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
--   authenticated -> SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
--
-- POR QUE IMPORTA, Y POR QUE NO ES "SOLO HIGIENE"
-- -----------------------------------------------
-- `perfiles` es la tabla con mas datos personales del sistema: email, nombre, telefono,
-- direccion_consultorio, lat/lng del consultorio y avatar_url.
--
-- SELECT/INSERT/UPDATE/DELETE de `anon` hoy NO son explotables: la tabla tiene RLS y sus cinco
-- policies dependen de `auth.uid()`, que para anon es NULL, asi que la RLS lo frena en seco. Son
-- grants vestigiales — la misma clase que P222 (`anon ve farmacias`).
--
-- **TRUNCATE ES OTRA COSA: NO PASA POR RLS.** La RLS filtra filas en SELECT/INSERT/UPDATE/DELETE;
-- TRUNCATE opera sobre la tabla entera y ni siquiera consulta las policies. Un TRUNCATE en manos de
-- `anon` es la capacidad de vaciar `perfiles` de un golpe, y la unica barrera que existio durante
-- toda la vida del proyecto fue que nadie lo intentara. Eso es lo que esta migracion cierra.
--
-- QUE **NO** SE TOCA
-- ------------------
-- A `authenticated` se le CONSERVAN SELECT, INSERT, UPDATE y DELETE: los necesita, y la RLS es la
-- que los acota fila por fila (`auth.uid() = id` y el gate de admin de pais). Sacarselos romperia
-- la app entera. Se le revocan solo TRUNCATE, REFERENCES y TRIGGER, que ninguna ruta usa.
--
-- No se toca ninguna POLICY. La 284 es exclusivamente de privilegios de tabla.
--
-- QUE LO MIDE
-- -----------
--   P631 — censo: anon sin los 6 de escritura/DDL, CON el SELECT (vino ROJO con los 7).
--   P632 — authenticated: los 4 de DML si, los otros 3 no (vino ROJO con 3 de mas).
--   P633 — CONTROL POSITIVO: un usuario real lee su propio perfil por SELECT. Verde ANTES y
--          DESPUES: es lo que prueba que la revocacion no se paso de la raya.
--   P634 — censo del modulo comercial: anon en cero sobre las 9 tablas del frente.
-- ############################################################################################

-- POR QUE **NO** SE REVOCA EL SELECT DE anon. MEDIDO, Y APRENDIDO A LOS GOLPES.
-- ----------------------------------------------------------------------------
-- La primera version de esta migracion hacia `REVOKE ALL ... FROM anon` y **rompio produccion**.
-- Causa: 22 tablas donde anon tiene SELECT tienen policies cuyo USING consulta `perfiles`
-- (`auditoria_logs`, `campana_metricas`, `clinicas`, `configuracion_sistema`,
-- `cuentas_bancarias_pais`, `cuentas_proveedor`, `disponibilidad_medico`, `empresas_proveedoras`,
-- `invitaciones_clinica`, `invitaciones_medico`, `notificaciones_email`, `pagos_proveedor`,
-- `planes_publicidad_config`, `productos_empresa`, `signos_vitales`, `solicitudes_campana`,
-- `usuario_roles`, `visitas_agendadas`, entre otras).
--
-- **Una policy se evalua con los privilegios del LLAMANTE, no del dueno de la tabla.** Antes, un
-- `EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() ...)` daba `false` en silencio para anon
-- —auth.uid() es NULL— y la RLS negaba el acceso, que es el comportamiento correcto. Sin el SELECT,
-- ese mismo EXISTS pasa a lanzar **42501 duro** antes de poder evaluar nada: la tabla entera deja
-- de responderle a anon, incluidas las policies publicas legitimas.
--
-- El SELECT de anon sobre perfiles NO es una fuga: la RLS ya lo deja en cero filas. Es el permiso
-- que las policies necesitan para poder DECIR QUE NO. Se conserva.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.perfiles FROM anon;

REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.perfiles FROM authenticated;

-- Re-verificacion: la migracion se comprueba a si misma y ABORTA si no quedo como dice.
DO $$
DECLARE v_anon text; v_sobra text; v_falta text;
BEGIN
  SELECT string_agg(p, ', ' ORDER BY p) INTO v_anon
    FROM unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
   WHERE has_table_privilege('anon', 'public.perfiles', p);
  IF v_anon IS NOT NULL THEN
    RAISE EXCEPTION 'anon conserva privilegios de escritura sobre perfiles: %', v_anon;
  END IF;
  -- El lado que NO se toca, y que si falta rompe 22 tablas: ver la nota de arriba.
  IF NOT has_table_privilege('anon', 'public.perfiles', 'SELECT') THEN
    RAISE EXCEPTION 'la 284 se paso: sin SELECT de anon, toda policy que consulte perfiles lanza 42501 a anon';
  END IF;

  SELECT string_agg(p, ', ' ORDER BY p) INTO v_sobra
    FROM unnest(ARRAY['TRUNCATE','REFERENCES','TRIGGER']) p
   WHERE has_table_privilege('authenticated', 'public.perfiles', p);
  IF v_sobra IS NOT NULL THEN
    RAISE EXCEPTION 'authenticated conserva privilegios que esta migracion debia revocar: %', v_sobra;
  END IF;

  -- Y el lado que NO se toca: si esto falta, la app se rompe entera y hay que enterarse aca.
  SELECT string_agg(p, ', ' ORDER BY p) INTO v_falta
    FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) p
   WHERE NOT has_table_privilege('authenticated', 'public.perfiles', p);
  IF v_falta IS NOT NULL THEN
    RAISE EXCEPTION 'la 284 se paso: authenticated perdio privilegios que la RLS necesita: %', v_falta;
  END IF;
END $$;
