# EzPayConnect — Memoria de proyecto

Plataforma médica con paneles de admin (admin-ezpay), proveedor, país (admin_pais) y paciente / clínica.
Stack: React + Vite + TypeScript, Supabase / Postgres, deploy en Vercel, repo en /c/dev/ezpayconnect.

## Reglas de trabajo (mantener siempre)
- Diagnosticar antes de tocar nada. Rastrear el flujo de datos de punta a punta y confirmar la causa raíz (idealmente contra la DB viva) antes de escribir código.
- Un commit por bloque, con mensaje claro. Nada de un commit gigante al final.
- Verificar en cada cambio: tsc -p tsconfig.app.json (baseline actual = **74** errores; objetivo = 0 nuevos) + vite build verde + prueba por rol en prod.
  **El comando es `npx tsc -p tsconfig.app.json --noEmit` y el baseline es 74.** Bajó de 75 a 74 el 3-oct con el fix de vigencia UTC (review #27: el `TS2339 'visitas_usadas'` de `useVisitasAgendadas` era el cálculo de cupo viejo, que leía un campo que el mapeo no traía). Antes, de 78 a 75 el 26-sep con el front de P4 (los 3 `TS2339 'descripcion'`
  de `ExamenPaciente`: el paciente nunca veía la descripción del examen). Antes, de 82 a 78 el
  22-sep con el frente 7 (lab): los 4 `TS2339 Property 'estado' does not exist on type
  'OrdenAgrupada'` de LabDashboard eran el bug del conteo, y llevaban meses escondidos DENTRO del
  baseline. Un baseline es un techo, no una alfombra — bajarlo cuando se arregla algo es parte del
  arreglo, si no el próximo que rompa 4 pasa igual. `npx tsc --noEmit` pelado
  da **0** y NO es un chequeo válido: el `tsconfig.json` raíz tiene `"files": []` y sólo `references`, y
  sin `-b` no compila ningún archivo. Un 0 de ese comando no mide nada. (Medido 15-sep-2026; circuló un
  "baseline 88" que no salió de ninguno de los dos comandos.)
- **Una policy se evalúa con los privilegios del LLAMANTE.** Revocar SELECT a un rol sobre una
  tabla que otras policies consultan en su `USING` **no niega en silencio: lanza 42501** y rompe
  esas tablas para ese rol. Toda migración de privilegios lleva una probe que **EJERCITE** al rol
  afectado contra una tabla dependiente (0 filas, sin error) — el dry-run de catálogo no lo ve,
  porque mira quién tiene qué y no qué pasa cuando se usa. **Mig 284, 6-sep: rompió prod unos
  minutos por esto** (P635 es la probe que faltaba, P636 su contraprueba).
