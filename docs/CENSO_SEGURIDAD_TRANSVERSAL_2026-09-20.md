# Censo de seguridad transversal — 20 de septiembre de 2026

**Pregunta:** después de cerrar PA-FAILOPEN (migs 265-271) y la capa de privilegios de `anon` +
gates SECURITY DEFINER (migs 298-301), ¿cuál es la PRÓXIMA capa? ¿Qué queda expuesto hoy, por
dónde, y para quién?

**Por qué se hizo:** para elegir el siguiente frente con evidencia, no por intuición. Este censo
NO arregla nada: es inventario con severidad. Cada fila trae la medición cruda que la sostiene.

**Modo:** solo lectura. Contra prod enlazada (`fqnsmvkxsuujahhmpzuk`) con `SELECT` sobre catálogos
y una batería de lecturas por la API real (REST/Functions/Storage) como `anon` sin sesión. Cero
`INSERT`/`UPDATE`/`DELETE`, cero migraciones, cero commits, cero deploys. Detalle al final, en
"Qué ejecutó este censo".

**Leyenda de severidad:** crítico = PHI o control de acceso roto, explotable hoy · alto = escritura
o lectura cross-tenant sin autorización · medio = fuga acotada, integridad, abuso de recursos ·
bajo = higiene, superficie no gobernada, o solo alcanzable con un rol que ya lo permite.
**Explotable por:** `anon` = sin sesión, con la key pública que está en el bundle · `auth` = cualquier
cuenta autenticada sin autorización sobre el objeto · `no` = no alcanzable por la API.

---

## Resumen ejecutivo

| # | Hallazgo | Severidad | Explotable por |
|---|---|---|---|
| 1 | **4 vistas de `public` corren como `postgres` (`bypassrls`) y `anon` las lee por REST.** `v_pacientes_actividad` devolvió **26/26 pacientes** (nombre, teléfono, última cita, recetas) sin sesión. `v_citas_hoy` expone las citas del día con nombre y teléfono del paciente. | **crítico** | `anon` |
| 2 | **`crear_clinica_con_dueno(p_doctor_id, …)`** es SECURITY DEFINER, la ejecuta `authenticated` y **no tiene gate**: crea clínicas y membresías a nombre de CUALQUIER médico. | **alto** | `auth` |
| 3 | `configuracion_sistema` tiene `USING (true)` para `public` y `anon` tiene SELECT: 21 claves legibles sin sesión, entre ellas `banco`, `cuenta_bancaria`, `titular_cuenta`, `tipo_cuenta`, `email_pagos`. | medio | `anon` |
| 4 | `notificaciones` broadcast (`usuario_id IS NULL`, 3 filas): cualquier `authenticated` puede hacer `UPDATE` sin `WITH CHECK` — puede reescribir `titulo`/`mensaje`/`accion_url` de lo que ven todos. | medio | `auth` |
| 5 | Buckets `campanas` y `productos`: cualquier `authenticated` sube y borra CUALQUIER objeto (la policy sólo mira `bucket_id` + `auth.role()`), y el bucket es público. | medio | `auth` |
| 6 | `verify_jwt=true` en Edge Functions **se satisface con la key pública** (medido). Las que confían solo en eso y usan `service_role` sin `getUser` quedan abiertas: `geocodificar` (gasta `GOOGLE_MAPS_API_KEY`) y `consultar-biblioteca` son proxies abiertos; `validar-*`/`registrar-*-invitacion` dependen únicamente del token (uuid v4, un solo uso, 7 días). | medio | `anon` |
| 7 | `listar_medicos_por_pais`, `buscar_medicos`, `obtener_medicos_por_ids`, `contar_medicos_por_*`: sin gate ni aislamiento por país (`p_pais_id NULL` = todos) y sin `search_path`. Cualquier `authenticated` lista a todos los médicos de todos los países. | medio | `auth` |
| 8 | Edge function huérfana **`super-function`** (slug) deployada, ACTIVE, `verify_jwt=true`, no existe en el repo: es una copia vieja de `generar-pdf-receta` con gate propio (`medico_id = user.id`). No vulnerable por sí misma; superficie no gobernada. | bajo | — |
| 9 | 6 SECURITY DEFINER sin `search_path` y 84 con `search_path=public` (no `''`). No explotable hoy: ni `anon` ni `authenticated` tienen CREATE en `public`/`extensions`. | bajo | `no` |

Lo que **no** apareció, y también es resultado: **0 tablas sin RLS en `public`** (120/120), **0
privilegios de escritura de `anon` sobre ninguna relación de `public`** (la 298 se sostiene), las
SECDEF con `EXECUTE` para `anon` son **exactamente las 11 esperadas** (la 301 se sostiene), los
buckets privados devuelven **0 objetos** a `anon` por la API, y los secretos compartidos de las
edges server-to-server son fail-closed (`!secret || header !== secret`).

