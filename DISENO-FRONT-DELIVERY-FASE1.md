# DISEÑO — FRONT del módulo DELIVERY Fase 1 (4 superficies, sub-olas)

> Doc de diseño para revisión. **NO es código.** Nada se construye/aplica/deploya hasta OK de Oscar **por sub-ola**.
> **El backend A→F ya está en prod (migs 144–150).** El front **NO crea lógica de negocio**: cablea UI a RPCs vivos
> y **respeta los gates/confinamientos que el backend ya impone** (RLS + DEFINER). Cada sub-ola es **aditiva** y
> **deployable independiente** (el backend no cambia). Stack: React 19 + TS + Vite + Supabase.

## Principios compartidos (las 4 superficies)
- **Consumir RPCs vivos, no reimplementar reglas.** El confinamiento (empresa+sucursal_visible+slice delivery), el
  techo de `entregas_cobrar`, el freeze de modalidad, el monto re-derivado, etc. los impone el **backend** — el front
  solo refleja (deshabilita controles, muestra estados), nunca es la fuente de verdad.
- **Reutilizables vivos:** `@/lib/signedUrl` → `openSignedUrl(bucket, path, {download?})` (firma cliente, **TTL 120 s**,
  exige SELECT en `storage.objects` → quien no tiene derecho no firma); `MapaInteractivo({lat,lng,onChange,height})`
  (Leaflet+OSM); edge **`geocodificar`** (texto→lat/lng); `useProveedorAuth` (cuenta/empresa/rol); `useFarmaciaPermisos`
  (`tienePermiso(accion)`); PWA infra existente (`vite` + `src/sw.ts`).
- **PII/scope (transversal):** la **dirección/teléfono del paciente** salen **solo** en el flujo delivery confinado
  (F1 repartidor sobre SU entrega, F3 monitoreo confinado). El pickup/mostrador (F4) y la bandeja **siguen viendo solo
  nombre**. **NUNCA `getPublicUrl`** en buckets privados (lección R9 — el repo tiene ese bug en lab/proveedor; NO copiar).
- **RPCs vivos por superficie:** F1 → (cola por RLS) + `actualizar_estado_entrega`, `registrar_cobro_entrega`,
  `registrar_evidencia_entrega`, `actualizar_direccion_entrega`; F2 → `fijar_modalidad_grupo`; F3 →
  `listar_entregas_monitoreo`, `stats_entregas_sucursal`, `reconciliar_entregas_faltantes`; F4 →
  `buscar_recetas_pendientes_paciente` + `registrar_dispensacion_dirigida`.

## Plan de sub-olas (F1 primero, por decisión de Oscar)
| Sub-ola | Superficie | Depende de | Deployable indep. |
|---|---|---|---|
| **F1** | PWA repartidor | — (backend vivo) | **Sí** (la cola puede arrancar vacía; se prueba sembrando una entrega delivery por RPC) |
| **F2** | Selector modalidad (médico+paciente) | — | Sí (es lo que **puebla** el flujo: marca grupos delivery → al despachar nacen entregas) |
| **F3** | Panel monitoreo admin/gerente | — | Sí (lectura) |
| **F4** | Búsqueda mostrador (sin-QR) | — | Sí (ortogonal, pickup) |
- **Independencia:** cada una cablea RPCs ya vivos → ninguna rompe a las otras ni al backend. **Nota de flujo:** F2
  es lo que genera entregas delivery (sin marcar modalidad, la cola de F1 queda vacía en producción); para **probar F1
  en QA** se siembra una entrega delivery llamando `fijar_modalidad_grupo` + despacho (backend), sin necesidad de F2.
- **Orden recomendado:** **F1 → F2 → F3 → F4** (el pedido de Oscar). Alternativa válida: F2 antes que F1 si se quiere
  poblar el flujo real primero; no hay dependencia técnica dura.

═══════════════════════════════════════════════════════════════
# F1 · PWA REPARTIDOR (primera sub-ola — máximo detalle)
═══════════════════════════════════════════════════════════════
Superficie **móvil, instalable**, para el rol `delivery`. Es la única superficie nueva con su propio routing/layout.

## Routing + montaje
- **NUEVO `/repartidor/*`** (separado de `/farmacia/*`, que es desktop). En `src/App.tsx`, junto a las otras rutas de
  layout: `<Route path="/repartidor/*" element={<RepartidorPrivateRoute><RepartidorLayout/></RepartidorPrivateRoute>}>`.