- NUNCA ampliar policies de RLS sobre tablas adyacentes a datos médicos (p. ej. campana_metricas). Para dar acceso, usar RPCs SECURITY DEFINER con search_path='', fail-closed (si el scope es NULL → 0 filas) y gate interno.
- Probar aislamiento por rol impersonando request.jwt.claims en prod: cada rol ve lo suyo y no lo ajeno.
- **Próximos números libres: probe `P1035`** (global, no por módulo; P1026-P1034 + M373_FX usados por la mig 373; P1023-P1025 + G372_FX usados por la mig 372; P1019-P1022 usados por la mig 371; P1015-P1018 usados por la mig 370, P1011-P1014 por la mig 369, P1010 por la mig 367, P1009 por la 366, P1008 por la 365, P1007 por la 364, P1001-P1006 por la mig 363, P996-P1000 por la 362, P990-P995 por la 361, P983-P989 por la 360, P975-P982 por la
  359, P967-P974 por la 358, P958-P966 por la 357 (obtener_medicos_por_ids acotada a relación); P906-P907 usados por la mig 336, P912-P913
  por la 337, P914-P915 por la 338, P916-P920 por la 339/340, P921-P923 por la 341, P924 por la 342, P925 por
  la 343, P926-P927 por la 344, P928-P929 por la 345, P930 por la 346, P931-P932 por la 347, P933 por la 348,
  P934-P935 por la 349, P936 por la 350, P937-P939 por la 351, P940-P943 por la 353), **migración `374`** (la 373 es el alta diferida de empresas, aplicada el 9-oct; la 371 es GL-02 y la 372 su hardening, las dos aplicadas el 8-oct), **errcode `LG007`** (prefijo LG,
  GL-02: LG001-LG005 en uso por la 371 — LG001 sin sesión, LG002 código inexistente, LG003 versión no vigente, LG004
  entrada inválida, LG005 aceptaciones append-only; LG006 = el texto no corresponde a la identidad de la cuenta, en uso
  por la 372), **errcode `PC029`** (familia PC: PC025 país requerido y PC026 sin autoridad en `contar_medicos_por_pais`, PC027
  no autenticado, PC028 sin autoridad sobre el país en `contar_proveedores_por_pais`), **errcode `RP005`** (prefijo RP,
  mig 373 `completar_registro_proveedor`: RP001 sin sesión, RP002 correo sin confirmar, RP003 sin registro de empresa
  pendiente, RP004 datos inválidos; mensajes para el usuario final, en tú, sin datos del usuario; el front tiene que mapear
  RP*; los 42501/22023 de `registrar_proveedor` se propagan tal cual)
  (373 = alta diferida de empresas con Confirm email ON — **APLICADA en prod el 2026-10-09 entre 16:27:52 y 16:27:54 UTC**
  y verificada en sesión independiente (V1-V4: objeto vivo = archivo, huellas, datos y P1026-P1034 + M373_FX en OK con la
  función presente). Rama `altas/alta-diferida-373`; commits c2b925d, 0423d3b, 42e2033 (review M2/M3/M4). sha256 de la
  migración 251eaf382530e1928622b6f2d03cb621414c9aa53e17999b27aafbe867708351 y de `373_rollback.sql`
  4b6857d2770c058bda8e6b2a8dbad922ecb7993450f72d27ff152cbd5364b8b9; md5(prosrc) de `completar_registro_proveedor`
  bdcaf676b4b14ad0ad14aaab73a4187d; `registrar_proveedor` sin cambio (fae23eeeacb393328f774386ccd88479). **Huellas
  post-373:** funciones 027e10a7b66101b4f5bb85c475c34045/392 (sin la nueva 5482f6de…/391, la post-372); policies
  8a8dc5cf…/309 y relaciones d065decf…/2394 sin cambio. **Decisión de Oscar (9-oct-2026):** Confirm email está ON en prod
  (medido 9-oct) y el autorregistro de farmacia/lab/proveedor fallaba en `registrar_proveedor` (signUp sin sesión);
  alta diferida: el front guarda los datos en `raw_user_meta_data -> 'registro_empresa'` en el signUp y al primer login
  llama a `public.completar_registro_proveedor()` (DEFINER, `search_path=''`, EXECUTE solo authenticated/postgres/
  service_role), que con el correo confirmado valida el registro y llama a `registrar_proveedor` con la sesión del usuario;
  idempotente (si ya es proveedor devuelve su empresa, antes de mirar correo y registro: P1034) y serializada por uid con
  `pg_advisory_xact_lock`; solo lee auth.users. Probes P1026-P1034 + M373_FX: con la función ausente publican
  `REGRESION (373 ausente: …)`. Rollback vigente 373 → 372 → 371 → 370. **Condiciones del PR del front** (rama nueva desde
  main después del merge de GL-02, lunes 12-oct): signUp de farmacia/lab/proveedor con `options.data.registro_empresa`
  (incluido `email_contacto` explícito: la RPC da RP004 si falta) y `emailRedirectTo` al login de su portal; llamar a
  `completar_registro_proveedor` al login de los 3 portales (y justo tras el signUp si hubo sesión); limpiar
  `registro_empresa` con `updateUser` después del éxito (review M1: si no, una empresa borrada se vuelve a crear en el
  próximo login); respetar `cuentas_proveedor.activo` (la RPC devuelve la empresa también a una cuenta inactiva, nit #3);
  mapear RP001-RP004; paciente: `emailRedirectTo` a /paciente y que RootRedirect y LoginPage reconozcan al paciente (fila
  en pacientes) en vez de mandarlo a /sin-panel. **Nits de la review 373 (backlog):** el autochequeo de grantees no mira
  `is_grantable`; RP002 es engañoso para un usuario borrado con JWT vivo; la SQL de huellas sigue repetida; 23505 crudo en
  la carrera `registrar_proveedor` directo vs `completar_registro_proveedor` (sin empresa duplicada: la PK de
  cuentas_proveedor revierte la segunda).)
  (372 = GL-02 hardening de la 371 (review #54, n2-n9) — **APLICADA en prod el 2026-10-08 a las 17:10 UTC (17:10:20.279 →
  17:10:22.590, exit 0)**, sha256 7797e4c5fe698a94348e27e5cd78a110c00dc115522098a79cf3cb3428c2d174, y verificada en sesión
  independiente (harness post-apply 1111 / 11 rojas de deuda; todos los objetos y cuerpos iguales al archivo). **Huellas
  post-372:** funciones 5482f6de564741ad445f30d3ccbd9a79/391; policies 8a8dc5cf…/309 y relaciones d065decf…/2394 sin
  cambio. P1022-P1025: la rama 'ausente' publica `REGRESION (372 ausente: …)` (commit e4d0d22; validada con un dry-run de
  `372_rollback` + probes: G372_FX OK (ausente), P1022-P1025 en REGRESION, txid 275998 abortado). Rama
  `gl02/mig-372-hardening`, PR #55 en borrador; commits e3db0e4 migración, e9e90cf rollback, 7956f08 probes, f38c225 y
  d22ac5b cabecera, e88437f probes, e4d0d22 REGRESION.
  **Review #55 pre-apply: APROBADO.** Nits n1/n2/n7 resueltos en la cabecera; n5/n6 en probes (G372_FX publica ROJO si el
  estado es parcial; mutación m6 con `fija_fecha` no-op deja G372_FX en OK (presente) y P1025 en ROJO por la aserción
  funcional: la fecha forjada sobrevive). **Riesgo aceptado (n2):** service_role (regla 3, SIUD) puede insertar directo la
  aceptación de un usuario real, de un texto que no le aplica y con via/user_agent a elección (el INSERT directo no pasa
  por LG006); la fecha (trigger) y el uid inexistente (FK) sí quedan cerrados; service_role solo existe server-side y
  ninguna edge escribe en la tabla. **Huecos de IDENTITY por diseño (n7):** probes y dry-runs consumen ids en
  transacciones abortadas; un hueco no implica una fila borrada (la inmutabilidad la garantizan los triggers LG005). `private.identidad_legal(uuid)` (DEFINER,
  `search_path=''`, una fila siempre, NULL → (false, false)): es_profesional sale de `roles_catalogo.ambito = 'clinica'`
  (JOIN, sin lista literal) o de `cuentas_proveedor`; `pendientes_de` y `aceptar_textos_legales` la usan. `aceptar` recorre
  el array `ORDER BY (e ->> 'codigo')` (locks en orden estable), valida tipo → repetido → LG002 → **LG006** (el texto no
  aplica a la identidad del llamante; no mira exigible) → LG003, y los mensajes van con tildes, en tú y sin eco de lo que
  manda el cliente. Trigger `trg_aceptaciones_legales_fija_fecha` (BEFORE INSERT, `aceptado_at := now()`; nadie elige la
  fecha, ni service_role); FK `aceptaciones_legales_usuario_id_fkey` → `auth.users` ON DELETE/UPDATE RESTRICT; las 2
  funciones de trigger son INVOKER. Precondición: estado post-371 (funciones 4c1f611c…/389, policies 8a8dc5cf…/309,
  relaciones d065decf…/2394, md5(prosrc) de las 5 funciones de la 371) más los 6 roles de `ambito = 'clinica'` = la lista
  vieja. Huellas post-372 calculadas = medidas en el dry-run: funciones 5482f6de564741ad445f30d3ccbd9a79/391; policies y
  relaciones sin cambio. sha256 de la migración 7797e4c5fe698a94348e27e5cd78a110c00dc115522098a79cf3cb3428c2d174 (solo cambió la cabecera en f38c225/d22ac5b; md5(prosrc) y huellas iguales, dry-run de control 34/34) y de
  `372_rollback.sql` 1769f78afdb6d3dd282ed6b6bb42e25b7b874396276888f39fd864178817d2bb. Dry-run 34/34 (pendientes_de pre y
  post iguales para los 6 actores de P1020); dry-run combinado 372 → rollback 29/29 con una aceptación cargada (sobrevive
  al rollback). Probes: G372_FX, P1022 por estado (ausente = forma 371, presente = forma 372, parcial = ROJO), P1023
  estructura, P1024 regla y mensajes, P1025 forja y escritura directa; harness pre-apply v2 1111 filas / 1020 bloques DO /
  11 rojas de deuda (P1023-P1025 en estado previo al apply); mutaciones m1-m6 (trigger, LG006, lista literal, solo_append
  DEFINER, FK, fija_fecha no-op) en ROJO.
  **Decisión de Oscar (8-oct-2026):** FK a `auth.users` ON DELETE RESTRICT — borrar un usuario con aceptaciones falla; la
  cancelación de cuenta va a necesitar un flujo de anonimización (backlog). **Próximo:** review ronda 2 → merge →
  front de GL-02. Próximos libres: mig 373, P1026, LG007; rollback vigente 372 → 371 → 370.)
  (371 = GL-02 textos legales: catálogo `textos_legales`, `aceptaciones_legales` append-only y RPCs
  `textos_legales_pendientes()` / `aceptar_textos_legales(jsonb, text, text)` — **APLICADA en prod el 2026-10-08 a las
  15:03 UTC (15:02:58.051 → 15:03:00.009, exit 0)**, sha256 del archivo
  e81b39d392a9896e16796925b9348e4de3ffc9e6fee4fe952a057058b88f3824, y verificada en sesión independiente (rama
  `gl02/textos-legales`, PR en borrador). Antes: dry-run PASA 7-oct (txid abortado) y precondición = estado post-370
  (funciones 4878afd5…/384, policies 9ad61756…/307, relaciones 64ff833d…/2368). **Huellas post-371 (medidas en prod =
  las del dry-run):** ACL de funciones 4c1f611c29b8b37d8076536d065069e0/389; policies 8a8dc5cfaf8365f95208fb9e8ba79674/309;
  ACL de relaciones de public d065decfec14c0afae8f5d898032e4bb/2394; 0 funciones con PUBLIC; anon ejecuta solo
  `catalogo_planes_visitador_publico()`. ACL: las 2 tablas `{postgres, authenticated=r, service_role=arwd}`; las 2 RPCs
  `{postgres, authenticated, service_role}`; las 3 de private solo postgres. `textos_legales`: 4 filas en v0.1
  (terminos, privacidad, consentimiento_salud, condiciones_profesionales) con `exigible = false` hasta que Oscar entregue
  los datos de la sección 5.1; `aceptaciones_legales`: 0 filas. Probes P1019-P1022: la rama 'ausente' publica
  `REGRESION (371 ausente: …)` (commit 2283d1f; validada con un dry-run de `371_rollback` + probes que terminó en
  ROLLBACK: las 4 en REGRESION, txid abortado, prod intacta). Harness post-371: **1107 filas / 1016 bloques DO / 11 rojas
  de deuda**; b2_guard top_level 0, cast 0, do_sin_handler 155, catchall_verde 205. Errcodes LG001-LG005 en uso,
  próximo LG006. **Rollback vigente: 371 → 370** (`supabase/migrations/371_rollback.sql`, va antes que `370_rollback`).
  **Sigue en GL-02:** el front (gate global en el primer login y casilla de aceptación en las altas).)
  (370 = familia 2, ÚLTIMO paso: EXECUTE de funciones sin PUBLIC ni anon — **APLICADA en prod el 2026-10-07 a las 19:18 UTC
  (19:18:26.914 → 19:18:28.737)**, sha256 del archivo 529777fd…cddbf7, y verificada VERDE en sesión independiente: harness
  post370 1102 filas / 1011 bloques DO / 11 rojas de deuda, P1015/P1016/P1017/P739/P741/P1000 en OK. **Bug vivo cerrado:**
  `entrega_evidencias` le daba 42501 a farmacia.qa (`entrega_visible` sin EXECUTE de authenticated). **Huellas post (las
  precondiciones que tiene que exigir la 371):** ACL de funciones 4878afd5e7fa74667b466d6994d565ff/384; 0 funciones con
  PUBLIC; anon ejecuta solo `catalogo_planes_visitador_publico`; policies 9ad617568275d4b7f27b1e2115f8978f/307 y ACL de
  relaciones de public 64ff833d25666534b8de9171d1e5d404/2368 sin cambio. Rama `fam2/execute-370-funciones` (rebasada
  sobre main 9ccd229; ~~va después del domingo 11-oct-2026~~). Pre-apply sobre main: 1102 filas / 11 rojas de deuda,
  tras corregir P1015 (fa385a7: `entrega_visible` sin authenticated es PENDIENTE en 'pre', como P1017; en 'post' se
  exige) (superado por b359a8f: el estado pre es REGRESION). Nota de método: el harness (payload de 2,8 MB) falló dos veces con "tls: bad record MAC" en la capa de red del
  sandbox de CC; ROLLBACK verificado, sin efectos. Recon del 6-oct (`tmp/recon_execute/`):
  de 384 funciones de public/private, 38 tenían EXECUTE para PUBLIC (21 legacy de public + 15 de private con proacl NULL + 2
  de private) y 22 anon explícito (las 21 legacy + `catalogo_planes_visitador_publico`). **Ninguna le llega a authenticated
  solo vía PUBLIC**: las 9 helpers de policies ya tienen authenticated (y las de public, service_role) explícitos. Cambio:
  GRANT documental (no-op) a authenticated/service_role sobre las 9 helpers + `calcular_limite_cancelacion` y a authenticated
  sobre `private.safe_uuid` (sin service_role: BYPASSRLS y sin USAGE en private); REVOKE EXECUTE FROM PUBLIC, anon por
  catálogo en las 38 (aborta si no son 38), salvo `catalogo_planes_visitador_publico`, que conserva anon; y GRANT de
  `private.entrega_visible(uuid,integer,uuid)` a authenticated (**bug vivo en prod**: la policy `entrega_evidencias_select`
  TO authenticated la llama y la función tenía `{postgres=X/postgres}` → toda lectura de `entrega_evidencias` por API da
  `42501 permission denied for function entrega_visible`; regla 10; lo hallaron P800 (l) y P1015). Las funciones de
  trigger no necesitan EXECUTE del que dispara (se chequea en CREATE TRIGGER, no en `ExecCallTriggerFunc`). Huellas: ACL de
  funciones e5c9770e…/384 → **4878afd5e7fa74667b466d6994d565ff/384**; policies 9ad61756…/307 y ACL de public 64ff833d…/2368
  sin cambio. md5 del archivo be129526…, del cuerpo sin BEGIN/COMMIT c276d600…; `370_rollback.sql` md5 372c4dcd… (listas
  LITERALES: 38 GRANT TO PUBLIC, 21 TO anon, REVOKE de entrega_visible; las 15 de proacl NULL vuelven como
  `{postgres=X,=X}`, mismo conjunto: la huella vuelve a e5c9770e…/384 pero proacl_null queda en 0). Probes: P1015 censo
  (+ regla "toda función de una policy la ejecuta cada rol de la policy"), P1016 anon ejercitado, P1017 authenticated por
  panel (incluye `entrega_evidencias` como farmacia.qa), P1018 triggers INVOKER y de private disparados como authenticated;
  P739/P741/P1000 invertidos; P935/P936 aceptan, con la 370 viva, el 42501 de FUNCIÓN de anon en la pasada alternada a
  `{public}`. **Con la 370 aplicada no hay rama PENDIENTE:** un estado pre (`370_rollback` o un re-otorgamiento manual;
  `pg_temp.e370_estado()` = 'pre', fixture E370_FX) da REGRESION en P739/P741/P1000/P1015/P1016/P1017, y P800 aborta con
  violaciones (j)/(k)/(m) → el harness sale con exit 1. **Quien corra `370_rollback` tiene que esperar esas rojas.** Cualquier
  otro estado distinto de 'post' es ROJO. P800: reglas (j) sin PUBLIC, (k) anon solo en WL_ANON_FN (baseline 1), (l)
  funciones de policies ejecutables por sus roles, (m) anon ejercitado; relkind con 'f'. Dry-run 6-oct: A (370 + harness) 1094 filas / 11 rojas de deuda; B (370 + P800) PASA limpio; C (370
  + rollback) huellas de vuelta; D huellas vivas intactas, proacl_null 15; E (harness sin la 370) 12 rojas = las 11 + P1015
  por entrega_visible, hasta el apply (corregido en fa385a7, ver arriba).)
  (369 = familia 2, F2-f (cierra la F2-f), examenes_catalogo sin escritura directa — APLICADA en prod el 2026-10-06 entre
  19:44:34 y 19:44:38 UTC y verificada en sesión independiente; harness 1089 filas / 11 rojas de deuda, P800 PASA. Antes,
  recepción y técnico del lab (y cualquier empresa activa con su propio id) escribían el catálogo por API sin el permiso.
  3 RPCs DEFINER (`search_path=''`, EXECUTE solo authenticated y service_role): `crear_examen_catalogo(p_nombre,
  p_categoria)`, `actualizar_examen_catalogo(p_id, p_categoria, p_activo)` (NULL = sin cambio; no renombra) y
  `eliminar_examen_catalogo(p_id)`, con el gate PRIMERO: `mi_empresa_proveedor()` + empresa `laboratorio_clinico` activa +
  `COALESCE(private.tiene_permiso('catalogo_examenes_editar'), false)`. Errcodes EX035 sin permiso, EX036 no existe en tu
  catálogo (también si es de otro lab), EX037 nombre/categoría inválidos, EX038 ya ordenado (se desactiva, no se borra),
  EX039 nombre repetido. `catalogo_lab_all` → `catalogo_lab_select` (SELECT TO authenticated, COALESCE fail-closed);
  REVOKE INSERT/UPDATE/DELETE y el UPDATE de columna (categoria, activo) de authenticated. Huellas: policies 2c6e39d7…/307
  → 9ad617568275d4b7f27b1e2115f8978f/307; ACL de public e2bb57f4…/2370 → 64ff833d25666534b8de9171d1e5d404/2368; ACL de
  funciones 0ee90ba6…/381 → e5c9770e31312d34601dc45f0c545173/384. Probes: P1011-P1014 nuevos; P873, P875, P878, P883 y
  P884 con rama `v_369` (verdes con y sin la 369). Front: `useLaboratorio` por RPC + `src/laboratorio/lib/catalogoExamenes.ts`
  (mensaje por whitelist EX035-EX039; 42501 y el resto con texto genérico desde el review #47; EX038 ofrece desactivar).
  Rollback `369_rollback.sql` (va antes que `368_rollback` y que `367_rollback`: la precondición de la 367 exige la ACL de
  public e2bb57f4…/2370, que la 369 cambió; exige revertir también el front de `useLaboratorio` a la escritura directa).)
  (368 = familia 2, F2-f parcial, configuracion_sistema sin admin_pais — APLICADA en prod el 2026-10-06 entre 18:58:26 y
  18:58:30 UTC y verificada en sesión independiente. ALTER POLICY de `configuracion_sistema_select_authenticated_publicas`:
  sale `admin_pais` del `tiene_rol`; queda con las 14 claves públicas para todo authenticated y las 21 solo para el
  super_admin (nadie lee la tabla con sesión de usuario: `/configuracion` va por la edge con service_role). Huella de
  policies a99ac4be…/307 → 2c6e39d704ebd6a2e28542b9d3b4fbc0/307; ACL sin cambio. Probes P757 y P1009 ajustados (el
  admin_pais ve 14, sin integ_* por nombre). Rollback `368_rollback.sql` (va antes que `366_rollback`; con `367_rollback` es conmutable).)
  (367 = familia 2, F2-f parcial, campana_vistas sin UPDATE — APLICADA en prod el 2026-10-06 entre 18:45:04 y 18:45:08 UTC
  y verificada en sesión independiente. REVOKE UPDATE de authenticated en `campana_vistas` (privilegio muerto: sin policy
  de UPDATE; el upsert que lo justificaba, `registrarVista`, no tenía llamadores y se borró del front); INSERT y
  `ON CONFLICT DO NOTHING` siguen andando. Huella de ACL de public d05a8b3a…/2371 → e2bb57f40da44965e21590fb92d7f9c3/2370;
  policies sin cambio. Probes: P1010 nuevo; P930 sin la entrada de campana_vistas en la allowlist. Rollback
  `367_rollback.sql` (si se corre, la entrada de P930 vuelve).)
  (366 = familia 2, F2-e parte 2, datos bancarios acotados — APLICADA en prod el 2026-10-06 entre 15:10:06 y 15:10:09 UTC y
  verificada en sesión independiente; harness 1084 filas / 11 rojas de deuda. `private.pais_empresa_onboarding()` (DEFINER,
  `search_path=''`, país de la empresa del proveedor que llama, derivada de `auth.uid()`, con la empresa en estado
  activa/pendiente/suspendida y la cuenta activa; EXECUTE solo authenticated); en `cuentas_bancarias_pais`, DROP de
  `cuentas_banco_read_pais` (`pais_id = private.mi_pais()`: cualquier perfil del país veía la cuenta de depósito) y nueva
  `cuentas_banco_read_acotada` (SELECT TO authenticated: super_admin, admin_pais DE ESE PAÍS por `private.puede_admin_pais`,
  o el proveedor cuya empresa es del país, en cualquier estado; COALESCE fail-closed); en `configuracion_sistema`, ALLOWLIST
  de las 14 claves públicas para anon y authenticated (`configuracion_sistema_select_anon_publicas` y
  `configuracion_sistema_select_authenticated_publicas`); super_admin y admin_pais ven las 21; las 5 bancarias y
  integ_email_smtp/integ_whatsapp_api quedan fuera para el resto. Sin cambios de ACL de tablas. Huellas: policies
  66bef0e5…/307 → a99ac4becc3fba65a272569c293fdd26/307; ACL de funciones c7f89c6d…/380 → 0ee90ba6869cce295105d3b32b893aed/381.
  Probes: P755-P758 reescritos, P936 anon config 16 → 14, P1009 nuevo (neutraliza las cuentas_proveedor que dejan
  P87/P97/P101/Pinvit y siembra un admin_pais y una cuenta ficticia de otro país en su savepoint). Front:
  `useConfiguracionSistema.ts` (muerto) borrado. Rollback `366_rollback.sql`.)
  (365 = familia 2, F2-e parte 1, expediente_notas sin escritura del super_admin — APLICADA en prod el 2026-10-05
  20:05:27 UTC y verificada en sesión independiente. DROP de `exp_superadmin_insert` (el super_admin creaba notas a nombre
  de cualquier médico; sin cita nacían cerradas) y `exp_superadmin_update`; el super_admin conserva la lectura
  (`exp_superadmin_select`); las correcciones las hace el médico por `corregir_nota_consulta`. Huella de policies
  1929c331…/309 → 66bef0e5…/307; ACL sin cambio. Probes P888/P896 ajustados, P1008 nuevo, P929 (su receta de
  expediente_notas usa a medico.qa). Front: `useConsultas` cuenta las filas al guardar la nota y, si vuelven 0, devuelve
  `SIN_FILAS` con mensaje fijo. Rollback `365_rollback.sql`.)
  (364 = familia 2, F2-d, visitas_agendadas sin UPDATE directo — APLICADA en prod el 2026-10-05 19:04:29 UTC, harness
  1082 filas / 11 rojas de deuda, verificada independientemente. DROP de "Médico actualiza sus visitas" y "Proveedor cancela
  sus visitas" (UPDATE sin WITH CHECK: el médico y cualquier cuenta de la empresa reescribían estado, check-in/out, fecha y
  pais_id, y devolvían cupo a la bolsa de `private.pvc_usadas`) + REVOKE UPDATE de authenticated; quedan SELECT+INSERT y las
  5 policies restantes (md5 2c45abcf… 5); las escrituras van solo por las 7 RPCs DEFINER (md5 sin cambio). Huella de
  policies 6fd0d66d… 311 → 1929c331… 309; ACL de relaciones deedb2e6… → d05a8b3a…; ACL de funciones sin cambio (c7f89c6d…
  380). Probe P1007 (snapshot acotado a sus visitas y actores; excluye las visitas de la demo e9151f3e/523a1e31); P259
  invertido y P781 acepta 42501 (P258/P259 siguen N/A por la cadena vg1→va2). Rollback `364_rollback.sql`.)
  (363 = familia DASHBOARDS, conteo de proveedores por país para el admin_pais — APLICADA en prod el 2026-10-04 20:33 UTC,
  harness 1081 / 11 rojas de deuda, verificada independientemente. `public.contar_proveedores_por_pais(p_pais_id)`
  (STABLE, DEFINER, `search_path=''`, md5 43c82022…): sin sesión → PC027; sin autoridad sobre el país (super_admin, o
  admin_pais de ESE país, `private.puede_admin_pais`, COALESCE fail-closed) → PC028; cuenta `empresas_proveedoras` con
  `pais_id` = el país (el mismo criterio que la tarjeta "Proveedores" de `PaisDashboardPage`, que el admin_pais veía en 0
  por RLS). ACL `{postgres, authenticated, service_role}` (sin PUBLIC ni anon); ACL de funciones 83031eae… 379 →
  c7f89c6d… 380; policies y relaciones sin cambio. Probes P1001-P1006. Rollback `363_rollback.sql` (DROP de la función).)
  (362 = catálogo PÚBLICO de planes de visitador para la landing `/planes-visitador` sin sesión —
  APLICADA en prod el 2026-10-04 16:58 UTC (16:58:32-16:58:33), harness 1075 / 11 rojas de deuda, verificada
  independientemente. `public.catalogo_planes_visitador_publico()` (STABLE, DEFINER, `search_path=''`, md5 02d8c328…):
  devuelve país, config, plan, precio, moneda, visitas y duración SOLO de las configs que acepta
  `solicitar_compra_plan_visitador` (mismo predicado de CP001/CP003/CP004/CP005: config y base activas tipo visitador,
  visitas/duración/precio no nulos y precio > 0, primera cuenta activa del país con la misma moneda); hoy solo GT.
  **Excepción de anon justificada en P739** (catálogo público de precios, solo lectura; la allowlist vive en el harness,
  no en la base): ACL `{postgres, authenticated, service_role, anon}`; anon ejecuta 38 → 39 funciones; anon SIGUE sin
  SELECT en planes_base/planes_configuracion (350). ACL de funciones a01b26ab… 378 → 83031eae… 379; policies sin cambio.
  Probes P996-P1000; P739 pasa a 11 esperadas. Rollback `362_rollback.sql` (DROP de la función).)
  (361 = familia CAMPAÑAS, duración <= días del plan — APLICADA en prod el 2026-10-04 16:06 UTC (16:06:33-16:06:35),
  harness 1070 / 11 rojas de deuda, verificada independientemente: `solicitar_pago_campana` (después de
  CA011, antes de CA010) y `aprobar_solicitud_campana` (después de la rama idempotente y de CA003) rechazan fecha_fin <
  fecha_inicio (CA015) y fecha_fin - fecha_inicio > `planes_publicidad.dias` (CA014); una ya publicada sigue devolviendo
  su id. md5 aprobar 64b305dc… → b0492c9d…, solicitar 49a10261… → 9d8a997a…; ACL y policies sin cambio; datos sin tocar
  (hay 4 publicadas del plan de 7 días con 13-30 días, se dejan). Probes P990-P995; P967-P982 siembran la duración =
  días del plan. Front: el form autocompleta fecha_fin = inicio + días y limita el input con min/max. Rollback
  `361_rollback.sql` (cuerpos exactos de la 358/359, sin CRLF); orden `361_rollback` → `360_rollback` → ….)
  (360 = familia CAMPAÑAS, cierre en el servidor — APLICADA en prod el 2026-10-04 entre 15:45:04 y 15:45:06 UTC,
  después del merge (#33, 908b29d) y del deploy de Production; harness 1064 filas / 11 rojas de deuda, 0 PENDIENTE. Policies:
  "Proveedor crea pagos" + `tipo <> 'campana'`; "Proveedor crea campañas" solo `estado = 'borrador'`; "Proveedor
  actualiza sus campañas borrador" USING/CHECK solo borrador; NUEVA "Proveedor elimina sus campañas borrador" (DELETE);
  "Admin ve campanas de su pais" y "Admin ve solicitudes de su pais" de ALL a SELECT; NUEVAS `campanas_superadmin_update`
  y `campanas_superadmin_delete` (el super_admin conserva pausar/reactivar/eliminar; el admin_pais pierde la escritura
  directa). Huella de policies b2a47be7… 308 → 6fd0d66d… 311; texto de las 3 tablas e2885295… → e42777c5…. Probes
  P983-P989; hasta la 360, P983-P987/P989, P980 y el caso 6 de P939 salen 'PENDIENTE mig 360' (catálogo). **Orden de
  rollback de la familia: `360_rollback` → `359_rollback` → `358_rollback`.**)
  (359 = familia CAMPAÑAS, precio en el servidor, SOLO ADITIVA: `private.precio_plan_publicidad(pais, plan)` (config
  activa del país, si no el plan base; EXECUTE solo postgres), `cotizar_campana(p_solicitud_id)` y
  `solicitar_pago_campana(p_solicitud_id, p_comprobante_path)` (CA009 gate empresa+rol, CA012 ya tiene pago — antes que
  CA011 no está en borrador —, CA010 sin precio, CA013 comprobante; crea el pago con monto/moneda del servidor y pasa la
  solicitud a 'enviada'). md5 949e707c…/6323c55a…/49a10261…; ACL de funciones 20151138… 375 → a01b26ab… 378; policies
  sin cambio. Probes P975-P982 — APLICADA en prod el 2026-10-04 entre 14:24:43 y 14:24:45 UTC; harness 1057 / 11 rojas de
  deuda.)
  (358 = familia CAMPAÑAS, publicación única: DELETE del grupo duplicado de la solicitud 900dc0b3… (quedó la publicación
  6; 7 y 8 con sus métricas por CASCADE, datos QA, no se restauran); índice único parcial
  `campanas_publicitarias_solicitud_uniq`; `aprobar_solicitud_campana` atómica e idempotente, solo super_admin (CA001;
  el admin_pais perdió el permiso, sin caller), CA002-CA008, verifica el pago pendiente y carga el peso del plan.
  md5 f5a46a02… → 64b305dc…. Probes P967-P974; ajustados P507-P510 (rechazo = CA001) — APLICADA en prod el 2026-10-04
  entre 13:58:05 y 13:58:06 UTC; harness 1049 / 11 rojas de deuda.)
  (357 = `obtener_medicos_por_ids(uuid[])` acotada a relación: antes cualquier sesión autenticada resolvía nombre y
  especialidad de cualquier médico por id. Misma firma, RETURNS, DEFINER, `search_path=''`, VOLATILE y guard PC027;
  devuelve un médico solo si (a) el llamante es super_admin, (b) es el propio médico, (c) el médico aparece en una cita
  que el llamante ve como paciente (`pacientes.auth_user_id`), admin_pais del país de la cita (`private.puede_admin_pais`)
  o gestor de su clínica (`private.puede_gestionar_citas`), o (d) es miembro (`medico_clinicas`) de una clínica de
  `private.clinicas_del_usuario()`; COALESCE fail-closed. Eliminada la rama de fallback a perfiles (muerta: 0 filas).
  `contar_medicos_por_ids` queda FUERA (lote 2). md5(prosrc) 2d646322… → 8ee60166…; ACL igual (sin PUBLIC ni anon);
  probes P958-P965 (por actor) y P966 (catálogo); PM_FX elige `pm_pac` determinista (paciente real de GT con cita con
  `pm_med`) para P701. Rollback `357_rollback.sql` (rearma el cuerpo viejo con CRLF por `E'…\r\n…'` y verifica el md5
  antes de ejecutar) — APLICADA en prod el 2026-10-04 entre 12:31:47 y 12:31:49 UTC; harness 1041 filas / 11 rojas de
  deuda; tsc 74, vitest 385; smoke manual por rol 6/6.)
  (353 = delivery, lote demo 1: `tablero_repartidores(p_farmacia_id)` (carga por repartidor activo de las sucursales
  visibles: asignadas, en_camino, entregadas_hoy, fallidas_hoy, libre/en_ruta; gate `entregas_ver` y rol <> delivery;
  sin datos de pacientes), `listar_repartidores_asignables(p_entrega_id)` (los que `asignar_entrega` aceptaría, con su
  carga; gate `entregas_gestionar`), `asignar_entregas_lote(p_entrega_ids, p_delivery_id)` (atómica, máx 50, sin
  repetidos, mismas reglas que `asignar_entrega` por entrega; la que falla viaja en DETAIL) y
  `private.notificar_entregas_asignadas` (EXECUTE solo postgres); errcodes 42501 + DE001-DE009 en
  `asignar_entrega`/`reasignar_entrega` (cuerpo armado con `replace()` sobre el prosrc vivo: solo agregan ERRCODE y la
  notificación; md5(prosrc) ff727cc7… → e4b71601… y 2883d4d8… → 2647876d…) y en las nuevas; push por
  `private.push_notificar` con accion_url `/repartidor` ("Tenés N entregas nuevas"; "Te quitaron una entrega" al
  anterior en la reasignación), en la misma transacción; cola en vivo por realtime sobre `notificaciones` (ya
  publicada, SELECT propio) — `entregas` NO se publica porque tiene datos de pacientes; ACL de funciones b8189120…
  (370) → 70a9dc38… (374); policies, relaciones, columnas, defaults y publicación sin cambio; probes P940 (gates por
  rol), P941 (lote atómico), P942 (asignar/reasignar + push + tablero), P943 (catálogo) — APLICADA en prod el
  2026-10-03 entre 13:41:13 y 13:41:15 UTC y verificada en sesión independiente 8/8. Dry-run: harness 1018 filas / 11
  rojas de deuda, P800 PASA, guard `do_sin_handler` 155 sobre 974 bloques DO; tsc 74, vitest 358. Orden de rollback
  global: `353_rollback` → `352_rollback` → `351_rollback` → … (`353_rollback` restaura los cuerpos ff727cc7…/2883d4d8…
  por replace inverso y borra las 4 funciones).)
  (352 = familia CP: catálogo QA de planes de visitador de GT — 3 configuraciones activas con UUID fijo: Bronce
  80f3c3e0… 250 GTQ / 20 visitas, Plata a383402a… 450 GTQ / 50, Oro 19a760ae… 900 GTQ / 120, las tres de 30 días;
  las 7 configuraciones inactivas de GT y planes_base no se tocan; planes_configuracion 110 → 113 filas; policies sin
  cambio — APLICADA en prod el 2026-10-03 entre 12:30:11 y 12:30:14 UTC. Dry-run: compra Bronce como proveedor.qa →
  pago pendiente 250 GTQ 20/30; aprobación como super_admin → `sumada` sobre la bolsa 6570afce (2 → 22 visitas, fin
  2027-06-12 → 2027-07-12), segunda aprobación `idempotente`.)
  (351 = familia CP: compra de plan de visitador por RPC — `solicitar_compra_plan_visitador(p_configuracion_id,
  p_comprobante_path)` y `aprobar_pago_plan_visitador(p_pago_id)` (DEFINER, `search_path=''`, sin EXECUTE para PUBLIC ni
  anon); columnas `planes_configuracion.visitas_incluidas/duracion_dias` y `pagos_proveedor.pvc_id/plan_visitas/
  plan_duracion_dias`; CHECK de `pagos_proveedor.estado` (pendiente/verificado/rechazado); policy "Proveedor crea pagos"
  endurecida (sin autoaprobación y sin `plan_visitador` directo); backfill de 2 `pvc_id`; huella de policies d1aae5eb… →
  70008237… (309); ACL de funciones b20ef072… → b8189120… (370); probes P937/P938/P939 — APLICADA en prod el
  2026-10-03 entre 12:03:38 y 12:03:41 UTC y verificada en sesión independiente 9/9. Orden de rollback global:
  `352_rollback` → `351_rollback` → `350_rollback` → … (`351_rollback` aborta si hay pagos con snapshot o
  configuraciones con visitas/duración cargadas: por eso primero va el de la 352).)
  (350 = familia 2, paso 3 (F2-c): las 17 policies `{public}` de las tablas de la WL_ANON_LEGACY → `TO authenticated`
  ("Publico lee paises activos" sigue `{public}`); las 17 dependen de la sesión y anon ya veía 0 por ellas (medido:
  paises 21 y configuracion_sistema 16 por sus propias policies de anon, el resto 0, sin 42501, igual después); huella
  de policies fc06b02c… → d1aae5eb… (309); contenido sin roles 2003cbbf… (309) sin cambios; probe P936 — APLICADA en
  prod el 2026-10-03 entre 11:06:51 y 11:06:53 UTC y verificada en sesión independiente 9/9 (1011 filas / 11 rojas de
  deuda, P800 PASA, guard `do_sin_handler` 155 sobre 969 bloques DO). **Allowlist TEMPORAL de P930:** SELECT de anon en
  cuentas_proveedor, empresas_proveedoras, pacientes, perfiles y recetas (sin policy de anon desde la 350); se quita en
  el paso EXECUTE de la familia 2, junto con el achique de la WL_ANON_LEGACY. Orden de rollback global: `350_rollback`
  → `349_rollback` → `348_rollback` → … → `342_rollback` (`350_rollback` exige d1aae5eb…).)
  (349 = familia 2, paso 2 (F2-b): 88 policies `{public}` de public → `TO authenticated`, en 41 tablas donde anon no
  tiene ningún privilegio (ni de tabla ni de columna), sin cambiar USING/CHECK/cmd/permissive; huella de policies
  96a7fabd… → fc06b02c… (309); contenido sin roles d0dfa2b9… (88) igual; probes P934 (censo) y P935 (funcional);
  P884 ajustado (fijaba `{public}` en 4 de estas policies) — APLICADA en prod el 2-oct-2026 20:53:20 UTC y
  verificada en sesión independiente 8/8 (1010 filas / 11 rojas de deuda, P800 PASA, guard `do_sin_handler` 155
  sobre 968 bloques DO). La precondición de `348_rollback` exige la huella 96a7fabd….)
  (348 = familia 2, paso 1 (F2-a): DROP de las 5 policies TO service_role (inertes: service_role tiene
  BYPASSRLS) — invitaciones_clinica_service_all, invitaciones_medico_service_all, "Service role all
  medico_clinicas", "Service role all push subscriptions", recordatorios_service_all; huella de policies de
  public/private/storage 75a9fb10… (314) → 96a7fabd… (309); 0 policies TO service_role; ACL intactas; probe
  P933 — APLICADA en prod el 2-oct-2026 20:29:16 UTC y verificada en sesión independiente 9/9 (1008 filas / 11
  rojas de deuda, P800 PASA, guard `do_sin_handler` 155 sobre 966 bloques DO). medico_clinicas y recordatorios
  quedan con 0 policies: authenticated no tiene privilegios vivos ahí desde la 346; el acceso es solo por
  service_role o DEFINER. `348_rollback` debe correr ANTES que cualquier rollback de la familia 1: su precondición exige las huellas finales
  de ACL/secuencias/funciones/defaults de la familia 1 y aborta si alguna ya se revirtió. En sentido inverso sí es
  independiente (los rollbacks 345/346 no miran policies TO service_role).)
  (347 = familia 1, paso 6: `SET search_path = ''` en `auto_configurar_planes_publicidad()`, la única SECURITY
  DEFINER de public/private sin search_path (función del trigger AFTER INSERT de `configuracion_pais`); sus 2
  referencias calificadas con `public.`; md5(prosrc) 6d1fe3a9… → 5949ef5d…; oid, dueño, ACL y trigger iguales;
  probes P931 (censo de DEFINER sin search_path) y P932 (funcional, con search_path hostil) — APLICADA en prod el
  2-oct-2026 20:02 UTC y verificada en sesión independiente 9/9 (1007 filas / 11 rojas de deuda, P800 PASA, guard
  `do_sin_handler` 155 sobre 965 bloques DO). **Técnica (patrón de la 347):** cuando el prosrc vivo tiene CRLF y
  el repo exige LF, el cuerpo nuevo se arma en SQL con `replace()` sobre el prosrc vivo y se ejecuta con
  `EXECUTE format(... %L)`, verificando el md5 de partida y el del resultado antes de ejecutar; el rollback hace el
  reemplazo inverso. Orden de rollback de la familia 1: `347_rollback` → `346_rollback` → `345_rollback` →
  `344_rollback` → `343_rollback` → `342_rollback`.
  346 = familia 1, paso 5: REVOKE de 102 privilegios muertos de authenticated — escrituras sin policy aplicable
  en 36 tablas (87 privilegios) + INSERT/UPDATE/DELETE en 5 vistas no actualizables (15) = 102; la 37ª tabla del
  recon, campana_vistas, queda en la allowlist (UPDATE por el upsert del front); de 113 muertos quedan 11 en la
  allowlist de P930; ACL de relaciones 855f0797… → deedb2e6…; escrituras de authenticated en public 239 → 137;
  probe P930 (censo) y P782 ajustado — APLICADA en prod el 2-oct-2026 19:38 UTC y verificada en sesión
  independiente 9/9 (1005 filas / 11 rojas de deuda, P800 PASA, guard `do_sin_handler` 155 sobre 963 bloques DO).
  345 = familia 1, paso 4: privilegios de las secuencias existentes de public — anon/PUBLIC sin nada (estaban
  en 32); authenticated sin SELECT/UPDATE (33) y con USAGE solo en las 11 del conjunto necesario; huella de
  secuencias 2b8162b5… → e1ef3639… (39); resto intacto; probes P928 (censo) y P929 (funcional) — APLICADA en
  prod el 2-oct-2026 19:07 UTC y verificada en sesión independiente 9/9 (1004 filas / 11 rojas de deuda, P800
  PASA, guard `do_sin_handler` 155 sobre 962 bloques DO). **Nota:** el header de `345_revoke_secuencias.sql` dice
  "currval/last_value = SELECT"; es inexacto para currval (Postgres lo acepta con USAGE o SELECT). Sin
  impacto: currval falla sin un nextval previo en la sesión, y last_value/setval sí quedan cerrados. El archivo
  no se edita porque ya está aplicado.
  344 = familia 1, paso 3: default privileges de postgres en public — tablas nuevas → authenticated solo
  SELECT/INSERT/UPDATE/DELETE; secuencias nuevas → authenticated solo USAGE; funciones sin cambio (ya cubiertas
  por la entrada global); pg_default_acl 1f07b802… → 7143eca7…; objetos existentes intactos; probes P926
  (catálogo) y P927 (funcional) — APLICADA en prod el 2-oct-2026 18:31:37 UTC y verificada en sesión
  independiente 9/9 (1002 filas / 11 rojas de deuda, P800 PASA, guard `do_sin_handler` 155 sobre 960 bloques DO).
  En la práctica la 344 y la 345 son independientes; la precondición de `343_rollback` exige TRU/TRI/REF en 0;
  todos independientes de 334-341.
  343 = familia 1, paso 2: REVOKE MAINTAIN de anon/authenticated/PUBLIC (authenticated en 114 relaciones de
  public, anon en 8; 122 tuplas); huella ACL c57c024f… → 855f0797…; probe P925 = censo global public+private;
  P800 extendido a MAINTAIN — APLICADA en prod el 2-oct-2026 18:11:49 UTC y verificada en sesión independiente
  8/8 (1000 filas / 11 rojas de deuda, P800 extendido PASA, guard `do_sin_handler` 155 sobre 958 bloques DO).
  342 = familia 1, paso 1: REVOKE TRUNCATE/TRIGGER/REFERENCES de anon/authenticated/PUBLIC en las 83
  relaciones de public que los tenían (242 tuplas, todas de authenticated); huella ACL 1df9d1b3… → c57c024f…;
  probe P924 = censo global — APLICADA en prod el 2-oct-2026 16:33:09 UTC y verificada en sesión independiente
  7/7 (999 filas / 11 rojas de deuda, P800 PASA, guard `do_sin_handler` 155 sobre 957 bloques DO).
  Plan de la familia: ver "Pendiente / ideas".
  341 = el mismo gate de relación de la 340 en `contexto_ia_paciente` (asistente IA en vivo), después de
  `gate_accion_phi`; md5(prosrc) 1eaf84a3… → 04fe590c…: `asistente_medico` y médicos de la clínica sin
  relación ya no reciben las notas por el asistente IA en vivo — APLICADA en prod el 2-oct-2026 15:59:42 UTC
  y verificada en sesión independiente 7/7 (998 filas / 11 rojas de deuda, P800 PASA, guard
  `do_sin_handler` 155 sobre 956 bloques DO). Orden de rollback: `341_rollback` → `340_rollback` →
  `339_rollback`.
  **Resumen IA de la última visita, fase 1: CERRADA y probada en prod el 2-oct-2026** — PR #15, merge
  4df0be1; caso feliz paciente 23 → `auditoria_ia` id 181; `sin_visita` paciente 8 sin auditar. **Fase 2
  (`cita_id` en recetas y órdenes de examen) pendiente.** 339 = RPC `contexto_ia_ultima_visita` — APLICADA en prod el 1-oct-2026 21:43:50 UTC;
  340 = gate de relación alineado con las ramas por paciente de `exp_select_medico` (`private.es_medico_de` /
  `private.medico_atiende_paciente`, COALESCE fail-closed → `no_pertenencia`), md5(prosrc) 339 a755ff5b… → 340
  7c97629d… — APLICADA en prod el 2-oct-2026 14:28:11 UTC; las dos verificadas en sesión independiente
  (995 filas / 11 rojas de deuda, guard 155). Edge
  `asistente-ia` v29 (md5 bb68fbb8…) desplegado en prod con modo `resumen_visita`; su rollback = redeploy del
  `index.ts` de `0043936^` (md5 4efc0997…). **Orden de deploy de la feature: edge ANTES que front** — el edge
  viejo responde 400 `app_desactualizada` al modo `resumen_visita`.
  338 = cierre de DELETE directo de examenes/ordenes_examen + REVOKE MAINTAIN ordenes_examen, ajusta P881,
  P884 y P905 — APLICADA en prod el 30-sep-2026 12:17:45 UTC y verificada en sesión independiente 9/9
  (huella dbb4786b…, 990 filas / 11 rojas de deuda, P800 PASA, guard 155). **P4 (revisiones inmutables)
  CERRADO: migs 334-338.** Orden de rollback: `338_rollback` → `337_rollback` → `336_rollback` → `335_rollback` (cada uno
  depende del estado que deja el siguiente);
  337 = resultados_scoped_select + rama examen_revisiones.archivo_url_anterior con puede_ver_historial_examen
  (el paciente no ve el archivo anterior, R3) — APLICADA en prod el 30-sep-2026 01:13 UTC y verificada en
  sesión independiente (988 filas / 11 rojas de deuda, guard 155 sobre 946 DO, tsc 78, qual 9f07449d…).
  336 = fix de la 335: liberación/reversión con FOR UPDATE + evento solo si cambió la fila; EX028
  normalizado espacios/tabs/saltos — APLICADA en prod y verificada en sesión independiente el
  26-sep-2026), **errcode `PA035`** (comercial),
  **`CA016`** (familia CAMPAÑAS: mig 358 `aprobar_solicitud_campana` → CA001 no es super_admin, CA002 solicitud
  inexistente, CA003 no está enviada, CA004 sin pago, CA005 más de un pago, CA006 pago rechazado, CA007 sin plan, CA008 la
  empresa no opera en el país; mig 359 `cotizar_campana`/`solicitar_pago_campana` → CA009 no es de tu empresa o rol,
  CA010 sin precio, CA011 no está en borrador, CA012 ya tiene pago, CA013 comprobante inválido; mig 361 → CA014 la
  duración supera los días del plan, CA015 fecha_fin anterior a fecha_inicio; el front los mapea en
  PagoCheckoutPage, PagosProveedoresPage y SolicitudesCampanaPage),
  **`DE010`** (delivery, mig 353: 42501 sin permiso; DE001 entrega inexistente o no visible, DE002 no está pendiente,
  DE003 el repartidor no es delivery activo de la empresa, DE004 repartidor de otra sucursal, DE005 entrega cobrada no
  se reasigna, DE006 no se reasigna desde ese estado, DE007 tanda vacía, DE008 tanda de más de 50, DE009 tanda con ids
  repetidos o NULL; el front los mapea en `src/farmacia/lib/gestionEntregas.ts`),
  **`CP018`** (familia CP, mig 351: `solicitar_compra_plan_visitador` → 42501 sin empresa o rol fuera de admin/editor,
  CP001 configuración no disponible, CP002 otro país, CP003 sin visitas/duración/precio, CP004 sin cuenta bancaria
  activa, CP005 moneda distinta a la de la cuenta, CP006 comprobante inválido, CP007 ya hay una compra pendiente;
  `aprobar_pago_plan_visitador` → 42501 no es super_admin, CP010 pago inexistente, CP011 no es plan_visitador, CP012 no
  pendiente, CP013 legacy sin snapshot, CP014 configuración inexistente, CP015 empresa no activa, CP016 no opera en el
  país, CP017 bolsa vigente ilimitada; libres CP008, CP009 y desde CP018; el front los mapea en
  `src/proveedor/lib/compraPlanVisitador.ts`),
  **`NT012`** (notas clínicas, mig 334 — APLICADA en prod, main b84edd4, probes P885-P911; front en
  feat/p4-334-front): NT001 = no autenticado, NT002 = no es el autor (o la nota no existe), NT003 = nota
  todavía abierta, NT004 = motivo vacío o > 500, NT005 = la corrección no cambia nada (esos 5 + NT011 =
  `corregir_nota_consulta`); NT006 = UPDATE directo sobre nota cerrada, NT007 = cambiar paciente/cita/
  médico/created_at, NT009 = campo de control (`cerrada_at`/`corregida_at`) puesto por el cliente
  (trigger guardia, UPDATE); NT008 = revisiones inmutables; NT010 = la nota no corresponde a la cita
  (guardia, INSERT); NT011 = no es médico con cuenta activa. El front muestra NT* y 42501 con
  `error.message` tal cual (`mensajeErrorNota`, `src/hooks/useConsultas.ts`),
  **`EX040`** (exámenes: EX035-EX039 = mig 369, catálogo del lab por RPC; EX001-EX020 órdenes por RPC, EX022 congelamiento de tipo/catalogo_id; EX021 reservado
  sin uso — el renombre del catálogo se cierra por grants; mig 332 — APLICADA en prod y verificada en sesión
  independiente el 25-sep-2026, probes P866-P878; mig 333 (REVOKE del INSERT directo + split de las ALL + M.8)
  — APLICADA en prod y verificada en sesión independiente el 25-sep-2026, probes P879-P884; P3 CERRADO
  (332 + front + 333); EX023-EX034 = mig 335 (corrección de resultados, historial inmutable) — APLICADA
  en prod y verificada en sesión independiente el 26-sep-2026, probes P897-P905),
  **`PR011`** (recetas: PR001-PR009 = emitir_receta; PR010 = receta cancelada no se despacha, mig 329
  — APLICADA en prod y verificada en sesión independiente el 25-sep-2026, probes P840-P847),
  **`SV004`** (signos vitales: SV001 = fuera de rango, SV002 = formato de PA, mig 330
  — APLICADA en prod y verificada en sesión independiente el 25-sep-2026, probes P848-P860;
  SV003 = toma vacía, mig 331 — APLICADA en prod y verificada en sesión independiente el 25-sep-2026,
  probes P861-P865)
  y **`PE005`** (expediente: PE001 = mig 291; PE002 = adjuntar sobre examen liberado y PE003 =
  no autenticado, mig 310; PE004 = sin autoridad para revertir una liberación, mig 311).
  `revertir_liberacion_examen` sobre un examen ya no liberado es **no-op** (`{ya_no_liberado:true}`),
  no un rechazo: no gasta errcode, igual que el `{ya_liberado:true}` de liberar. El "no autenticado" de las RPCs de médicos es `PC027`
  y **NO se reusa fuera de la familia PC**: el front distingue el módulo por el prefijo.
- **Módulo comercial —** (Mig 285, 6-sep:
  PA028 = check-in sobre visita que no está `planificada`; PA029 = doble checkout. Mig 286, 7-sep:
  `comercial_perfiles_sin_ficha(uuid)`, P639–P643; mig 287: `comercial_supervisores_del_pais(uuid)`,
  P644–P648; las dos son lectura y **no agregan errcode**: sin autoridad devuelven 0 filas, no
  42501. Mig 288, 7-sep: tarjeta pública del asesor, PA030 = sin ficha, P649–P661. La resolutora
  `tarjeta_publica_por_token` la ejecuta **sólo `service_role`** — ni `anon` ni `authenticated`:
  la llama una edge pública, `anon` nunca toca la base. Mig 289, 7-sep: foto de la tarjeta,
  PA031 = sin ficha, PA032 = el path no empieza con tu id, P662–P671. El bucket `tarjetas-asesor`
  es **privado y lo sirve la edge**: uno público entregaría una URL de objeto que responde para
  siempre, y apagar el consentimiento no la mataría. El molde `fotos-medicos` **no sirve** — su
  `fotos_medicos_public_select` es `SELECT` a `{public}` con la sola condición del `bucket_id`.
  Mig 290, 8-sep: validación de `fecha_ingreso` y `celular` en la ficha, PA033 = fecha fuera de
  rango, PA034 = celular sin 7–15 dígitos, P672–P677. **El límite superior de la fecha NO puede ser
  un CHECK**: depende de `CURRENT_DATE` y un CHECK exige expresión inmutable — por eso vive en la
  RPC, igual que PA026. El celular sí tiene CHECK estructural *además* del guard: la RPC devuelve
  el errcode que el front sabe pintar, y el CHECK ataja cualquier INSERT que no pase por la RPC.)
- **El gateway de `*.supabase.co` REESCRIBE el `Content-Type` del HTML. Medido 7-sep-2026 contra el
  deploy real.** Toda respuesta `text/html` de una edge sale por el gateway como **`text/plain`** y
  con **`Content-Security-Policy: default-src 'none'; sandbox`** agregado. Es su defensa
  anti-phishing sobre el dominio compartido y no se apaga desde el código. **Sólo interviene sobre
  `text/html`**: la contraprueba del mismo lote es que un `text/vcard` llegó intacto y sin CSP.
  Consecuencias medidas, las tres:
  - **Vercel NO lo repara**: proxea la respuesta de un rewrite externo arrastrando el `Content-Type`
    y el CSP del upstream tal cual.
  - **Vercel NO manda `x-forwarded-host`** a un destino de rewrite EXTERNO, y el gateway entrega el
    path como `/<nombre-funcion>` (sin `/functions/v1`). O sea que una edge no puede reconstruir su
    URL pública: ni el host ni el path le llegan.
  - **Un header PROPIO sí atraviesa el gateway intacto.** Por eso el tipo real viaja en
    `X-Tarjeta-Content-Type` y el proxy lo aplica como `Content-Type`.
  **Servir HTML público desde una edge de Supabase exige un proxy propio que corrija headers**
  (acá: `api/tarjeta.ts` en Vercel, que no decide nada — transporta y arregla headers; la lógica y
  el `service_role` se quedan en la edge). Con `text/plain` el navegador muestra el código fuente y
  el crawler de WhatsApp no lee los `og:`, que suele ser la única razón para servir HTML server-side.
- **Harness de RLS (`tests/rls/probes_escritura.sql`): OBLIGATORIO correr `python tests/rls/b2_guard.py`
  (o `npm run harness:guard`) al tocarlo.** Es el gate de estructura del frente B2: falla si aparece
  una sentencia DML/DDL fuera de un bloque `DO` con `EXCEPTION` handler, o si crecen los bloques `DO`
  sin handler. Está enganchado como hook de pre-commit en `.githooks/pre-commit`; en un clone nuevo
  hay que activarlo una vez con `git config core.hooksPath .githooks`.
- **Todo probe que modifica un fixture lo restaura a su snapshot y verifica la restauración.**
- **En un probe con PENDIENTE, las regresiones que no dependen de la migración se chequean ANTES de la rama PENDIENTE**
  (p. ej. que el super_admin vea menos de 21 claves): si no, una regresión real queda tapada por 'PENDIENTE mig N'
  (review del #46, 6-oct-2026).
- **Los fixtures que toman cuentas reales por posición (ORDER BY id LIMIT/OFFSET) las dejan modificadas para el resto de la
  transacción (C.2, P309-P316). Un probe nuevo no debe filtrar actores por rol o empresa sin tener esto en cuenta.**
- **Un actor que alimenta un INSERT con FK se elige por email o con EXISTS en la tabla destino de la FK, nunca por ORDER BY
  id: otros probes dejan vivas en la transacción filas sembradas con uuid aleatorio (P929, 6-oct). Y los actores que NO
  deben ver algo se neutralizan dentro del savepoint (P101 deja a medico.qa con cuenta_proveedor activa; P1009, 6-oct).**
- **Toda rama de FALLA publica un prefijo de PREFIJOS_ROJOS (harness_run.py); un handler WHEN OTHERS no publica verde sin
  mirar el SQLSTATE (b2_guard catchall_verde).** Un texto fuera de esos prefijos pasa como verde aunque describa una falla
  (P14 've N propios / M ajenos', P629 'RECHAZA', Pinvit 'OK? (…)'; censo de veredictos, 7-oct-2026).
- **Correr el harness SIEMPRE con `npm run harness`, nunca a mano.** El runner
  (`tests/rls/harness_run.py`) verifica exit code, salida no vacía, JSON parseable, piso de 680
  filas y cero veredictos vacíos. **Por qué**: el 2026-09-03 una corrida devolvió *exit 0 con la
  salida vacía* por un corte del cliente — indistinguible de un harness verde para quien lea el
  exit code. `npm run harness:selftest` prueba que esas cinco verificaciones disparan.
  Está enganchado al pre-commit junto al test del detector: los tres gates del hook son offline.
  **El runner CLASIFICA las rojas** (roja = el `verdict` empieza (mayúsculas, sin tildes) con alguno de `PREFIJOS_ROJOS`
  de `tests/rls/harness_run.py`: `ROJO`, `FALLO`, `REGRESION`, `FUGA`, `LEAK`, `PERMITIDO`, `VISIBLE`, `ERROR`, `BLOQUEADO?`) contra la
  lista `DEUDA` que vive en el código, hoy con **11 entradas**: una roja FUERA de la deuda es exit 1,
  y una entrada de la deuda que sale VERDE también (se arregló y hay que sacarla, o alguien la
  anestesió) — actualizar la lista es un acto deliberado, no un efecto colateral.
  **El CLI de supabase decide el formato Y la forma del JSON por DETECCIÓN DE AGENTE**: a CC le da
  `{"rows":[...]}`, a una PowerShell interactiva le da una TABLA con bordes, y con `--agent no
  --output json` da un array plano. El runner pide **`--output json` explícito**; nunca asumir el
  default. Una corrida que devolvió tabla NO midió nada.
  **`SUPABASE_TELEMETRY_DISABLED=1` y `DO_NOT_TRACK=1` van en el env del SUBPROCESO**: sin eso el
  CLI 2.100 escribe `~/.supabase/telemetry.json` antes de hacer nada y muere con EPERM en sandboxes
  sin escritura fuera del repo — la corrida no ocurre y parece un fallo de SQL.
  **Codex NO puede correr el harness** (sin egress a `api.supabase.com`). La verificación
  independiente de una corrida la hace Oscar en su terminal.
  **"Salida cruda" = lo que imprime el programa, copiado tal cual.** Nada de resúmenes propios
  presentados con formato de salida de programa. Todo cálculo propio va aparte y rotulado
  **"cálculo mío"**.
  **Por qué**: el harness corre en UNA transacción — una sentencia que revienta fuera de un handler
  no da rojo, MATA la transacción y la salida queda vacía, que se lee como "todavía no lo corrí".
  Pasó dos veces (18cf819 y el lote 1 de PA-FAILOPEN) y una de ellas tardó dos meses en detectarse.
  Baselines vivos: `top_level_dml_ddl=0` (excluye `pg_temp`), `cast_directo=0`, `do_sin_handler=155`
  (fase 2.2 CERRADA: los 55 bloques que escriben están envueltos, 211→193→175→157→156→155; los 155
  restantes sólo leen y publican, así que ya no son deuda; 1006 bloques DO en total al 7-oct-2026, rama
  harness/diag-fixture-fm, con 1097 / 11 rojas de deuda en esa rama y en harness/censo-veredictos (post14a, 7-oct-2026);
  la última cuenta de filas medida en esta memoria es **1111 / 1020 bloques DO / 11 rojas de deuda (post-372, 8-oct-2026)**; tsc
  74, vitest 424), `catchall_verde=205` (set_config de un handler `WHEN OTHERS` que publica un valor no rojo — no empieza
  con `PREFIJOS_ROJOS`; incluye flags de fixture que terminan en N/A — y solo queda exento si un IF/CASE de su camino mira
  el error; cada rama se exime solo por su propia condición, un ELSE nunca: cualquier error sale verde; techo, solo puede
  bajar; censo de veredictos, rama harness/censo-veredictos,
  7-oct-2026). Los probes de la 370, medidos ANTES de rebasarla sobre main (base 00e503e, tras la 369): 1004 → 1009
  bloques DO y 1089 → 1094 filas en el dry-run. Sobre main, con la 370 aplicada (post370, 7-oct-2026): **1102 filas /
  1011 bloques DO / 11 rojas de deuda**.
  **Regla de método: el harness NUNCA corre en paralelo con otra sesión que escriba o impersone contra prod**
  (las dos compiten por las mismas filas: deadlocks 40P01 que salen como rojos falsos). **P782 ajustado en la 346:** el DELETE directo sobre
  `visitas_agendadas` ahora da 42501 de privilegio (authenticated ya no tiene DELETE) y cuenta como OK, más fuerte
  que ROW_COUNT=0; cualquier otro error sigue siendo FALLO. **P929 y los dry-runs consumen valores de secuencia en prod**
  (`nextval` no es transaccional: el ROLLBACK no los devuelve) → huecos en los ids, esperado; no se devuelven
  con `setval` porque podría pisar un valor que prod entregó mientras tanto. El señalizador P516 del harness los publica, pero NO mide:
  el gate es el script. **El detector del guard tiene test propio (`tests/rls/b2_guard_test.py`,
  `npm run harness:guard:test`) y el hook lo corre ANTES del guard**: se equivocó tres veces en un día
  y llegó a tener un baseline inflado en 108, o sea permisivo. Un gate con el detector sin probar es
  decoración.
- **Migraciones: SIEMPRE `npx supabase db query --linked -f <archivo>`, NUNCA `db push`.** `db push`
  desincroniza `schema_migrations` (deuda desde la 047). Los `.sql` viven en `supabase/migrations/`
  (rollback en `supabase/migrations/rollback/`); los de `supabase/fixes/` se agregan con `git add -f`.
  **Desvío aceptado (familia 8):** los rollbacks de 334-373 viven en `supabase/migrations/`
  (`3XX_rollback.sql`), no en `supabase/migrations/rollback/`. Orden de rollback global vigente: `373_rollback` → `372_rollback` →
  `371_rollback` → `370_rollback` → `369_rollback` →
  `368_rollback` → `366_rollback` → `365_rollback` → … Forzados por huella: 369 antes que 368 Y antes que 367 (la
  precondición de `367_rollback` exige la ACL de public e2bb57f4…/2370, que la 369 cambió) y 368 antes que 366;
  `367_rollback` sigue conmutable con 366 y 368 (siempre después de 369). `369_rollback` exige revertir también el front
  de `useLaboratorio`. **373 (APLICADA el 9-oct) encabeza la cadena:** la precondición de `372_rollback` exige la huella
  de funciones post-372 5482f6de…/391, que la 373 cambió (027e10a7…/392) y `373_rollback` devuelve. **372 (APLICADA el 8-oct) va después:** la precondición de `371_rollback` exige la huella
  de funciones post-371 4c1f611c…/389, que la 372 cambió (5482f6de…/391) y `372_rollback` devuelve. **371 (APLICADA el 8-oct) va después:** la precondición de `370_rollback` exige la ACL de
  funciones post-370 4878afd5…/384, que la 371 cambió (4c1f611c…/389) y `371_rollback` devuelve. **370 (APLICADA el 7-oct) va antes que 369, 350 y 349:** `369_rollback` espera la ACL de funciones
  e5c9770e…/384, y con la 370 viva devolver las policies de la 349/350 a `TO public` le da a anon 42501 de FUNCIÓN
  (`get_auth_user_pais_id`) en configuracion_sistema (la landing la lee sin sesión) y otras 8 tablas (medido con P935/P936).
- **Los tests de edge (deno) NO corren en vitest ni en el pre-commit**: se corren a mano desde
  `supabase/functions/<fn>/` con `deno test --allow-net --allow-env --no-check` (asistente-ia: 17).
- **El CORS de `asistente-ia` sólo acepta `med.ezpayconnect.com`**: las pruebas de edges desde un preview
  de Vercel no funcionan. El caso feliz de una feature con edge se prueba en prod DESPUÉS del merge.
- **Nota de QA:** el paciente QA 23 se llama literalmente "Paciente". En un chequeo de PII del prompt de
  la IA, su nombre "aparece" por el encabezado fijo `PACIENTE:` de la plantilla — no es filtración.
  Medir como palabra entera y contar contra la plantilla, no por substring.

## GRANTs explícitos del Data API (obligatoria desde 30-oct-2026)
Supabase deja de otorgar GRANTs automáticos a los roles del Data API al crear objetos en `public`.
Desde esa fecha, una tabla/vista nueva **sin GRANT explícito nace inaccesible**. Reglas:
1. Toda migración con `CREATE TABLE` / `CREATE VIEW` en `public` lleva **sus `GRANT` explícitos en el
   mismo archivo** (no en otro, no "después").
2. **authenticated**: solo los privilegios que la tabla realmente usa (p. ej. `SELECT`, o
   `SELECT, UPDATE(col)`). **RLS habilitada + policies es obligatoria**; el `GRANT` NO reemplaza la RLS
   — son capas distintas (el grant abre la puerta, la RLS filtra las filas).
3. **service_role**: `SELECT, INSERT, UPDATE, DELETE`.
4. **anon**: **SIN grant.** El acceso sin sesión va solo por edge function o RPC `SECURITY DEFINER`.
   Excepciones → lista blanca `WL_ANON_LEGACY` del probe **P800**, cada una justificada.
5. **Prohibido `ALTER DEFAULT PRIVILEGES` para restaurar el comportamiento viejo** (re-otorgar en masa).
   Los `ALTER DEFAULT PRIVILEGES` que **RESTRINGEN** (migs 298/301) son válidos.
6. **VIEW expuesta = mismos criterios** que una tabla (grants explícitos por rol; anon sin grant).
7. **Probe P800 (`npm run harness:grants`) debe pasar antes de commitear cualquier migración que
   cree tabla/VIEW** (gate global de grants; archivo `tests/rls/probe_grants_p800.sql`).
8. **Verificación post-apply desde una sesión distinta**: con `information_schema.role_table_grants` /
   `has_table_privilege`, confirmar que los grants son **exactamente** los esperados (ni de más ni de menos).
9. **Defaults vigentes desde la mig 344** (lo que postgres crea nace así): tabla nueva en public →
   authenticated `SELECT, INSERT, UPDATE, DELETE` (sin TRUNCATE/TRIGGER/REFERENCES/MAINTAIN); secuencia nueva →
   authenticated solo `USAGE`; función nueva de public → `EXECUTE` para authenticated y service_role, **no**
   para PUBLIC ni anon. Toda tabla nueva que necesite **menos** que SELECT/INSERT/UPDATE/DELETE para
   authenticated debe hacer el `REVOKE` explícito en su migración.
10. **Toda función nueva de `private`** nace con `EXECUTE` **solo para postgres** (entrada global de
   pg_default_acl sin PUBLIC; private no tiene entrada propia): si la usa una policy o una RPC de authenticated,
   su migración lleva `GRANT EXECUTE … TO authenticated` explícito (sin él, la policy lanza 42501).
11. **Tabla nueva con INSERT directo de authenticated y `DEFAULT nextval`** (serial, no IDENTITY): necesita
   `USAGE` en su secuencia para authenticated. El default de la 344 lo da; si la migración lo revoca, tiene
   que reponerlo con un `GRANT USAGE ON SEQUENCE … TO authenticated` explícito. Además va una **receta en P929**
   (INSERT real como un actor que su policy permite): P929 da ROJO a propósito si entra al conjunto necesario
   una tabla sin receta. Las columnas IDENTITY no necesitan grant (su nextval interno no chequea privilegios).
12. **Un privilegio de escritura para authenticated se otorga SOLO junto con la policy que lo habilita** (desde la
   346). Un privilegio sin policy permisiva aplicable (o una policy que lo deja muerto) hace salir **P930 ROJO**.
   Cualquier excepción va a la allowlist de P930, con comentario del motivo. P930 también sale ROJO si una entrada
   de la allowlist deja de estar muerta: hay que sacarla. Ojo: un `upsert` (`ON CONFLICT DO UPDATE`) exige UPDATE
   aunque no haya conflicto.
13. **Toda función SECURITY DEFINER nueva lleva `SET search_path = ''`** y todas sus referencias calificadas con
   schema (tablas, funciones, tipos; `pg_catalog` no hace falta). Sin eso, resuelve los nombres con el search_path
   del llamante y corre como el dueño (secuestro de nombres). **P931 sale ROJO** si queda alguna DEFINER de
   public/private sin search_path fijo (desde la 347).
14. **Toda policy nueva se crea `TO authenticated`** (o con el rol explícito que corresponda), **nunca `TO public`**,
   salvo una lectura pública deliberada en una tabla de la WL_ANON_LEGACY. Una policy `{public}` en public fuera de
   esas tablas hace salir **P934 ROJO** (desde la 349). Las `{public}` de storage (lectura pública de buckets) no cuentan.

## Modelo de identidad / helpers
- mi_empresa_proveedor() → empresa_id del proveedor logueado desde cuentas_proveedor (tipo-agnóstica; cubre los 4 tipos: farmacia, laboratorio_clinico, laboratorio_farmaceutico, empresa_afin).
- get_auth_user_rol() / get_auth_user_pais_id() → rol y país del usuario desde perfiles.
- Gate de país estándar: super_admin (cualquier país) O admin_pais con get_auth_user_pais_id() = p_pais_id (rechaza con 42501 no_autorizado si es admin de otro país).

## Frente cerrado: métricas de publicidad (HEAD final 9fb665e, todo en prod)
Causa raíz: RLS super_admin-only sobre campana_metricas + vistas security_invoker → métricas de anuncios en 0 para proveedor y para panel de país. Vínculo proveedor↔campaña se hacía por título (frágil).

Solución (RPCs SECURITY DEFINER, sin ampliar RLS):
- metricas_campana_proveedor() — scope mi_empresa_proveedor(). Consumida por useMetricasCampana / PublicidadMetricasPage (los 4 tipos).
- metricas_campana_pais(p_pais_id) — con el gate de país; extendida para devolver empresa_id / empresa_nombre / empresa_tipo (desglose por empresa). Consumida por PaisDashboardPage y useMetricasCampanaAdmin.
- RPC de frequency cap scoped a auth.uid() (antes devolvía [] y el cap nunca se aplicaba).
- campanas_publicitarias + empresa_id y solicitud_campana_id (con backfill 14/14). Los 3 orígenes de creación de campañas setean el dueño (aprobar_solicitud_campana RPC, PagosProveedoresPage, y el form manual admin = house-ad con empresa_id NULL a propósito).
- CHECK chk_campana_dueno: solicitud_campana_id IS NULL OR empresa_id IS NOT NULL (una campaña nacida de solicitud debe llevar dueño; house-ads siguen válidas).

Commits del frente: 50ee110 (A) · 44ef4e3 (B1) · 747d8bd (B2) · 6067921 (B3) · 352097b (C) · a9a2618 (CHECK) · 9fb665e (desglose por empresa).

Detalles a recordar:
- Los .sql de fixes viven en supabase/fixes/ y se agregaron con git add -f (el dir puede estar en .gitignore) — confirmar siempre que quedan en origin.
- El overview de todos los países (useMetricasCampanaAdmin.fetchMetricasPais → vista v_metricas_campana_pais) se dejó como está: solo super_admin, que sí pasa la RLS.

## Pendiente / ideas
- (Producto, no código) Prompts de video sobre el software médico para mostrar a futuros clientes.
- **FAMILIA 2 (policies) EN CURSO.** Recon del 2-oct-2026 sobre 092c863 (`tmp/recon_fam2/`): 314 policies (271 public,
  43 storage), todas permissive; 109 `TO public`, de las que solo las de la WL_ANON_LEGACY y 3 de lectura pública
  de storage las evalúa anon; las 21 funciones con EXECUTE para anon lo reciben VÍA PUBLIC (authenticated también),
  ninguna se llama por RPC desde el cliente. Plan: **F2-a** policies TO service_role inertes (348, **APLICADA**) → **F2-b** las 88
  `{public}` de public que anon no alcanza → TO authenticated (349, **APLICADA**; P884 ajustado) → **F2-c** las
  18 `{public}` de las tablas de la WL_ANON_LEGACY salvo "Publico lee paises activos" (17 cambian) → TO authenticated, con probe de anon (0 filas
  sin 42501) (350, **APLICADA**; P936; allowlist temporal de P930 con el SELECT de anon en 5 tablas) → **F2-d** quitar el UPDATE directo de visitas_agendadas (2 policies + el privilegio) (364, **APLICADA**) → **F2-e** decisiones
  de producto (exp_superadmin_insert: super_admin crea notas a nombre de cualquier médico; claves bancarias de
  configuracion_sistema visibles para todo authenticated) (365 + 366, **APLICADAS**) → **F2-f** con front (campana_vistas sin UPDATE y fuera de la allowlist de P930,
  367 **APLICADA**; configuracion_sistema sin admin_pais, 368 **APLICADA**; catalogo_lab_all partida, 369 **APLICADA** — **F2-f CERRADA**) → **sigue:** **F2-g** opcional (partir ALL;
  `(select auth.uid())`) → **ÚLTIMO: EXECUTE** = mig 370 (**APLICADA el 7-oct-2026 19:18 UTC**; ver la entrada
  370 arriba). Corrección del recon del 6-oct: las helpers de policies YA tienen authenticated y service_role explícitos,
  así que el REVOKE de PUBLIC/anon no le rompe nada a authenticated; el riesgo de este paso es solo para anon, y anon ya no
  evalúa ninguna policy con funciones desde las 349/350. P800 extendido a `pg_proc` en la misma rama. Lo que queda para
  la **373+** (los números 371 y 372 los tomó GL-02): achicar WL_ANON_LEGACY y sacar las 5 entradas temporales de anon de la allowlist de P930 (350) (ver backlog). Hallazgos a conservar: `transacciones` se lee desde el front (AdminEzPayPage y las
  ReportesEzPayPage) y siempre devuelve [] porque tiene 0 policies → familia 7; configuracion_pais: el `true` de
  authenticated anula el filtro `activo` para logueados; 123 policies con `auth.uid()` sin `(select …)` (performance).
  F2-d (mig 364, 5-oct): visitas_agendadas sin UPDATE directo; las escrituras van solo por las 7 RPCs DEFINER.
  F2-e (migs 365 y 366, 5/6-oct): el super_admin no escribe notas clínicas; cuenta de depósito y claves bancarias acotadas.
  F2-f CERRADA (migs 367, 368 y 369, 6-oct): campana_vistas sin UPDATE; configuracion_sistema con las 21 claves solo para el
  super_admin; examenes_catalogo sin escritura directa (catalogo_lab_all partida; escrituras por 3 RPCs DEFINER con el gate
  `tiene_permiso('catalogo_examenes_editar')` adentro, no por policy con WITH CHECK que llame funciones DEFINER — lección
  rls-with-check-definer-flaky-postgrest). EXECUTE = mig 370 (**APLICADA** el 7-oct); sigue la 373+ (anon en 6 tablas; la 371 y la 372 son GL-02).
  F2-g sigue opcional.
- **FAMILIA 1 (privilegios) CERRADA: 342-347 aplicadas.** El paso de EXECUTE (antes "348") pasa a ser el ÚLTIMO de
  la familia 2, porque su prerequisito (sacar de `TO public` las policies que anon evalúa) es trabajo de policies.
  Plan original (recon del 2-oct-2026 sobre f29f974: sin fuga explotable
  por API; el problema de fondo son los default privileges de postgres en public, que dan los 8 privilegios de
  tabla a authenticated en cada tabla nueva):
  342 TRUNCATE/TRIGGER/REFERENCES (**APLICADA**) → 343 MAINTAIN (**APLICADA**; authenticated en 114
  relaciones, anon en 8) → 344 default privileges de postgres en public (**APLICADA**; tablas sin
  TRU/TRI/REF/MAI, secuencias sin SELECT/UPDATE; funciones ya cubiertas) → 345 secuencias existentes
  (**APLICADA**; anon/PUBLIC sin nada; authenticated sin SELECT/UPDATE y con USAGE solo en las 11 del conjunto
  necesario. Regla del conjunto: secuencia de un `DEFAULT nextval` en una tabla de public con INSERT de
  authenticated en la ACL y una policy INSERT/ALL para authenticated o public. Huella 2b8162b5… → e1ef3639…;
  P928 = censo que recalcula el conjunto desde el catálogo, P929 = funcional con INSERT real en las 11 y ROJO
  a propósito si entra una tabla sin receta) → 346 privilegios muertos (**APLICADA**; 102 revocados de 113:
  escrituras de authenticated sin policy aplicable en 36 tablas (87 privilegios) + escrituras en 5 vistas no
  actualizables (15) = 102; la 37ª tabla del recon, campana_vistas, queda en la allowlist (UPDATE por el upsert
  del front);
  ACL 855f0797… → deedb2e6…; escrituras de authenticated 239 → 137; P930 = censo con allowlist de 11 comentada:
  UPDATE de `campana_vistas` (upsert del front), SELECT de `recordatorios` y `transacciones` (las lee el front),
  SELECT de anon en `liquidaciones_comision` (WL_ANON_LEGACY, lección 284), y SELECT de 7 tablas sin otro
  privilegio que P800 regla (b) obliga a conservar — cache_biblioteca, confirmaciones_receta, medico_clinicas,
  medico_correlativos, planes_features, planes_limites, resumen_comisiones —: decisión 2-oct-2026 de no agrandar
  WL_AUTH, diferido al paso de EXECUTE, último de la familia 2) → 347 `search_path` de `auto_configurar_planes_publicidad` (**APLICADA**;
  `SET search_path = ''`, única DEFINER sin search_path; sus 2 referencias calificadas con `public.`; md5(prosrc)
  6d1fe3a9… → 5949ef5d…; cuerpo armado con `replace()` sobre el prosrc vivo para preservar sus CRLF; P931 = censo
  de DEFINER sin search_path, P932 = funcional con search_path hostil) → EXECUTE de PUBLIC/anon en funciones:
  movido a la familia 2 (último paso).
  P800 ya extendido a MAINTAIN (343: reglas (c)/(d) + nueva (i), authenticated/PUBLIC sin TRU/TRI/REF/MAI en
  ninguna relación de public); extendido a funciones en la rama de la 370 (2797e06: reglas (j)-(m) sobre `pg_proc`).
  Hallazgos del recon para no perderlos: **P800 no consultaba `pg_proc`** (lo hace desde 2797e06, mig 370); 21 funciones de public con
  EXECUTE para anon (10 helpers DEFINER usados por policies `TO public`, 9 de trigger, 2 utilitarias); 7 tablas
  con RLS y 0 policies con todos los privilegios (cache_biblioteca, confirmaciones_receta, medico_correlativos,
  planes_features, planes_limites, resumen_comisiones, transacciones).
  **Corrección del recon (344):** el EXECUTE de PUBLIC en funciones NUEVAS ya estaba cerrado por una entrada
  GLOBAL de pg_default_acl (`postgres|f {postgres=X/postgres}`; el recon la pasó por alto porque filtró entradas
  sin anon/authenticated/PUBLIC); las 21 funciones de public con EXECUTE para PUBLIC son anteriores o tienen
  GRANT explícito (siguen siendo el último paso de la familia 2). `supabase_admin`: MEDIDO, postgres no puede alterar sus defaults
  (42501 "permission denied to change default privileges"); inerte porque las migraciones crean como postgres, y
  P724 lo vigila. Defaults de postgres en `storage` (anon/authenticated con todo): inertes, postgres no tiene
  CREATE en storage.
- **FAMILIA CP (compra de planes de visitador): 351 + 352 APLICADAS, front en main (PR #27, merge a00f804).** El cupo
  del front se calcula POR PAÍS con el criterio de `private.gate_visita_pais` (`cupoPorPais`, lote demo 1: hallazgo A3
  del review #27 cerrado).
  Decisiones (Oscar, 3-oct-2026): pago por transferencia con aprobación manual del super_admin; el precio, la moneda,
  las visitas y la duración salen del catálogo del país en el servidor (el monto de la URL no se usa); con una bolsa
  vigente en el país la compra SUMA visitas y EXTIENDE la fecha_fin (dos bolsas superpuestas no suman cupo); no se vende
  ilimitado; la aprobación es una RPC atómica e idempotente que activa la capacidad 'visitadores' (permanente); el
  visitador solo ve su bolsa (cupo y vigencia), sin catálogo; se quitó el toggle anual de `/planes-visitador` (la compra
  cobra el precio mensual). **Ventana rota:** entre el apply de la 351 y el deploy del front, el checkout viejo de
  plan_visitador falla (la policy ya no admite el INSERT directo). Backlog: comprobante huérfano cuando la RPC rechaza
  (falta una policy DELETE acotada en el bucket `comprobantes`); monto libre en el checkout de campana/plan_laboratorio/
  plan_farmacia (misma solución por RPC); rechazar un pago sigue sin RPC (UPDATE directo del super_admin); la columna
  `planes_visitador_contratados.visitas_usadas` está muerta (el cupo se cuenta con `private.pvc_usadas`). El servidor
  usa CURRENT_DATE en UTC: en GT una bolsa vence a las 18:00 hora local de su último día. Evaluar pasar el criterio a la
  zona horaria del país (gate de visitas + RPCs); el front lo replica en `esBolsaVigente`/`hoyUTC`
  (`src/proveedor/lib/compraPlanVisitador.ts`) y hay que cambiar los dos juntos.
- **DELIVERY — lote demo 1 (mig 353 APLICADA + front en `fix/lote-demo-1`).** Decisiones (Oscar, 3-oct-2026): el
  reparto es por tandas durante el día; el gerente ve un tablero con la carga de cada repartidor; asigna en tanda (máx
  50 entregas, de una sola sucursal, porque cada repartidor es de una sucursal) y reasigna; el repartidor tiene la cola
  en vivo, con aviso push al asignarle, y un mapa con sus pendientes ordenadas por cercanía a su ubicación actual — la
  ubicación se usa solo en el dispositivo, no se envía al servidor. Backlog: el autochequeo de `353_rollback` no
  remide grants por columna ni `pg_default_acl`; `fallidas_hoy` usa `updated_at` (no existe `fallida_at`); "hoy" del
  tablero en UTC (igual que la familia CP); aviso al paciente del estado de la entrega; ruta optimizada y tracking en
  vivo (roadmap).
- (Familia 6) La secuencia de `planes_publicidad` está desfasada (medido 2-oct-2026: `last_value` 1, `max(id)` 3):
  un INSERT por default choca con la PK (23505). Corregir con `setval` en una migración aparte (lo detectó el
  dry-run A2 de la 345; P929 siembra su plan con id explícito).
- (Familia 6/2) `limpiar_cache_biblioteca_expirada()` (INVOKER) escribe `cache_biblioteca` y no tiene llamadores
  (ni front, ni edges, ni pg_cron); desde la 346 daría 42501 si alguien la llama como authenticated → decidir si
  se borra o pasa a DEFINER.
- (Familia 7) Bugs latentes que la 346 vuelve visibles (42501 en vez de un "éxito" silencioso con 0 filas):
  `useProveedorAuth.ts:171` UPDATE de `cuentas_proveedor`; `useFacturas.ts:80` DELETE de `facturas`;
  `useRecetas.ts:197` UPDATE de `recetas`.
- (Familia 3/4) FK `examenes_orden_id_fkey` sigue `ON DELETE CASCADE`: tras la 338 sólo la alcanzan
  postgres/service_role (borrar una orden arrastra sus exámenes, completados incluidos).
- (Familia 4, review #47 M-2, candidato a mig 373+; la 370 fue EXECUTE y la 371-372 GL-02) Las RPCs de la 369 normalizan nombre y categoría con `btrim`, que solo
  recorta espacios: tabs y saltos de línea pasan por API (el front hace `.trim()`, que sí los recorta). La 336 ya normaliza
  espacios/tabs/saltos para EX028: usar el mismo criterio en `crear_examen_catalogo` y `actualizar_examen_catalogo`.
- (Familia 2/4) `catalogo_read_activos` no filtra por tipo de empresa: `private.lab_en_mi_pais` solo compara el país. Hoy no
  se explota porque las RPCs de la 369 exigen `laboratorio_clinico`, pero una fila activa con `laboratorio_id` de otro tipo
  de empresa (sembrada por postgres/service_role) sería visible para el médico.
- (Familia 4) `examenes.updated_at` no se actualiza al corregir ni al liberar.
- (Familia 7) El lab no tiene vista del historial de revisiones; "Ver archivo anterior" aparece en
  revisiones que no cambiaron el archivo.
- (Familia 8, backlog del harness, 6-oct-2026) ~~P87/P97/P101/Pinvit no borran las cuentas_proveedor que crean (P101 deja a
  medico.qa como 'Lab Inv', y un fixture posterior lo reasigna a admin)~~ **resuelto en la rama harness/diag-fixture-fm
  (7-oct): ahora las borran y lo verifican (`DET_trio_cleanup` / `DET_pinvit_cleanup` = OK con esperadas + restantes=0)**; P639/P777/P788/mig 311 (x2)/P799 dejan perfiles
  'medico' sin fila en medicos; algún fixture deja un admin_pais HN "real" dentro de la transacción (en prod no existe);
  `probe.p1009_det` se setea pero no se publica en el result set; `probe.p1008_det` tampoco; en P1009 el fallback de
  `a_pno` excluye la cuenta de `a_farm` pero no su empresa.
- (Familia 8, backlog del harness, 7-oct-2026) `catchall_verde = 205`: bajar por lotes; al bajar, actualizar
  `BASELINE_CATCHALL_VERDE` en `b2_guard.py` y el texto de P516. Fuera del guard: ~52 variables verdes asignadas en un
  handler y publicadas después, y keys dinámicas.
- (Familia 8, backlog del harness, 7-oct-2026) P17 apagado: `crear_cita` se llama con médico y clínica NULL, el gate
  nuevo lo rechaza y el catch-all lo convierte en N/A; el caso agendada → solicitada no se ejercita. Necesita recon del fixture.
- (Familia 8, backlog del harness, 7-oct-2026) P52 es un positivo débil ('RLS permitió; faltó dato: 23502'): la fila
  nunca se inserta.
- (Familia 8, backlog del harness, 7-oct-2026) Fixture pe (`probes_escritura.sql` ~L3691): sus INSERT en
  `productos_empresa` fallan dentro del catch-all → `pe_ready='0'` → P195/P196/P197/P203 publican N/A sin medir. El
  handler no guarda SQLSTATE. Recon pendiente.
- (Familia 8, backlog del harness, 7-oct-2026) `bs_ready` (~L5317): P304/P305/P307 en N/A indeterminado (el error queda en
  `probe.bs_err`, que no se publica).
- (Familia 8, backlog del harness, 7-oct-2026) `catchall_verde` solo mira el total: un arreglo + un catch-all nuevo en el
  mismo commit no lo detecta → congelar como allowlist de firmas (salida de `--listar`) en vez de un número. Además mezcla
  flags de fixture (`*_ready='0'`, `'ERR:'||SQLSTATE`) con veredictos: separar las dos cuentas (o resolverlo con la allowlist).
- (Familia 8, backlog del harness, 7-oct-2026) El detector de `catchall_verde` no analiza `set_config` cuyo valor es una
  expresión CASE, ni variables verdes asignadas en el handler y publicadas después, ni keys dinámicas. Límites que quedan
  tras la review de seguimiento: un CASE dentro de la condición de un IF rompe la pila; mencionar el error no es
  discriminarlo (`IF SQLSTATE IS NOT NULL` exime); `_vars_de_error` no respeta el orden de las asignaciones; un
  `set_config` con literal `E'…'` no se detecta; el campo `exc` de los frames no se usa.
- (Familia 8, backlog del harness, 7-oct-2026) P13 (L479), P18 (L560) y P485 (L10136): su ELSE publica BLOQUEADO para
  cualquier SQLSTATE distinto del esperado → pasar a FALLO (verdes falsos latentes; hoy salen por su rama 42501).
- (Familia 8, backlog del harness, 7-oct-2026) P44 matchea el mensaje exacto del RAISE de `administrar_visita`: cuando se
  toque esa función, darle ERRCODE propio y matchear por SQLSTATE.
- (Familia 8, backlog del harness, 7-oct-2026) Nits: P757 con la 366 revertida dice "PENDIENTE mig 368"; el `re.sub` de
  comentarios `--` en `b2_guard.py` trunca un `--` dentro de un literal (hoy 0 casos).
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 3) El precheck de la 370, P800 (l) y P1015 solo miran
  `pg_policy` como dependientes de funciones: un DEFAULT, CHECK, vista security_invoker o WHEN de trigger nuevos que llamen
  a una helper sin GRANT pasarían en verde y darían 42501 en runtime (hoy 0 casos vivos). Ampliar (l) a `pg_depend` de
  `pg_attrdef` / `pg_constraint` / `pg_rewrite` / `pg_trigger`.
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 4) Ningún gate verifica que los llamadores de
  `resolver_medicamento_id` y `es_staff_calendario_clinica` sigan siendo SECURITY DEFINER (hoy 7 de 7); P1018 no dispara
  `trg_farmed_resolver_medid`. Agregar un probe que lo exija.
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 5) P1017 acepta 0 filas (~L33896/33910): solo comprueba que
  no haya 42501. Si `entrega_visible` devolviera siempre false, farmacia.qa vería 0 evidencias y el probe diría OK. Sembrar
  una evidencia propia y exigir n >= 1.
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 6) `pg_temp.e370_estado()` no excluye funciones de
  extensiones (~L17226) y el de P800 sí: si se instala una extensión en public, harness y P800 discrepan. Latente.
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 7) El snapshot de P1018 no cubre
  `empresas_proveedoras.estado` ni `empresa_paises_operacion`, que el probe modifica; hoy queda dentro del savepoint P0999,
  pero no cumple "restaura y verifica la restauración".
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 8) `370_rollback.sql` usa un salto de línea literal dentro de
  `E'…'` (:31, :123) y la mig usa `E'\n'`: la huella depende del fin de línea en disco (hoy eol=lf, 0 CR). Solo falla con
  una copia en CRLF.