---

## Método

- **Catálogo:** 18 consultas `SELECT` (una por archivo, porque el CLI devuelve sólo el último result
  set) sobre `pg_class`, `pg_policy`, `pg_proc`, `pg_default_acl`, `pg_attribute.attacl`,
  `storage.buckets`, `pg_roles`, `pg_extension`, `information_schema.columns`. 344 funciones,
  306 policies, 135 relaciones, 43 policies de storage, 14 buckets.
- **Ejercicio como rol:** `set_config('role', …)` + `request.jwt.claims` — el ACL se evalúa por el
  rol de sesión, no por el JWT (lección de la mig 300). Dos actores: `anon` y un `authenticated`
  real sin rol (`0dd0c68c-…`, paciente).
- **API real:** con la key pública de `.env.local` (formato nuevo, 46 chars; nunca impresa), `GET`
  a `/rest/v1/<vista>` con `Prefer: count=exact` + `Range: 0-0` (sólo `Content-Range`, sin datos),
  `Accept-Profile` para los schemas, `POST` a Functions con body vacío (para saber si el gateway
  deja pasar, no para ejecutar nada), `POST /storage/v1/object/list/<bucket>` (sólo cantidad).
- **Código:** los 36 `index.ts` de `supabase/functions/` con un barrido estático
  (`service_role`, `getUser`, chequeo de rol, secreto compartido, CORS, stub 410) + lectura manual
  de los 12 que el barrido marcó. Estado **deployado** por `supabase functions list` (37 entradas).
  `config.toml` sólo se usó como contraste: lo que manda es lo deployado.
- **F4 (gates):** clasificador sintáctico sobre las 288 SECDEF no-trigger ejecutables por
  `anon`/`authenticated`; de las 63 sin patrón de identidad se extrajeron los helpers que llaman
  (52 usan `private.puede_admin_pais` / `es_staff_calendario_clinica` / `puede_gestionar_prospecto`
  / `admin_puede_gestionar_empresa` / `tiene_permiso` / `gate_accion_phi`) y se **leyó el cuerpo**
  de las 11 restantes. Los helpers `puede_admin_pais` y `puede_gestionar_prospecto` tienen
  `COALESCE(…, false)`; `es_staff_calendario_clinica` no (ver F4).

---

## F1 — Tablas sin RLS / sin FORCE

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `public.*` (120 tablas) | **Ninguna sin RLS.** 120/120 `relrowsecurity=true`. | `f1_tablas_rls`: RLS off = 0 | — | — |
| `public.*` (120 tablas) | 0/120 con `FORCE ROW LEVEL SECURITY`. Sólo importa para el dueño (`postgres`), que nunca entra por la API. | `relforcerowsecurity=false` ×120; owner `postgres` ×120 | bajo | `no` |
| `private.busqueda_paciente_log`, `private.delivery_autocreate_fallos`, `private.delivery_flags` | RLS **off**. Sin grants a `anon`/`authenticated`; `private` no está expuesto (PGRST106) y `anon` no tiene USAGE. | `f1`: rls=false, anon_sel=false, auth_sel=false; REST `Accept-Profile: private` → 406 | bajo | `no` |
| `storage.buckets`, `storage.buckets_analytics` | `anon` y `authenticated` con S/I/U/D **completos**, RLS on, **0 policies** → deny. Default de Supabase. | `f5_storage_grants` | bajo | `no` |