- **`RepartidorPrivateRoute`** (nuevo, `src/repartidor/components/`): usa `useProveedorAuth`; permite solo si
  `cuenta?.rol_en_empresa === 'delivery'` y `empresa?.tipo === 'farmacia'`; si no, redirige. (El backend igual confina
  por RLS; este guard solo enruta/oculta.)
- **Login:** reusa el login existente (`/farmacia/login` o `/proveedor/login`, mismo `auth`); tras login, si el rol es
  `delivery` → redirigir a `/repartidor`. (Opcional: deep-link `/repartidor/login` que reusa el mismo form.)

## Archivos nuevos
- `src/repartidor/layout/RepartidorLayout.tsx` — shell móvil (header + bottom-nav simple: Cola / Perfil).
- `src/repartidor/components/RepartidorPrivateRoute.tsx`.
- `src/repartidor/pages/ColaPage.tsx` — lista de SUS entregas.
- `src/repartidor/pages/EntregaDetallePage.tsx` — detalle: estado, mapa, cobro, evidencia.
- `src/repartidor/hooks/useEntregasRepartidor.ts` — data + acciones (cablea RPCs).
- (Opcional) `src/repartidor/components/{EstadoStepper,CobroSheet,EvidenciaUploader}.tsx`.

## Datos + RPCs que consume
- **Cola (SUS entregas) [DECISIÓN OSCAR (1) = RPC, CERRADO]:** consume **`listar_entregas_delivery(p_estado,p_desde,p_hasta)`** (mig **151**, vivo): STABLE DEFINER sp'', gate `entregas_ver`, confinado `entrega_visible(...) AND delivery_id=auth.uid()` (solo las propias), superficie de columnas **controlada** (entrega_id, estado, receta_base_id, farmacia_id+sucursal_nombre, direccion_entrega, telefono_contacto, lat/lng, monto, cobrado, metodo_cobro, intentos, motivo_fallo, evidencia_path, asignado_at/entregado_at/created_at/updated_at). Orden: **estado activo primero** (en_camino→asignada→pendiente→entregada→fallida) luego `created_at DESC`. Filtros: `p_estado`, rango de fecha. → `supabase.rpc('listar_entregas_delivery', { p_estado, p_desde, p_hasta })`. El front **NO** hace `select` directo a la tabla.
- **Transición de estado:** `supabase.rpc('actualizar_estado_entrega',{p_entrega_id,p_nuevo_estado,p_motivo_fallo})`.
  Flujo del repartidor: **`asignada → en_camino → entregada | fallida(motivo)`** (el delivery **no** asigna — eso es
  gestión; recibe entregas ya `asignada`). `fallida` exige `p_motivo_fallo ∈ {rechazada,ausente,direccion_mala}`.
- **Cobro:** `supabase.rpc('registrar_cobro_entrega',{p_entrega_id,p_metodo_cobro})`. **El front NO envía monto** (el
  server lo re-deriva de `dispensaciones`); la UI **muestra** `monto` solo informativo. Métodos: efectivo/tarjeta/
  transferencia/sin_cobro.
- **Evidencia (foto/firma):** subir al bucket privado **`entregas-evidencia`** con path **`{empresa_id}/{entrega_id}/{firma|foto}_{ts}.jpg`**:
  `supabase.storage.from('entregas-evidencia').upload(path, blob)` → luego asociar:
  `supabase.rpc('registrar_evidencia_entrega',{p_entrega_id,p_path})`. **Leer** la evidencia con
  `openSignedUrl('entregas-evidencia', evidencia_path)` (TTL 120 s). **NUNCA `getPublicUrl`.**
- **Dirección/mapa:** `MapaInteractivo({lat,lng})` para mostrar el pin. Si `lat/lng` NULL → geocodificar al abrir:
  edge `geocodificar(direccion_entrega)` → `supabase.rpc('actualizar_direccion_entrega',{p_entrega_id,p_direccion,p_lat,p_lng})`
  (best-effort; si falla, mapa sin-pin + dirección por texto). `direccion_entrega`/`telefono_contacto` se muestran
  **solo aquí** (es la entrega del propio repartidor, confinada).