- (Familia 8, backlog del harness, 7-oct-2026, review #53 punto 9) Lógica duplicada: listas 38/22 en E370_FX y el rollback
  (P800 ya no las tiene desde 2b63b72); la regla "cada rol de la policy ejecuta sus funciones" en P1015 y P800 (l); la SQL de
  huellas 4 veces. La 371 va a tener que tocar 3-4 copias: centralizar en un helper de `pg_temp`.
- (Producto) `administrar_visita('rechazar')` no valida el estado de la visita (definición viva): rechaza visitas
  completadas, canceladas o ya rechazadas. Recon de producto post-11-oct. Detectado en la review de
  harness/diag-fixture-fm (m5 descartado, ver c38862e).
- (Familia 8) ~~P800 salta las foreign tables~~: alineado en la rama de la 370 (relkind incluye 'f').
- (Familia 2, **mig 373+**; los números 371 y 372 los tomó GL-02) REVOKE SELECT de anon en las 6 tablas de la WL_ANON_LEGACY que ya no usa (cuentas_proveedor,
  empresas_proveedoras, liquidaciones_comision, pacientes, perfiles, recetas): anon no evalúa ninguna policy sobre ellas
  desde la 350 (privilegio muerto, 0 filas). WL_ANON_LEGACY 8 → 2 (quedan configuracion_pais y configuracion_sistema, que
  usan la landing y los registros sin sesión); P930 sin esas 6 entradas (las 5 temporales de la 350 + liquidaciones_comision);
  ajustar P936 (anon pasa a 42501 de privilegio en las 6), la lista de tablas de P741 y el baseline de P800. Recon: las
  lecturas del front a esas tablas son todas post-login.
- (Familia 8) ~~P254/P255 (cadena vg1→va2) insertan `visitas_agendadas` con `tipo_visita='presencial'`, que el CHECK
  `tipo_visita_valido` rechaza~~: resuelto en main por 45959a7 (tipo_visita válido en P254-P258/P322-P327). P1018 usa
  'presentacion_producto'.
- (Familia 8, no urgente) `.gitattributes` ya tiene `* text=auto eol=lf` (476b925; 0 blobs renormalizados),
  pero ~640 archivos siguen en CRLF en disco (checkouts viejos con `core.autocrlf=true`). Para pasarlos a LF
  hay que refrescar el checkout (`git rm --cached -r . && git reset --hard`) en un momento sin cambios locales.
- (Familia 7) `AsistenteIA.tsx` no muestra el motivo de los 403/400 (usar `src/lib/errorAsistenteIA.ts`); el
  sidebar filtra por `'asistente'` y no por `'asistente_medico'` (`Sidebar.tsx:55-57`).
- (Familia 7, resumen IA) Los vitales del resumen se muestran sin fecha de toma; el título "Datos faltantes
  en la nota" (`ResumenUltimaVisita.tsx:45`) incluye campos de la ficha → renombrar a "Datos faltantes";
  admin_clinica ve el botón "Iniciar consulta" en `/pacientes/:id/detalle` (`PacienteDetallePage.tsx:401`);
  "Dr. Dr." duplicado en Historial de Consultas (el "Dr." se antepone en `PacienteDetallePage.tsx:593`).
- (GL-02, decisión de Oscar 8-oct-2026, mig 372) `aceptaciones_legales.usuario_id` → `auth.users` ON DELETE RESTRICT: con
  aceptaciones registradas, `auth.admin.deleteUser` falla. La cancelación de cuenta va a necesitar un flujo de
  anonimización (qué se conserva de la evidencia legal y cómo se desvincula del usuario). Hoy los únicos borrados de usuarios
  del repo son rollbacks de altas en la misma request (recon de la 372, punto 5). **Alcance (review #55 n3):** a un paciente
  ya no se lo puede borrar hoy (`pacientes_auth_user_id_fkey` es NO ACTION); el bloqueo nuevo cae sobre las cuentas con
  perfil o de proveedor que tengan aceptaciones.
- (GL-02, front, review #55 n4) Alta de proveedor (`src/proveedor/hooks/useProveedorAuth.ts`: `signUp` L96 →
  `registrar_proveedor` L109): la aceptación de `condiciones_profesionales` va DESPUÉS de `registrar_proveedor`; antes la
  cuenta todavía no tiene `cuentas_proveedor` y `aceptar_textos_legales` da LG006. En el paciente no pasa:
  `handle_new_paciente` (mig 230, AFTER INSERT ON auth.users, solo si la metadata trae `tipo = 'paciente'`) crea la fila de
  `pacientes` en el mismo `signUp`.
- (Corrección, 9-oct-2026) El "Escribile" visto el 9-oct era un bundle viejo en el celular: main y prod (571d39a) dicen
  "Escríbele". Backlog: verificar que el service worker de la PWA se actualice en iOS.
- **(QA-MANUAL, cleanup pre-go-live)** `auditoria_ia` id **181** (2026-10-02 15:38:37 UTC, medico.qa →
  paciente 23): `DELETE FROM public.auditoria_ia WHERE id = 181;`