## F2 — RLS on pero sin policies, cobertura, policies `true`

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `configuracion_sistema` | Policy `Cualquiera lee configuracion` = `USING (true)` para **`public`**, y `anon` tiene SELECT. 21 filas legibles sin sesión: `app_logo_url, app_nombre, banco, color_*, cuenta_bancaria, email_pagos, integ_email_smtp, integ_google_calendar, integ_whatsapp_api, notif_*, sistema_*, tipo_cuenta, titular_cuenta`. Los valores no se miraron; los largos sí: `cuenta_bancaria` len=12, `banco` len=16, `integ_*` len=0. | REST anon: `HTTP 206 Content-Range: 0-0/21`. SQL como anon: 21 filas. | **medio** | `anon` |
| `configuracion_pais` | `Publico lee paises activos` = `USING (activo = true)` para `public`; 21 países con `moneda`, `porcentaje_comision_default`, `techo_cortesia_visitas`. | SQL como anon: 21 filas | bajo | `anon` |
| `notificaciones` | `notificaciones_update_propias`: `USING (usuario_id = auth.uid() OR usuario_id IS NULL)`, **sin `WITH CHECK`** (hereda el USING), `authenticated` tiene UPDATE. Las 3 filas broadcast son editables por cualquier cuenta: `titulo`, `mensaje`, `accion_url`, `metadata`, incluso `usuario_id`. | `f2_policies` + `f1` (auth_update=true) + `count(*) WHERE usuario_id IS NULL` = 3 | **medio** | `auth` |
| `notificaciones` | Misma policy en SELECT: los broadcast los ve cualquiera (eso es intencional). | idem | — | — |
| `cache_biblioteca`, `confirmaciones_receta`, `medico_correlativos`, `planes_features`, `planes_limites`, `resumen_comisiones`, `transacciones` (66 filas) | RLS on, **0 policies**, `authenticated` con SIUD → deny total por la API. No es vulnerabilidad; es inventario: sólo `service_role`/SECDEF las alcanzan. | `f1` n_policies=0 | bajo | `no` |
| `empresa_capacidades`, `medicamentos_clasificacion_log`, `solicitudes_capacidad_pais` | RLS on, 0 policies, **sin grants** a los roles de API. | idem | — | `no` |
| 25 policies `USING (true)` para `authenticated` (catálogos: `especialidades`, `medicamentos`, `roles*`, `planes_*`, `tiers_*`, `capacidades_catalogo`, `consentimiento_permisos`, `acciones_techo`, `permisos_empresa_rol`, `configuracion_pais`) | Lectura abierta a cualquier cuenta. Son catálogos; `consentimiento_permisos` es `codigo/version/etiqueta/texto_legal`, no datos por paciente. | `f2` | bajo | — |
| 6 policies `USING (true) WITH CHECK (true)` para `service_role` (`invitaciones_*`, `medico_clinicas`, `push_subscriptions`, `recordatorios`) | Inertes: `service_role` tiene `bypassrls`. | `f9_authenticator`: service_role bypassrls=true | — | `no` |
| 88 combinaciones (tabla, rol, comando) con grant y sin policy | Deny por defecto. Inventario, no hallazgo. | cálculo sobre `f1`×`f2` | — | `no` |

## F3 — SECURITY DEFINER sin `search_path`

323 SECDEF en `public`+`private`: 233 con `search_path=""`, 84 con `search_path=public`, **6 sin nada**.

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `buscar_medicos(text,uuid,int)`, `contar_medicos_por_ids(uuid[])`, `contar_medicos_por_pais(uuid)`, `listar_medicos_por_pais(uuid)`, `obtener_medicos_por_ids(uuid[])`, `auto_configurar_planes_publicidad()` | `proconfig IS NULL`: resuelven nombres con el `search_path` del llamante. Hijacking exige CREATE en un schema del path; `anon`/`authenticated` no lo tienen en `public` ni `extensions`. Además coinciden con F4 (sin gate). | `f3_funciones`: tiene_search_path=false; `f7_anon_schemas`: CREATE=false en todos | bajo | `no` (hoy) |
| 84 SECDEF con `search_path=public` | No es `''`. Misma condición: sin CREATE en `public` no hay objeto que interponer. Higiene, y la linter de Supabase lo marca. | `f3`: Counter(search_path=public)=84 | bajo | `no` |
| SECDEF con `search_path` a otro schema | **Ninguna.** | `f3`: 0 | — | — |