## Permisos que gatean (UI)
- Entrar a `/repartidor/*` → rol `delivery` (route guard) + RLS.
- **Cobro:** mostrar/habilitar el control **solo si** `useFarmaciaPermisos().tienePermiso('entregas_cobrar')`
  (techo 117; el admin decide si el delivery cobra). Si no lo tiene → **ocultar** el botón de cobro (el server haría
  RAISE igual; la UI no debe ofrecer lo que no puede).
- Estado/evidencia → `entregas_actualizar_estado` (el delivery lo tiene por default).

## Estados de UI
- **Loading:** skeleton de la cola / spinner en acciones.
- **Empty:** "No tenés entregas asignadas" (cola vacía es normal).
- **Error:** toast con el mensaje del RPC (los RAISE del backend son legibles: "no es tu entrega", "transición ilegal",
  "ya cobrada"); estado de **sin-conexión** explícito (ver offline).
- **Optimismo controlado:** tras un RPC OK, refrescar la fila desde el retorno del RPC (devuelve la entrega actualizada).

## PWA / offline
- **Instalable + móvil:** reusa la infra PWA (`vite` + `src/sw.ts`); agregar (o confirmar) `manifest` con scope que
  cubra `/repartidor`. Es la **app real** (no artifact) → puede usar Service Worker / cache del navegador.
- **Tolerancia a red intermitente (v1, simple):** el SW cachea el **shell** + la **última cola** leída (stale-while-
  revalidate) para que la app abra offline y muestre lo último. **Las ESCRITURAS (estado/cobro/evidencia) requieren
  online** → si no hay red, **bloquear la acción con estado "sin conexión, reintentá"** (NO cola de escritura offline en
  v1: evita inconsistencias de cobro/estado; el server es la verdad). **[Decisión Oscar futura]** una cola offline de
  acciones sería Fase 2 (requiere idempotencia/orden — el cobro ya es no-recobrable, el estado es idempotente, pero la
  evidencia y el orden de transición piden cuidado). Recomiendo **sin cola offline en v1**.

## Anti-patrones (PROHIBIDO)
- **NO** ver/operar entregas fuera de `delivery_id=auth.uid()` (la RLS lo impide; el front **no** debe intentar leer la
  tabla con otro filtro ni asumir más de lo que la RLS devuelve).
- **NO** enviar el monto como fuente de verdad en el cobro (display-only; el server re-deriva).
- **NUNCA `getPublicUrl`** sobre `entregas-evidencia` (privado) — siempre `openSignedUrl`.
- **NO** exponer la dirección/teléfono en ninguna superficie que no sea la entrega propia del repartidor (F1) o el
  monitoreo confinado (F3).

## Verificación F1 (e2e manual en QA)
Sembrar (backend) una entrega delivery: `fijar_modalidad_grupo(receta,farmacia,'delivery')` → despachar
(`registrar_dispensacion_dirigida`) → `asignar_entrega(entrega, delivery_qa)`. Luego, como **delivery QA**:
(1) la cola muestra **solo** esa entrega (no las de otros); (2) `en_camino`→`entregada` mueve el estado; `fallida`
pide motivo; (3) cobro: con `entregas_cobrar` el control aparece y cobra (monto = el del server); sin el permiso, el
control no aparece; (4) subir foto/firma → se asocia; abrir evidencia → signed URL 120 s (sin permiso/otra entrega →
no firma); (5) mapa con pin si hay coords, sin-pin si no; dirección visible. **Confinamiento:** un 2º delivery NO ve
la entrega del 1º.

═══════════════════════════════════════════════════════════════
# F2 · SELECTOR DE MODALIDAD (médico + paciente)
═══════════════════════════════════════════════════════════════
Un **único** RPC: `fijar_modalidad_grupo(p_receta_id, p_farmacia_id, p_modalidad)` (médico O paciente; freeze server-side).

## Médico — `src/components/consulta/RecetaModal.tsx`
- La agrupación por cadena/sucursal ya existe (~L187-198) y el ruteo per-ítem en ~L370 (`abrirModalFarmacia`). **Tras
  rutear** (cuando `item.farmacia_id` está seteado), mostrar un **toggle pickup/delivery por grupo de sucursal** →
  `supabase.rpc('fijar_modalidad_grupo',{p_receta_id, p_farmacia_id, p_modalidad})`. Al emitir aún por insert directo
  (pre-O1 regulatorio), la pre-marca se hace cuando ya hay `receta_id` + ítems con `farmacia_id`.
