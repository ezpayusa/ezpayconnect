# Recon de cierre — Panel de FARMACIA
**Fecha:** 2026-06-23 · **Modo:** SOLO LECTURA (cero cambios/migraciones/commits) · **Salida:** este documento.

> Recon para que el revisor estructure la ruta de trabajo del panel de Farmacia en **tres carriles**. Todo verificado contra el código + la **BD viva** (consultas de solo lectura). No se propone ni construye nada.

## ⚠️ Correcciones a recon previos (verificadas en BD viva)
1. **C.2 (confinamiento por sucursal) NO está "pendiente de diseño" — está APLICADA (mig 114).** El término `private.sucursal_visible(farmacia_id)` ya está **ANDeado** en las policies SELECT (`farm_med_propia_empresa`) y ALL (`farm_med_tenant_all`, USING+WITH CHECK) de `farmacia_medicamentos`. Es **grandfather-inerte** (todos los `sucursal_id = NULL` → rama permisiva), no "sin cablear". Lo que falta es el **mecanismo de asignación** de sucursal a usuarios, no el código de policy.
2. **`farmacias` ES la tabla de sucursales** (no hay tabla `sucursales`). Confirmado en mig 091:5.

---

# CARRIL A — Sucursales (C.2)

## #1 — Tabla(s) de sucursales
- **No existe tabla `sucursales`.** La tabla de sucursales **es `farmacias`** (mig 091:5 lo declara explícito).
- Columnas de `farmacias`: `id, nombre, direccion, telefono, email, encargado, horario, activo, created_at, tipo, pais_id, empresa_id`.
  - **Tiene `direccion`** (texto libre). **NO tiene lat/lng** (ninguna columna de coordenadas).
  - **FK a empresa:** `empresa_id` → `empresas_proveedoras` (la cadena). NULL = catálogo global (super_admin).
- **Datos en vivo:** 7 filas. **6 con `empresa_id = NULL`** (catálogo global) + **1 con empresa real** (`548741e4-…`). Solo **3 de 7** tienen `direccion` cargada.

## #2 — ¿UI para crear/editar sucursales en el panel admin de farmacia?
**NO existe ninguna UI hoy.** No hay página ni componente que invoque `crear_sucursal`. El RPC **existe** en backend:
- `crear_sucursal(p_nombre text, p_direccion text, p_telefono text, p_encargado text, p_horario text)` — DEFINER, gate `tiene_permiso('sucursales_gestionar')`, empresa forzada server-side (mig 091).
- **Sin parámetros de lat/lng** (el RPC no captura coordenadas).
- No hay RPC de edición/listado de sucursales propio (las farmacias se listan vía otros queries).

## #3 — `cuentas_proveedor.sucursal_id` y el confinamiento (mig 091 + 114)
**Quién usa el eje sucursal hoy (BD viva):**
- **Helpers:** `private.mi_sucursal()` (mig 091, devuelve `cuentas_proveedor.sucursal_id` del caller, NULL-safe), `private.sucursal_visible(p_farmacia_id)` (mig 114).
- **Policies que ANDean el término sucursal:** `farmacia_medicamentos.farm_med_propia_empresa` (SELECT) y `farmacia_medicamentos.farm_med_tenant_all` (ALL: USING+WITH CHECK). Ambas: `… empresa fail-closed … AND COALESCE(private.sucursal_visible(farmacia_id), false)` (mig 114:37-61).
- **RPCs de reportes:** `stats_finanzas_sucursal(p_desde,p_hasta,p_sucursal_id)` y `stats_recetas_sucursal(...)` aceptan `p_sucursal_id` (hoy el front pasa `null`).
- **`sucursal_visible` =** EXENTO (`mi_rol_proveedor() ∈ {admin, gerente_farmacia, finanzas, pagador}`) **OR** grandfather (`mi_sucursal() IS NULL`) **OR** `p_farmacia_id = mi_sucursal()` (mig 114:26-32).