## F4 — SECDEF fail-open por razones distintas al trivaluado

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `public.crear_clinica_con_dueno(p_doctor_id uuid, p_nombre, p_pais_id, p_direccion, p_telefono, p_email)` | **Sin gate de ninguna clase.** `INSERT INTO clinicas (doctor_id = p_doctor_id, …)` + `INSERT INTO medico_clinicas (medico_id = p_doctor_id, es_principal = …)`. Cualquier cuenta crea clínicas a nombre de cualquier médico y, si ese médico no tenía principal, se la fija. El front pasa `user.id` (`useClinicas.ts:78`), pero la RPC no lo exige. `search_path=public`. | cuerpo completo leído; `auth_exec=true`, `anon_exec=false`; sin `auth.uid()`, sin `RAISE`, sin helper | **alto** | `auth` |
| `listar_medicos_por_pais(uuid)`, `buscar_medicos(text,uuid,int)`, `obtener_medicos_por_ids(uuid[])`, `contar_medicos_por_pais(uuid)`, `contar_medicos_por_ids(uuid[])` | Sin gate ni pertenencia; `p_pais_id IS NULL OR …` ⇒ NULL lista **todos los países**. Devuelven `id, nombre_completo, especialidad, foto_url, activo, pais_id` de `medicos` **más** `perfiles` con `rol='medico'` de cualquier país (el "aislamiento por país" que ya figura como pendiente). Callers: `CitasPage`, `useClinicaCitas`, `useAdmisionCitas`, `useWebAppCitas`. | cuerpos leídos; `WHERE (p_pais_id IS NULL OR m.pais_id = p_pais_id OR m.pais_id IS NULL)` | **medio** | `auth` |
| `obtener_clinicas_medico(p_medico_id uuid)` | Sin gate: clínicas (id, nombre, es_principal) de cualquier médico para cualquier cuenta. Caller: `AgendarCitaModal`. | cuerpo leído | bajo | `auth` |
| `prioridad_activa(p_medico_id uuid)` | Sin gate: revela `lab_enrolador_id`, conteo de visitas cumplidas y límite de cualquier médico (relación comercial médico↔laboratorio). | cuerpo leído | bajo | `auth` |
| `proximo_turno_disponible(p_medico_id uuid)` | Sin gate: primer slot libre de cualquier médico. Es la funcionalidad de agendar; se lista por completitud. | cuerpo leído | bajo | `auth` |
| `emision_flag(text)` | Sin gate: lee `private.emision_flags.habilitado` por clave. Sólo booleanos. | cuerpo leído | bajo | `auth` |
| `private.es_staff_calendario_clinica(p_clinica uuid)` y sus 5 callers (`crear_paciente_clinica`, `listar_citas_clinica`, `listar_visitas_clinica`, `listar_medicos_clinica`, `buscar_pacientes_clinica`) | El helper es `tiene_rol(super) OR (tiene_rol(staff) AND p_clinica IN (…))` **sin COALESCE**. Con `p_clinica = NULL` y un usuario que SÍ tiene rol de staff: `false OR (true AND NULL)` = NULL → `IF NOT NULL` no entra → **no lanza**. En `crear_paciente_clinica` eso inserta un paciente con `clinica_primaria_id` y `pais_id` NULL (huérfano); en las de lectura, `WHERE clinica_id = NULL` da 0 filas. El censo fail-open anterior no lo vio porque sus dos actores no tenían rol de staff. | cuerpo del helper + de `crear_paciente_clinica` | bajo | `auth` (staff) |
| `private.resolver_medicamento_id(text)` | `EXECUTE` para `anon` explícito, SECDEF. `private` no está expuesto y `anon` no tiene USAGE. | `f7_anon_funciones_todas`; REST → PGRST106 | bajo | `no` |
| 225 SECDEF clasificadas "gate + pertenencia" | **No se releyeron una por una.** El clasificador confirma que llaman a un helper de identidad; la corrección de cada gate contra el trivaluado la cubrió `tmp/censo_failopen.md` (25 candidatas, 3 confirmadas y cerradas en la 300). La pertenencia fina (que el id recibido sea del tenant correcto) queda fuera de este censo. | — | — | (no medido) |

## F5 — Storage

14 buckets, 43 policies sobre `storage.objects`. `anon` lista **0** objetos en todos los privados
(medido por la API con `POST /object/list`).

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| bucket `campanas` (público, 14 objetos) | `Usuarios autenticados pueden subir campanas` = `bucket_id='campanas' AND auth.role()='authenticated'`; ídem `…eliminar`. **Sin confinamiento por empresa ni por path.** Cualquier cuenta borra las creatividades de cualquier anunciante o sube imágenes que se sirven públicas desde el dominio. MIME limitado a imágenes, 5 MB. | `f5_storage_policies` | **medio** | `auth` |
| bucket `productos` (público, 0 objetos) | Mismo patrón exacto (`Autenticados suben productos` / `…eliminan productos`). | idem | medio | `auth` |
| bucket `fotos-medicos` (público, 1 objeto) | `fotos_medicos_public_select` = `bucket_id='fotos-medicos'` para `public`: anon lista y lee todas las fotos de médicos (1 hoy). Documentado como molde a no repetir en CLAUDE.md. Escritura confinada a `auth.uid()`. | policy + `POST /object/list/fotos-medicos` como anon → 1 | bajo | `anon` |
| buckets `personalizacion-logos`, `premios` (públicos) | Lectura pública por diseño; escritura confinada (`clinica/<id>` en `clinicas_del_usuario`; `premios` sólo `super_admin`). | policies | bajo | — |
| `pacientes-fotos`, `pacientes-documentos`, `resultados-examenes`, `comprobantes`, `entregas-evidencia`, `evidencias-visitas`, `material-comercial`, `visitas-comerciales`, `tarjetas-asesor` (privados) | Confinados por tenant en USING/CHECK (`clinicas_del_usuario()`, `mi_empresa_proveedor()`, `puede_admin_pais`, `puede_ver_visita`, `auth.uid()`). Varios sin policy DELETE = nadie borra por la API. | policies; anon lista 0 en los 4 probados | — | `no` |
| `storage.objects` | `anon` con S/I/U/D completos a nivel grant (default Supabase); lo que gobierna es RLS. Las policies de INSERT para `public` exigen `auth.role()='authenticated'` → `anon` no sube. | `f5_storage_grants` + policies | bajo | `no` |

