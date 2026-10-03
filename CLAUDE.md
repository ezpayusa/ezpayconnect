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
- **Próximos números libres: probe `P944`** (global, no por módulo; P906-P907 usados por la mig 336, P912-P913
  por la 337, P914-P915 por la 338, P916-P920 por la 339/340, P921-P923 por la 341, P924 por la 342, P925 por
  la 343, P926-P927 por la 344, P928-P929 por la 345, P930 por la 346, P931-P932 por la 347, P933 por la 348,
  P934-P935 por la 349, P936 por la 350, P937-P939 por la 351, P940-P943 por la 353), **migración `354`**
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
  **`EX035`** (exámenes: EX001-EX020 órdenes por RPC, EX022 congelamiento de tipo/catalogo_id; EX021 reservado
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
- **Correr el harness SIEMPRE con `npm run harness`, nunca a mano.** El runner
  (`tests/rls/harness_run.py`) verifica exit code, salida no vacía, JSON parseable, piso de 680
  filas y cero veredictos vacíos. **Por qué**: el 2026-09-03 una corrida devolvió *exit 0 con la
  salida vacía* por un corte del cliente — indistinguible de un harness verde para quien lea el
  exit code. `npm run harness:selftest` prueba que esas cinco verificaciones disparan.
  Está enganchado al pre-commit junto al test del detector: los tres gates del hook son offline.
  **El runner CLASIFICA las rojas** (roja = el `verdict` empieza con `ROJO` o `FALLO`) contra la
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
  restantes sólo leen y publican, así que ya no son deuda; 974 bloques DO en total al 3-oct-2026, con P940-P943
  de la 353; la última cuenta de filas medida en esta memoria es 1018 / 11 rojas de deuda, tras la 353).
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
  **Desvío aceptado (familia 8):** los rollbacks de 334-353 viven en `supabase/migrations/`
  (`3XX_rollback.sql`), no en `supabase/migrations/rollback/`.
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
  sin 42501) (350, **APLICADA**; P936; allowlist temporal de P930 con el SELECT de anon en 5 tablas) → **sigue: F2-d** quitar el UPDATE directo de visitas_agendadas (2 policies + el privilegio) → **F2-e** decisiones
  de producto (exp_superadmin_insert: super_admin crea notas a nombre de cualquier médico; claves bancarias de
  configuracion_sistema visibles para todo authenticated) → **F2-f** con front (campana_vistas con `ignoreDuplicates`
  + revocar UPDATE y sacarlo de la allowlist de P930; partir catalogo_lab_all) → **F2-g** opcional (partir ALL;
  `(select auth.uid())`) → **ÚLTIMO: EXECUTE** (con el número que le toque): `GRANT EXECUTE … TO authenticated,
  service_role` explícito en los helpers usados por policies ANTES de `REVOKE … FROM PUBLIC, anon` en las 21 (si no,
  se rompen para authenticated las 52 policies de mi_empresa_proveedor() y el resto); extender P800 a `pg_proc`;
  achicar WL_ANON_LEGACY y sacar las 5 entradas temporales de anon de la allowlist de P930 (350). Hallazgos a conservar: `transacciones` se lee desde el front (AdminEzPayPage y las
  ReportesEzPayPage) y siempre devuelve [] porque tiene 0 policies → familia 7; configuracion_pais: el `true` de
  authenticated anula el filtro `activo` para logueados; 123 policies con `auth.uid()` sin `(select …)` (performance).
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
  ninguna relación de public); falta extenderlo a funciones (último paso de la familia 2).
  Hallazgos del recon para no perderlos: **P800 NO consulta `pg_proc`**; 21 funciones de public con
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
  `useRecetas.ts:197` UPDATE de `recetas`. Y: `campana_vistas` no tiene policy de UPDATE, así que el upsert del
  front con conflicto (vista repetida) probablemente falla desde antes de la 346 (el front traga el error);
  revisar.
- (Familia 3/4) FK `examenes_orden_id_fkey` sigue `ON DELETE CASCADE`: tras la 338 sólo la alcanzan
  postgres/service_role (borrar una orden arrastra sus exámenes, completados incluidos).
- (Familia 4) `examenes.updated_at` no se actualiza al corregir ni al liberar.
- (Familia 7) El lab no tiene vista del historial de revisiones; "Ver archivo anterior" aparece en
  revisiones que no cambiaron el archivo.
- (Familia 8) P800 salta las foreign tables (relkind 'f': mira `'r','v','m','p'`) mientras la 343 y P925 las
  incluyen; sin efecto hoy (0 foreign tables en public). Alinear cuando se toque P800 en el paso de EXECUTE (último de la familia 2).
- (Familia 8, no urgente) `.gitattributes` ya tiene `* text=auto eol=lf` (476b925; 0 blobs renormalizados),
  pero ~640 archivos siguen en CRLF en disco (checkouts viejos con `core.autocrlf=true`). Para pasarlos a LF
  hay que refrescar el checkout (`git rm --cached -r . && git reset --hard`) en un momento sin cambios locales.
- (Familia 7) `AsistenteIA.tsx` no muestra el motivo de los 403/400 (usar `src/lib/errorAsistenteIA.ts`); el
  sidebar filtra por `'asistente'` y no por `'asistente_medico'` (`Sidebar.tsx:55-57`).
- (Familia 7, resumen IA) Los vitales del resumen se muestran sin fecha de toma; el título "Datos faltantes
  en la nota" (`ResumenUltimaVisita.tsx:45`) incluye campos de la ficha → renombrar a "Datos faltantes";
  admin_clinica ve el botón "Iniciar consulta" en `/pacientes/:id/detalle` (`PacienteDetallePage.tsx:401`);
  "Dr. Dr." duplicado en Historial de Consultas (el "Dr." se antepone en `PacienteDetallePage.tsx:593`).
- **(QA-MANUAL, cleanup pre-go-live)** `auditoria_ia` id **181** (2026-10-02 15:38:37 UTC, medico.qa →
  paciente 23): `DELETE FROM public.auditoria_ia WHERE id = 181;`