- **Freeze (UI):** deshabilitar el toggle si el grupo ya despachó (algún ítem `dispensado=true`); el server hace RAISE
  igual, pero la UI debe **reflejarlo** (tooltip "congelada: ya despachada"). 

## Paciente — `src/webapp/pages/WebAppRecetas.tsx` (~L97) + `src/webapp/hooks/useWebAppRecetas.ts` (~L51)
- Agrupar los ítems por `farmacia_id`; ofrecer pickup/delivery **por sucursal** → **mismo** `fijar_modalidad_grupo`.
- **Exponer `farmacia_id` y `modalidad`** en el `select` de `useWebAppRecetas` (~L51 hoy no los trae) para poder
  agrupar y mostrar el estado actual + el freeze.

## Permiso / estados / anti-patrón
- Gate: el RPC valida (médico de la receta O paciente dueño); el front solo muestra el control a quien corresponde.
- Estados: loading/disabled (freeze)/error (toast del RAISE). Anti-patrón: **no** intentar setear modalidad ítem-por-
  ítem (es **por grupo de sucursal**; el RPC actualiza todo el grupo) ni permitir `delivery` sin sucursal (el CHECK lo
  rechaza). **Última escritura gana** (médico pre-marca, paciente cambia) — la UI no bloquea, solo refleja el valor.

## Archivos
Editar `RecetaModal.tsx`, `WebAppRecetas.tsx`, `useWebAppRecetas.ts`; (opcional) componente `ModalidadToggle.tsx` compartido.

## Verificación F2
Médico marca un grupo delivery al rutear → al despachar nace la entrega (F1/E lo ven). Paciente cambia a pickup → no
nace entrega. Grupo ya despachado → toggle deshabilitado + RAISE si se fuerza. Otro paciente → no ve/!cambia.

═══════════════════════════════════════════════════════════════
# F3 · PANEL MONITOREO (admin / gerente)
═══════════════════════════════════════════════════════════════
Monta en el **panel farmacia** (`FarmaciaLayout`, desktop). Lectura confinada por el backend.

## Routing + montaje
- Nuevo nav item en `src/farmacia/layout/FarmaciaLayout.tsx`: `{ label:'Entregas', path:'/farmacia/entregas', icon:Truck, accion:'entregas_ver' }` (gateado por `tienePermiso`).
- Página `src/farmacia/pages/MonitoreoEntregasPage.tsx` + `src/farmacia/hooks/useMonitoreoEntregas.ts`.

## RPCs
- `listar_entregas_monitoreo(p_estado,p_sucursal_id,p_delivery_id,p_desde,p_hasta)` — lista confinada + flags
  `disc_monto`/`disc_cobrada_fallida` por fila.
- `stats_entregas_sucursal(p_desde,p_hasta,p_sucursal_id)` — tarjetas por sucursal (conteos, %éxito, monto cobrado,
  reintentos, conteos de discrepancia).
- `reconciliar_entregas_faltantes(p_sucursal_id)` — **vista/alerta aparte** ("despachado delivery SIN entrega").
- Evidencia: `openSignedUrl('entregas-evidencia', evidencia_path)` (120 s).

## Q1 en la UI (respetar al pie de la letra)
- `gerente_farmacia` es **EXENTO** → ve **toda la cadena, igual que admin**. La UI **NO** debe agregar ningún
  confinamiento por sucursal para el gerente. El **selector de sucursal** (que pasa `p_sucursal_id`) es un **filtro
  voluntario** de vista, **no** un confinamiento. El confinable (supervisor/…) ya lo acota el backend automáticamente.
- **Las 3 discrepancias:** `disc_monto`/`disc_cobrada_fallida` como **badges por fila** + contadores (de `stats`);
  `reconciliar_entregas_faltantes` como **panel/alerta separado** ("entregas faltantes a reconciliar", con acción de
  `crear_entrega` para el gestor).

## Estados / anti-patrón
- Loading (skeleton tabla/cards), empty ("sin entregas en el rango"), error (toast). Anti-patrón: **no** mostrar PII de
  pacientes fuera de lo que el RPC ya confinó (el RPC ya filtra; el front no debe pedir/derivar más); **no** persistir
  signed URLs.