## F6 — Edge Functions

37 deployadas / 36 carpetas en el repo. **Hallazgo transversal medido:** `verify_jwt=true` en el
gateway **acepta la key pública** como credencial — `geocodificar` respondió `200` sin
`Authorization`, y `validar-invitacion`/`registrar-medico-invitacion`/`consultar-biblioteca`
respondieron `400` (su propia validación de body) con sólo la key pública. O sea: `verify_jwt` NO
es un gate de sesión. Sólo `getUser`/`gate_accion_phi`/secreto compartido lo son.

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `geocodificar` (vjwt=true) | Sin `getUser`, sin secreto. Proxy abierto a Google Geocoding con `GOOGLE_MAPS_API_KEY` (y fallback a otro geocoder). Cualquiera con la key pública gasta la cuota/factura. | `POST {}` sin Authorization → `200 {"error":"Dirección requerida"}` (no llegó a Google) | **medio** | `anon` |
| `consultar-biblioteca` (vjwt=true) | Sin `getUser`. Proxy abierto a PubMed/Wikipedia. Sin costo directo; abuso de recursos. | `POST {}` → 400 desde la función | bajo | `anon` |
| `validar-invitacion`, `validar-invitacion-clinica`, `validar-invitacion-medico` (vjwt=true) | `service_role`, sin `getUser`. Devuelven la fila de la invitación (email, nombre, rol, clínica, país) a quien traiga el token. Token = `gen_random_uuid()` (122 bits), `estado='pendiente'`, `expires_at` 7 días. Enumeración impracticable; la fuga es "quien tiene el link ve a quién invitaron". | código + `information_schema.columns` (defaults) + token falso → 400 | bajo | `anon` (con token) |
| `registrar-clinica-invitacion`, `registrar-medico-invitacion` (vjwt=true) | `service_role`, sin `getUser`. Orden correcto: valida `token+pendiente+expires_at` **antes** de `auth.admin.createUser`. Pero los pasos no son atómicos: si la RPC `registrar_*_desde_invitacion` falla después, quedan un usuario de Auth y un `perfiles` con `rol='admin_clinica'`/`'medico'`, `activo=true`, sin clínica/médico. La RPC re-valida con `FOR UPDATE`, email igual y marca `usada`. | código líneas 32-95 + cuerpo de las RPC | bajo | `anon` (con token) |
| slug **`super-function`** (name `generar-pdf-receta`, id `8070daa4-…`, v17, ACTIVE, vjwt=true, creado may-2026) | No existe en el repo. Descargado a scratch: 269 líneas, `getUser(token)` + `.eq('medico_id', user.id)` + `service_role`, jsPDF. Es la versión anterior de `generar-pdf-receta` (la actual es `82838208-…`, v19). Gate propio, no vulnerable; **endpoint activo que nadie mantiene**. | `functions list` (2 entradas con el mismo name) + `functions download super-function` a scratch + diff (474 líneas) | bajo | — |
| `enviar-notificacion`, `enviar-push`, `registrar-dispensacion`, `verificar-receta-qr` (vjwt=**false**) | Stubs `410 Gone` (CIERRE FINAL push-tx / Inc.4). No tocan BD ni `service_role`. | barrido: `stub410=true`, sin `SERVICE_ROLE` | — | `no` |
| `enviar-push-notificacion`, `notificar-email`, `procesar-recordatorios` (vjwt=false) | Secreto compartido, **fail-closed**: `if (!secret \|\| header !== secret) return 401`. | código líneas 21 / 95 / 17 | — | `no` |
| `notificar-admin` (vjwt=false) | Gate dual: `x-internal-secret` (fail-closed, `!!internalSecret && …`) O JWT + `super_admin`. | código línea 68 | — | `no` |
| `confirmar-recepcion-receta`, `tarjeta-asesor` (vjwt=false) | Por diseño sin sesión; token de 256 bits (`gen_random_bytes(32)`), expiración, RPC sólo `service_role`. | código + `f3` ACL `service_role=X` | — | `no` |
| `dictado-voz`, `asistente-ia` | Cliente **anon + JWT del caller** y `gate_accion_phi` en la RPC (identidad por `auth.uid()`); `asistente-ia` además `getUser` para la auditoría. `service_role` sólo para escribir la auditoría. | código | — | `no` |
| 21 restantes con `getUser` + rol/ownership | `crear-empleado`, `listar-empleados`, `reportes-*`, `exportar-csv`, `actualizar-configuracion`, `crear-invitacion-*`, `crear-staff-clinica`, `invitar-*`, `enviar-push-campana`, `programar-recordatorio`, `enviar-recordatorio`, `registrar-auditoria`, `generar-pdf-receta`. No se releyó cada gate en este censo (ya censadas 12/12 el 3-jul). | barrido | — | — |
| 34/36 con `Access-Control-Allow-Origin: *` | Con auth por bearer, CORS `*` no habilita nada por sí solo (no hay cookies). Informativo. `tarjeta-asesor` sin CORS (HTML). | barrido | bajo | — |
| Secrets deployados | 18 nombres; `DEV_ORIGIN` (el que "borrar antes de go-live") **no está** ✓. | `secrets list` (sólo nombres) | — | — |