**Estado real:** **0 de 12 cuentas tienen `sucursal_id` no-NULL** → todos caen en la rama grandfather → comportamiento empresa-wide actual, sin regresión.

**Qué se necesita para activar C.2 sin romper lo de empresa:** (el código de policy YA está). Falta: (a) **UI de crear/editar sucursales** (#2, el RPC existe); (b) **mecanismo de asignar `sucursal_id` a un miembro** (NO existe RPC `asignar_sucursal_a_miembro` — verificado: las únicas funciones sucursal son `mi_sucursal`, `sucursal_visible`, `crear_sucursal`, `stats_*`); (c) decidir partición de roles (mig 114 ya la fija: EXENTOS `{admin, gerente_farmacia, finanzas, pagador}`; CONFINABLES `{supervisor, inventario, cajero, dependiente, delivery}`). El `NULL = grandfather` garantiza que mientras no se asigne, nada se rompe.

> **Nota de alcance C.2:** mig 114 solo confina `farmacia_medicamentos` (inventario/stock). El **buzón de recetas** (`listar_recetas_entrantes`) **NO** tiene término de sucursal (filtra solo por empresa — ver #9).

---

# CARRIL A-bis — Asignación de personal a sucursal

## #4 — Pantalla "Personal y roles" del admin de farmacia
`src/farmacia/pages/FarmaciaPersonalPage.tsx`. Dos acciones, **ninguna toca `sucursal_id`**:
- **Editar rol** → `asignar_rol_miembro(p_target_id, p_nuevo_rol)` (`:54-64`). El RPC (mig 079) solo hace `UPDATE cuentas_proveedor SET rol_en_empresa=… WHERE id=…`. Sin sucursal.
- **Invitar** → `invitar_miembro_farmacia(p_email, p_nombre, p_nuevo_rol, p_telefono)` (`:69-85`). El RPC (mig 080) inserta en `invitaciones_visitador` con `empresa_id` (forzado) + `rol`; **sin columna/param de sucursal**. El form (`:169-176`) solo pide nombre/email/rol.
- Aceptación (`aceptar_invitacion_proveedor`, mig 080) inserta `cuentas_proveedor (id, empresa_id, email, nombre_completo, telefono, rol_en_empresa, activo)` → **`sucursal_id` queda en su DEFAULT NULL.**

→ **El campo existe en la tabla pero ningún flujo de alta/edición lo setea.** Todo miembro nace empresa-wide. La asignación a sucursal es la pieza faltante de C.2 (#3).

## #5 — Routing post-login
**Decisión por `empresa.tipo` únicamente; NUNCA lee `sucursal_id`.**
- `FarmaciaLogin.tsx:29-41` (y `ProveedorLogin.tsx:30-47`, idéntico): `select('empresa:empresa_id(tipo)')` → switch `tipo === 'farmacia'` → `/farmacia/dashboard`.
- `useProveedorAuth.ts:15-18` trae `select('*, empresa:empresa_id(*)')` (incluye `sucursal_id` en `*`) pero **no hay rama que lo use** para routing/contexto. Permisos se derivan de `cuenta.rol_en_empresa` (`:182-186`).
- **Con `sucursal_id NULL` (todos hoy):** cae a la vista de empresa (ve todas las sucursales). El único uso de `sucursal_id` en el front es la *sucursal de la fila de datos* en `FarmaciaReportesPage` (no la del usuario).

## #6 — Cardinalidad de `cuentas_proveedor`
- **PK = `id` (solo).** No hay UNIQUE adicional (ni en `auth_user_id` ni en `email`). El `id` ES el auth user id (la fila se inserta con `id = p_user_id`, mig 049/080).
- → **Modelo 1:1 estricto: un auth user = exactamente UNA fila = UNA empresa + UNA sucursal.** La estructura **NO soporta** un empleado en varias sucursales ni en varias empresas. Cualquier modelo de "empleado multi-sucursal" requeriría rediseño (tabla puente). Para C.2 tal cual (1 usuario → 1 sucursal), la cardinalidad actual alcanza.

---

# CARRIL B — Ruteo receta médico → farmacia

## #7 — Selector de farmacia en el flujo de receta
- UI: `RecetaModal.tsx` — botón por-ítem `abrirModalFarmacia(idx)` (`:347`) → búsqueda → `seleccionarProveedor` setea `item.farmacia_id = proveedor.farmacia?.id` (`:142`).
- **Query que alimenta la búsqueda:** `useBusquedaMedicamentos.ts:62-70` (`buscar`, usado vía alias `buscarEnProveedor`):
  ```ts
  supabase.from('farmacia_medicamentos')
    .select(`*, farmacia:farmacia_id(id, nombre, direccion, telefono, email, encargado, horario, tipo)`)
    .ilike('nombre_medicamento', `%${query}%`).gt('stock_actual', 0).order('precio_unitario')
  ```
  - Consulta **`farmacia_medicamentos`** (inventario), la farmacia llega como join. **NO filtra por `empresa_id`** ni por tipo (filtro farmacia/lab se hace en cliente, `RecetaModal.tsx:153-158`). Único filtro: `stock_actual > 0`.
- **El médico VE el catálogo global (empresa_id NULL)**: la RLS `farm_med_disp_medico` (mig 086:43-45) da SELECT a todo médico/super_admin **sin condición de empresa** → ve catálogo global + farmacias-tenant indistintamente. (Mismo patrón en `RecetasPage.tsx:29,99,110,139`.)

## #8 — Columna que guarda la farmacia destino
- **`receta_items.farmacia_id`** (FK → `farmacias.id`). Insert: `useRecetas.ts:83`. Ruteo es **por-ítem** (cada medicamento a su farmacia).
- **`recetas` NO tiene columna de farmacia/sucursal** (verificado). El "tiene farmacia" se deriva de los ítems (`useRecetas.ts:28-35`).
- **No hay `sucursal_id` en `receta_items`** — habría que agregarlo si se quiere rutear a sucursal específica (hoy el `farmacia_id` ya apunta a una fila de `farmacias`, que ES una sucursal, pero el buzón despacha a nivel empresa — ver #9).

## #9 — `useRecetasEntrantes` (buzón): query y por qué filtra por empresa
- El hook solo llama RPCs DEFINER (`listar_recetas_entrantes`, `detalle_receta_entrante`, `registrar_dispensacion_dirigida`); la UI nunca toca tablas (RLS cerrada).
- `listar_recetas_entrantes` (mig 090:71-84) filtra:
  ```sql
  JOIN farmacias f ON f.id = ri.farmacia_id
  WHERE COALESCE(f.empresa_id = v_emp, false) AND ri.dispensado = false   -- v_emp = mi_empresa_proveedor()
  ```
- **Filtra por EMPRESA, no por sucursal** → buzón central por empresa (cualquier usuario de la empresa ve todos los ítems ruteados a cualquier farmacia de su empresa). No hay vista separada admin-central vs bandeja-por-sucursal.
- **Para soportar central-admin + por-sucursal** (observación de estructura, no propuesta): el RPC tendría que ANDear opcionalmente un término de sucursal análogo a `sucursal_visible` (ya existe el helper) — hoy ese término **no está** en el buzón (solo en `farmacia_medicamentos`).

## #10 — Censo de las 6 farmacias `empresa_id NULL` + 9 receta_items ruteados
- **FKs entrantes a `farmacias`** (4): `farmacia_medicamentos.farmacia_id`, `dispensaciones.farmacia_id`, `receta_items.farmacia_id` (`receta_items_farmacia_fk`), `cuentas_proveedor.sucursal_id`.
- **Datos:** los **9 `receta_items` ruteados apuntan TODOS a farmacias con `empresa_id = NULL`** (catálogo global); **0 a farmacias de empresa real**. → Con el filtro de #9, **ninguna receta ruteada hoy llega a un buzón** (las farmacias elegidas no tienen dueño-empresa).
- **No se borró nada** — censo: estas 6 farmacias globales **tienen dependencias** (son referenciadas por `farmacia_medicamentos` del catálogo global que el médico busca, y por los 9 `receta_items`). Decisión limpieza-vs-migración queda para el revisor: borrarlas rompería los `receta_items` existentes (FK) y el catálogo global de búsqueda del médico.

---

# CARRIL C — Delivery (épico nuevo)

## #11 — Módulo de mapa/ruteo del visitador (reutilizable)
- **Librería: react-leaflet + Leaflet + OpenStreetMap** (sin API key en el front). Navegación externa por **deep-link a Google Maps y Waze**. (Google API key solo en backend, edge `geocodificar`.)
- `VisitadorRutaPage.tsx:13-26,257-286` — `MapContainer/TileLayer(OSM)/Marker/Popup/Polyline`; deep-links `:43-50,96,111`.
- **`src/components/MapaInteractivo.tsx`** — componente genérico `<MapaInteractivo lat lng onChange>` con pin arrastrable + click-to-set (default Guatemala `[14.6349,-90.5069]`). **Directamente reutilizable** para fijar direcciones de entrega.
- **Coordenadas:** tabla `ubicaciones_medico_proveedor` (`lat/lng/direccion/notas`, `UNIQUE(empresa_id, medico_id)`, mig 016) leída por RPC DEFINER `get_ubicaciones_con_medico`. Hook `useUbicacionesMedico.ts`.
- **Cálculo de ruta:** `useRutaVisitador.ts` — orden por hora, distancia **Haversine** (`:75-84`), ETA buffer `2min/km+5min`. **Sin TSP ni Directions API.**
- **Geocodificación:** edge `geocodificar` (Google Geocoding si hay key, fallback **Nominatim/OSM**, `region/countrycodes=gt`).
- **Reutilizable para delivery:** `MapaInteractivo`, edge `geocodificar`, patrón tabla `lat/lng/direccion`+RPC DEFINER, deep-links Waze/Google, Haversine. **Falta para entregas serias:** optimización de ruta real, tracking en vivo, Directions/Distance Matrix.

## #12 — Rol "Delivery" en la matriz de permisos
- **Dos matrices conviven:** (A) `permisos.ts` hardcoded (visitador-céntrico, **sin** rol delivery); (B) **data-driven en BD** (`roles_empresa_catalogo`/`permisos_empresa_rol`, mig 079) — **aquí SÍ existe `delivery`**.
- **Catálogo farmacia (9 roles, BD viva):** admin(100,admin), gerente_farmacia(80), supervisor(60), inventario(40), finanzas(40), pagador(40), cajero(20), dependiente(20), **delivery(20)**.
- **Acción `delivery`** la tienen `{admin, gerente_farmacia, supervisor, delivery}` (mig 079). Helper `private.tiene_permiso('delivery')`.
- **Estado: el rol/acción existen pero NINGÚN flujo los usa.** `tiene_permiso('delivery')` no aparece en ninguna policy/RPC; en `src/**` no hay archivo con `delivery`. `delivery` está explícitamente FUERA del despacho QR (mig 085:7) y listado como CONFINABLE a sucursal (mig 114). **No existe tabla `entregas`/`reparto`/`envio_domicilio`.** → **El flujo de entregas es 100% nuevo; solo está reservado el slot de rol/permiso.**

## #13 — Chat interno: ¿entra delivery natural?
**NO es plug-and-play — el gate excluye por allowlist hardcodeada de roles** (que no incluye `delivery` ni roles de farmacia):
- `es_miembro_conversacion` (mig 053:68-69): canal `administracion` → `rol IN ('admin','editor','supervisor','catalogo','marketing','finanzas')`. `delivery` no está.
- `sincronizar_mis_canales` (mig 056:15): misma allowlist; canal `equipo` solo si hay `equipo_id` (visitadores).
- `contactos_chat` (mig 054:20-31) y `destinatarios_conversacion` (mig 057:14-24): matriz sin `delivery`.
- → Para que un repartidor chatee con su farmacia hay que **tocar gates** (agregar roles de farmacia a esas allowlists). El chat asume el modelo de roles del visitador, no el data-driven de farmacia.

---

# CARRIL D — Invitación de personal (Opción B)

## #14 — Piezas reutilizables
- **`crear-staff-clinica` (edge) es el patrón candidato:** `index.ts:23-25,68-73` `createClient(service_role)` + `auth.admin.createUser({email, password, email_confirm:true})` (auto-confirma, evita round-trip).
- **Email existente:** `auth.admin.createUser` devuelve **error real** → mapea a HTTP 409 "Este email ya está registrado" (`:74-80`). (Contraste con el `signUp` cliente roto de #16.)
- **Credencial vía Resend** (best-effort): `:139-168` (password temporal en el email + en la respuesta JSON). Incluye autz del solicitante por header+rol (`:43-65`) + rollback en cascada (`:96-137`).
- **Cardinalidad** (cruce #6): PK `cuentas_proveedor.id = auth.uid` → 1:1; un invitado = 1 fila. Encaja con `createUser` + insert de membresía.
- **Gate del invitador (farmacia actual):** `invitar_miembro_farmacia` (mig 080) ya valida empresa+rol del invitador server-side.

---

# CARRIL E — Arreglos de auditoría del panel

## #15 — Gap de permiso de inventario — ❌ FALSO POSITIVO (corrección 2026-06-23, verificado en BD viva + probes red-first)
- **La policy VIVA `farm_med_tenant_all` SÍ gatea escritura por `inventario_editar`** en USING **y** WITH CHECK: `COALESCE(private.tiene_permiso('inventario_editar'),false) AND empresa AND sucursal_visible`. Añadido en **mig 079** (`:97`), reforzado en **mig 114** (`:52,58`). El recon original leyó **mig 078** (superseded) y un excerpt de 114 que se saltó la línea 52.
- **Probes en vivo (rolled-back):** cajero (sin `inventario_editar`, `sucursal_id=NULL` → término sucursal pasa) → INSERT **DENEGADO (42501)**, UPDATE/DELETE **DENEGADO (0 filas)**; SELECT del cajero **PASA** (vía `farm_med_propia_empresa`); admin (con permiso) UPDATE **PASA**. → escritura cerrada por permiso, lectura intacta.
- **El comentario `086:65` `[inventario_editar + empresa]` es CORRECTO**, no drift (lo fue desde mig 079).
- **Residual menor aparte (no R11) — ✅ APLICADO en prod 2026-06-23:** `anon` tenía grants de tabla `INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER` sobre `farmacia_medicamentos`. INSERT/UPDATE/DELETE eran inertes bajo RLS, pero **TRUNCATE/TRIGGER NO son RLS-gated** (hueco latente). Aplicado `REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.farmacia_medicamentos FROM anon;` → grants resultantes de `anon` = **solo `SELECT`**; `authenticated` intacto (7 verbos). Harness post-apply en vivo: 424 filas, 0 ROJO, scan limpio, 3 Pinv verdes. (Censo sistémico de grants a `anon` en todo `public` queda encolado — ver pendientes-roadmap.)
- **Texto original (incorrecto), conservado para trazabilidad:** ~~(a) la UI solo oculta `FarmaciaInventarioPage.tsx:36,105-166`; (b) la policy `farm_med_tenant_all` no exige `inventario_editar` (leyó mig 078); comentario 086:65 = drift.~~ La parte (a) (UI oculta) es cierta; (b) y el "drift" son falsos.

## #16 — Bug éxito-falso en signup de invitación (CONFIRMADO)
`ProveedorRegistroVisitador.tsx:55-119` (página compartida; el link de farmacia apunta aquí):
- `:73` `supabase.auth.signUp({email, password})` (cliente, no admin).
- Con email **ya existente + "Confirm email" ON**: signUp **no devuelve error** (anti-enumeración) → `authData.user` presente pero **`session = null`**.
- `:78` no entra (authError null); `:89` pasa (user presente); `:102` **se salta** `aceptarInvitacionPendiente()` (requiere `session`); `:111` `setRegistrado(true)` → UI muestra "¡Registro exitoso!".
- → **La UI dice "registrado" pero la membresía `cuentas_proveedor` nunca se crea** (el RPC de aceptación solo corre autenticado, en login). El dueño del email preexistente no completa ese login con la contraseña que tecleó. **Es la causa del "invité y no puede entrar".** (cruza con el self-invite de Oscar: invitación `oscarabadgutierreztomas@gmail.com` quedó `pendiente`, su auth user ya existía y estaba confirmado, sin fila en `cuentas_proveedor`.)
- Contraste: `crear-staff-clinica` (#14) usa `createUser` → error real en duplicados, sin éxito-falso.

## #17 — Menores
- **`/farmacia/pagos`:** monta `ProveedorPagosPage` genérico (`App.tsx:369`); igual `perfil`→`ProveedorPerfilPage`, `notificaciones`→`ProveedorNotificacionesPage`. Solo dashboard/inventario/recetas/reportes/personal tienen componente `Farmacia*` propio. → Reutilización genérica; confirmar si tiene sentido funcional para farmacia.
- **Naming ruta de registro:** el link de invitación de farmacia apunta a `/proveedor/registro-visitador` (`FarmaciaPersonalPage.tsx:82`) aunque el RPC sea `invitar_miembro_farmacia`. Naming heredado del visitador.
- **`useRecetasEntrantes.detalle` / `detalle_receta_entrante`: dead code.** Definido y exportado (`useRecetasEntrantes.ts:53-57,93`) pero **sin consumidor** (los 2 usuarios del hook solo desestructuran `listar`/`despacharDirigido`/`verificarToken`/`despacharWalkin`).
- **Dashboard farmacia (`FarmaciaDashboard.tsx`):** conteos consistentes (no hay stat por campo inexistente ni 0-fijo, a diferencia del dashboard de laboratorio). Matiz menor: `bajoStock` (`:24`) marca `stock 0` con `stock_minimo` NULL como bajo stock (`0<=0`). No muestra conteo de recetas entrantes (la actividad operativa principal queda fuera del dashboard).

---

# Resumen para los tres carriles

| Carril | Estado verificado | Pieza faltante / pendiente |
|---|---|---|
| **A — Sucursales (C.2)** | Policy de inventario YA confina por sucursal (mig 114), grandfather-inerte (0/12 asignados). `crear_sucursal` existe (sin geo). | UI crear/editar sucursal; **RPC `asignar_sucursal_a_miembro` NO existe**; campo sucursal en alta de personal (#4); buzón de recetas NO confina por sucursal (#9). Cardinalidad 1:1 user↔sucursal (#6). |
| **B — Ruteo receta + buzón** | Ruteo por-ítem a `receta_items.farmacia_id`; buzón filtra por empresa (#9); médico ve catálogo global (#7). | **Bloqueante de datos:** 9/9 ítems ruteados a farmacias `empresa_id NULL` → no caen en ningún buzón (#10). Sin `sucursal_id` en receta_items (#8). |
| **C — Delivery (nuevo)** | Rol/permiso `delivery` reservado en catálogo (mig 079, confinable mig 114); mapa Leaflet+OSM + `MapaInteractivo` + `geocodificar` reutilizables (#11). | Flujo de entregas 100% nuevo (sin tabla `entregas`); chat NO admite delivery sin tocar allowlists (#13). |
| **D — Invitación (Opción B)** | Patrón `crear-staff-clinica` (service_role + createUser + Resend + 409 en duplicado) reutilizable (#14). | Bug éxito-falso en signup cliente (#16) a reemplazar por el patrón admin. |
| **E — Arreglos auditoría** | #15 ❌ FALSO POSITIVO (policy ya gatea `inventario_editar`, mig 079/114, probado en vivo); #16 éxito-falso signup, #17 menores — confirmados. | #15 sin fix (cerrado); residual menor: REVOKE grants `anon` (inerte). #16/#17 pendientes. |

*Fin del recon. Nada implementado; el revisor estructura la ruta.*