## Verificación F3
Admin ve toda su empresa; **gerente_farmacia ve toda la empresa también** (incl. otra sucursal); confinable solo su
sucursal; selector de sucursal filtra sin relajar; badges de discrepancia correctos; faltantes en el panel aparte;
evidencia abre con signed URL; cross-empresa 0.

═══════════════════════════════════════════════════════════════
# F4 · BÚSQUEDA MOSTRADOR (despacho sin-QR)
═══════════════════════════════════════════════════════════════
Monta en el **panel farmacia** (bandeja/mostrador). Pickup puro, ortogonal al delivery.

## Routing + montaje
- En la bandeja de **Recetas entrantes** (`/farmacia/recetas`) o un sub-tab "Mostrador (sin QR)"; gateado por
  `tienePermiso('recetas_dispensar')`.
- Componente `src/farmacia/pages/BuscarPacienteMostrador.tsx` (o sección en la bandeja) + `hooks/useBuscarPacienteMostrador.ts`.

## RPCs
- `buscar_recetas_pendientes_paciente(p_nombre,p_apellido,p_fecha_nac)` → recetas con ítems pendientes (confinado) +
  `paciente_ref` opaco.
- Despacho posterior: `registrar_dispensacion_dirigida(p_receta_id,p_item_ids,p_farmaceutico)` (path vivo, 141-gated).

## Homónimos + PII
- **Homónimos:** el RPC devuelve varios pacientes, cada uno con **`paciente_ref` opaco** → la UI los agrupa y deja
  **seleccionar** cuál despachar **sin exponer el `paciente_id`** (el ref es solo un discriminador de display). El
  despacho usa `receta_base_id` + `item_id` (no el ref).
- **Mostrar SOLO:** nombre del paciente + recetas/ítems pendientes (med/dosis/cantidad). **NO** dirección/teléfono/
  expediente/diagnóstico (el mostrador sigue viendo solo nombre, como hoy).

## Permiso / estados / anti-patrón
- Gate `recetas_dispensar` (el RPC hace RAISE si no). Estados: input mínimo (nombre+apellido+fecha requeridos), loading,
  empty ("sin recetas pendientes para ese paciente en tu sucursal"), error. Anti-patrón: **no** búsqueda parcial/fuzzy
  en el front (el RPC es exacto; el front no debe simular prefijos); **no** mostrar PII; **no** exponer `paciente_id`.

## Verificación F4
Match exacto → recetas pendientes de la sucursal; no-match/prefijo → vacío; homónimos → 2 tarjetas con ref distinto y
opaco; seleccionar y despachar por `registrar_dispensacion_dirigida` funciona; cross-empresa/otra sucursal → vacío; no
aparece PII; ítem ya dispensado no aparece.

═══════════════════════════════════════════════════════════════
# Resumen de archivos por sub-ola + independencia
═══════════════════════════════════════════════════════════════
- **F1:** `src/repartidor/**` (layout, private-route, ColaPage, EntregaDetallePage, useEntregasRepartidor) + ruta en
  `App.tsx` + redirect de login del rol delivery. (Reusa `signedUrl.ts`, `MapaInteractivo`, edge `geocodificar`.)
- **F2:** edita `RecetaModal.tsx`, `WebAppRecetas.tsx`, `useWebAppRecetas.ts` (+ `ModalidadToggle` opcional).
- **F3:** `src/farmacia/pages/MonitoreoEntregasPage.tsx` + hook + nav item en `FarmaciaLayout.tsx`.
- **F4:** `src/farmacia/pages/BuscarPacienteMostrador.tsx` + hook + entrada en la bandeja.
- **Cada sub-ola = front aditivo sobre backend vivo** → deployable independiente, no rompe nada. Deploy = `git push`
  (Vercel auto-build); validar en **PREVIEW (rama)** antes de main (lección 25).

## Decisiones de Oscar (CERRADAS)
1. **F1 cola = RPC `listar_entregas_delivery`** (mini-mig 151, aplicada). El front consume el RPC, no `select` directo.
2. **F1 offline = SIN cola de escritura offline en v1** (SW cachea shell + última cola; toda escritura exige online).
3. **Orden de sub-olas = F1 → F2 → F3 → F4.**