## F7 — Grants de `anon`, barrido completo

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| SECDEF en `public` con `EXECUTE` para `anon` | **Exactamente 11**: `registrar_proveedor` + las 10 de policies. Nada nuevo desde la 301. | `f7_anon_funciones_todas`: public secdef=True → 11 | — | — |
| 11 funciones **no**-SECDEF de `public` con `anon` (`actualizar_stock_dispensacion`, `calcular_imc_signos_vitales`, `calcular_limite_cancelacion`, `limpiar_cache_biblioteca_expirada`, `perfiles_guard_rol_update`, `set_fecha_limite_cancelacion`, `trg_*`, `trigger_set_updated_at`, `update_*`) | Triggers (`0A000` si se invocan como RPC) salvo `calcular_limite_cancelacion(date)` y `limpiar_cache_biblioteca_expirada()`, que son puras/inofensivas. Vía `PUBLIC=X`. | `f7` via_public=true | bajo | `no` |
| 17 funciones de `private` con `anon` (10 SECDEF: guards de triggers, `es_staff_calendario_clinica`, `puede_aprobar_visitas`, `resolver_medicamento_id`) | `private` no expuesto y sin USAGE para `anon`. | `f7_anon_schemas`: private anon USAGE=false | bajo | `no` |
| 72 tablas + 8 vistas de `public` con SELECT para `anon` | **0 privilegios de escritura** en ninguna relación de `public` (la 298 se sostiene). Las 72 tablas están gobernadas por RLS (medido: `citas`, `pacientes`, `perfiles`, `recetas`, `expediente_notas` → 0 filas a anon). Las 8 vistas: ver F8. | `f7_anon_relaciones`: en public sólo `['SELECT']`; REST `citas`/`pacientes` → `*/0` | — | — |
| 32 secuencias de `public` con USAGE para `anon` | Sin INSERT en ninguna tabla no hay `nextval` alcanzable por REST. La fábrica ya está cerrada (301). | `f7_anon_secuencias` | bajo | `no` |
| `net._http_response`, `net.http_request_queue` | `anon` con **los 7 privilegios**, RLS off, y USAGE en `net`; `anon` ejecuta 12 funciones `net.*` incluidas `http_get`/`http_post`. `net` no está expuesto por PostgREST. Es el default de pg_net; sólo alcanzable desde SQL (p. ej. una inyección dentro de una SECDEF). | `f7` + REST `Accept-Profile: net` → 406 | bajo | `no` (hoy) |
| `cron.job` (SELECT), `cron.job_run_details` (SELECT, DELETE) | Grants presentes pero `anon` sin USAGE en `cron`. | `f7_anon_schemas` | bajo | `no` |
| `extensions.pg_stat_statements` (SELECT para `anon`) | Expondría texto de queries; schema no expuesto y sin CREATE. | `f7` + REST 406 | bajo | `no` |
| `realtime.messages` (S/I/U para `anon`) | RLS on, 0 policies → deny. Default. | `f7` | — | `no` |
| `pg_default_acl` | `public`: cerrada para `f`/`r`/`S` (sin `anon`, sin `PUBLIC`) ✓. `storage`: sigue dando todo a `anon` (lo administra Supabase). `supabase_admin`: intocable, inerte (nada lo crea). | `f7_default_acl` | — | — |
| ACL por columna | 36 entradas, todas deliberadas (mig 277: coordenadas no legibles; `notificaciones_pacientes.leida` sólo UPDATE). | `f7_columnas_anon` | — | — |

## F8 — Vistas

8 vistas en `public`, todas con SELECT para `anon` y `authenticated`, todas `owner=postgres`
(**`rolbypassrls=true`**). 4 tienen `security_invoker=on`; **4 no**, y esas corren con los
privilegios del dueño: RLS de las tablas base **no aplica**.

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| `v_pacientes_actividad` | `pacientes ⟕ citas ⟕ recetas`, sin filtro. Columnas: `paciente_id, paciente_nombre, telefono, total_citas, ultima_cita, total_recetas, citas_canceladas`. **Anon sin sesión recibe la tabla completa.** La base `pacientes` da 0 al mismo actor. Sin caller en `src/`. | REST anon: `HTTP 206 Content-Range: 0-0/26`; SQL anon: 26 = total `pacientes` | **crítico** | `anon` |
| `v_citas_hoy` | `citas ⟕ pacientes ⟕ perfiles ⟕ recordatorios` `WHERE fecha = CURRENT_DATE`: `paciente_nombre, paciente_telefono, medico_nombre, motivo, hora`. Hoy 0 filas **porque no hay citas hoy**, no porque esté protegida: cualquier día con agenda expone las citas del día. Sin caller en `src/`. | REST anon: `200 */0`; definición sin `auth.uid()` | **crítico** (latente) | `anon` |
| `v_estadisticas_medico` | `perfiles WHERE rol='medico' ⟕ citas ⟕ recetas`: nombre + conteos por médico. 4 filas = los 4 médicos. Sin caller. | REST anon: `206 0-0/4`; `perfiles rol=medico` = 4 | medio | `anon` |
| `v_resumen_mensual` | Agregados por mes (citas, pacientes nuevos, recetas). Sin PHI individual; sí métricas del negocio. Sin caller. | REST anon: `206 0-0/2` | bajo | `anon` |
| `v_consultas_paciente` | `security_invoker=on` (mig 234, C2). Anon → 0. | REST `200 */0` | — | `no` |
| `v_medicamentos_bajo_stock`, `v_metricas_campana_pais`, `v_metricas_campana_resumen` | `security_invoker=on`. Anon → 0 / 42501 (`farmacias` revocada en 298). | SQL | — | `no` |

## F9 — API, schemas, extensiones, roles

| objeto | problema medido | evidencia | severidad | explotable por |
|---|---|---|---|---|
| Schemas expuestos por PostgREST | **`public`, `graphql_public`** — nada más. `private`, `storage`, `net`, `extensions` → `PGRST106`. | REST `Accept-Profile` | — | — |
| `graphql_public.graphql(text,text,jsonb,jsonb)` | `EXECUTE` para `anon`; es un stub plpgsql: **`pg_graphql` no está instalada**. | `pg_extension` | bajo | `no` |
| Extensiones | `pg_net 0.20.0` con namespace `public` (default Supabase; sus objetos viven en `net`). `pgcrypto`, `uuid-ossp`, `pg_stat_statements` en `extensions` ✓. `pg_cron` en `pg_catalog`. `supabase_vault`. | `f9_extensiones` | bajo | — |
| Roles | `anon` `statement_timeout=3s`, `authenticated` `8s` ✓. `postgres` `bypassrls=true` (estándar, y es la razón de F8). `service_role` `bypassrls=true`. | `f9_authenticator` | — | — |
| `private` | `authenticated` tiene USAGE (no expuesto por REST; alcanzable sólo desde SQL). | `f7_anon_schemas` | bajo | `no` |
| Superficie RPC visible a `anon` | **No medida**: la raíz OpenAPI `/rest/v1/` devolvió `401` con la key pública nueva. | REST | — | (no medido) |

---

## Conteos

- Tablas `public`: 120 · con RLS: **120** · sin policies: 10 · policies: 306 (public) + 43 (storage).
- Funciones `public`+`private`: 344 · SECDEF: 323 · sin `search_path`: **6** · con `search_path=public`: 84.
- SECDEF ejecutables por `anon` en `public`: **11** (las esperadas). Por `authenticated`: 288 no-trigger.
- Relaciones con algún privilegio de `anon`: 95 (80 en `public`, todas sólo SELECT; 7 `storage`; 2 `net`; 2 `cron`; 2 `extensions`; 2 `realtime`).
- Vistas `public`: 8 · sin `security_invoker`: **4** · de esas, con filas para anon hoy: **3** (26 + 4 + 2).
- Buckets: 14 · públicos: 5 · con escritura sin confinamiento: **2**.
- Edge functions deployadas: 37 · `verify_jwt=false`: 10 (4 stubs 410, 3 secreto, 1 dual, 2 token) · `service_role` sin `getUser` ni secreto: **5** (validar ×3, registrar ×2) · sin BD y sin gate: **2** (geocodificar, consultar-biblioteca) · huérfanas: **1**.

## Hallazgos destacados (por qué el orden)

1. **F8 — las 4 vistas** son la única fuga de PHI a `anon` sin sesión que este censo midió con la
   API real. Es la misma clase que C2 (mig 234) y las 4 quedaron afuera de aquel cierre. Ninguna
   tiene caller en `src/`: son superficie muerta que sólo sirve al atacante.
2. **F4 — `crear_clinica_con_dueno`**: escritura cross-tenant sin gate en una SECDEF. No se ejercitó
   (habría escrito); la evidencia es el cuerpo completo y el ACL.
3. **F2/F5 — integridad por `authenticated`**: broadcast de `notificaciones` editable por cualquiera
   (vector de phishing interno vía `accion_url`) y buckets `campanas`/`productos` sin confinamiento.
4. **F6 — `verify_jwt` no es sesión.** Este es el que reordena la lectura de las edges: cualquier
   edge cuya única defensa sea `verify_jwt=true` está abierta con la key pública. Hoy pega en 2
   proxies externos (uno con costo) y en 5 que dependen del token de invitación.
5. **F2 — `configuracion_sistema`** con datos bancarios legibles sin sesión.
6. **F4 — listado de médicos sin país**: no es PHI, pero contradice el aislamiento por país que el
   producto promete, y devuelve `perfiles` con `rol='medico'` de cualquier país.

## Salvedades

1. **F4 es heurístico más lectura dirigida.** Se leyeron 11 cuerpos (los sin helper) y 3 helpers.
   Las 225 con helper de identidad NO se releyeron: el trivaluado ya lo cubrió el censo anterior;
   la **pertenencia fina** (que el id recibido sea del tenant del caller) no está auditada.
2. **Nada se ejercitó escribiendo.** `crear_clinica_con_dueno` y `notificaciones` broadcast se
   clasifican por cuerpo/policy, no por explotación.
3. **F6:** de las 21 edges con `getUser` + rol no se releyó cada gate (censo del 3-jul). El barrido
   estático puede equivocarse en un regex; por eso todo lo marcado se leyó a mano.
4. **La superficie RPC visible a anon** (OpenAPI) no se pudo contar: `401` con la key nueva.
5. **Auth (GoTrue)**: confirmación de email, rate limits, providers, no entran en este censo.
6. **Realtime**: sólo se miró el catálogo (`realtime.messages` deny). No se probó suscribirse.
7. `v_citas_hoy` se clasifica **crítico latente** por definición, no por filas vistas hoy.

## Qué ejecutó este censo (para auditar el "solo lectura")

- **SQL (18 + 6 archivos, todos `SELECT` / `DO` de sólo lectura):** `f1_tablas_rls`, `f2_policies`,
  `f3_funciones`, `f5_buckets`, `f5_storage_policies`, `f5_storage_objetos`, `f5_storage_grants`,
  `f7_anon_relaciones`, `f7_anon_secuencias`, `f7_anon_funciones_todas`, `f7_anon_schemas`,
  `f7_default_acl`, `f7_columnas_anon`, `f8_vistas`, `f9_authenticator`, `f9_extensiones`,
  `f9_pgrst_settings`, `f9_objetos_otros_schemas`, `x_cols`, `x_tok`, `x_vistas_anon` (cuenta filas
  como anon/authenticated; el `DO` no escribe), `x_misc`, `verif_muestra`, `impacto10`.
- **CLI:** `functions list`, `secrets list` (sólo nombres), `functions download super-function`
  con `--workdir` en scratch (**no tocó `supabase/functions/` del repo**; `git status` limpio).
- **HTTP contra prod:** `GET /rest/v1/<vista|tabla>` con `Range: 0-0` (8 objetos), `GET /rest/v1/`
  con `Accept-Profile` (8 schemas), `GET /rest/v1/emision_flags` con `Accept-Profile` (5),
  `POST /functions/v1/{geocodificar, consultar-biblioteca, validar-invitacion,
  validar-invitacion-medico, registrar-medico-invitacion}` con `{}` (todas cortaron en su
  validación de body antes de tocar BD o APIs externas; `geocodificar` devolvió "Dirección
  requerida" sin llamar a Google), `POST /functions/v1/validar-invitacion` con un uuid nulo,
  `POST /storage/v1/object/list/<bucket>` (6 buckets). La key pública se leyó de `.env.local` y
  no se imprimió en ningún momento.
- **Repo:** lectura de `supabase/functions/**/*.ts`, `supabase/config.toml`, `src/hooks/useClinicas.ts`,
  `supabase/migrations/*.sql` (grep). Sin cambios: este documento es el único archivo nuevo, y
  queda **sin trackear**.
