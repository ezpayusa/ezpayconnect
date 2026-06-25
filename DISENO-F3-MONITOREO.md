# DISEÑO — F3 · Panel de monitoreo (admin/gerente) — SOLO DOC

> Monta DENTRO del panel **Farmacia** → estética `#1E5C8E` + shadcn (calce con FarmaciaLayout/Dashboard existentes),
> guiado por los mockups de Claude Design (dashboard admin + gerente). **Cero lógica nueva**: solo cablea RPCs vivos.
> **Nada toca prod hasta OK paso a paso de Oscar.** Leí el frontend-design skill; aplico cohesión con el panel Farmacia.
>
> **Backend vivo (verificado):**
> - `listar_entregas_monitoreo(p_estado, p_sucursal_id, p_delivery_id, p_desde, p_hasta)` → gate `entregas_ver`. Devuelve por fila:
>   `id, estado, farmacia_id, sucursal_nombre, delivery_id, delivery_nombre, monto, cobrado, cobrado_at, cobrado_por,
>   metodo_cobro, intentos, motivo_fallo, reabierta_at, asignado_at, entregado_at, created_at, paciente_nombre,
>   direccion_entrega, telefono_contacto, evidencia_path, lat, lng, disc_monto (bool), disc_cobrada_fallida (bool)`.
>   **NO expone medicamentos** (anti-patrón respetado). `evidencia_path` = PATH (no URL).
> - `stats_entregas_sucursal(p_desde, p_hasta, p_sucursal_id)` → por sucursal: `total, pendiente, asignada, en_camino,
>   entregada, fallida, pct_exito, monto_cobrado, reintentos` (+ conteos de discrepancia, Ola E).
> - `reconciliar_entregas_faltantes(p_sucursal_id)` → `receta_base_id, farmacia_id, sucursal_nombre, fallo_log` =
>   grupos delivery despachados **SIN** entrega (de `receta_items` modalidad delivery sin fila en `entregas`, + flag de
>   `private.delivery_autocreate_fallos`).
> - `actualizar_direccion_entrega(p_entrega_id, p_direccion, p_lat, p_lng)` + edge `geocodificar` (gate gestión).
> - `asignar_entrega(p_entrega_id, p_delivery_id uuid)` · `reasignar_entrega(p_entrega_id, p_delivery_id uuid)` (gestión).

## 1. Q1 en la UI (no violar)
- `gerente_farmacia` es **EXENTO = nivel EMPRESA** → ve **TODA la cadena**, igual que admin. El **selector de sucursal
  es FILTRO VOLUNTARIO** (parámetro `p_sucursal_id` opcional de los RPCs), **NO** confinamiento.
- El "gerente de sucursal" del mockup = rol **CONFINABLE** → el backend ya lo acota (los RPCs confinan por
  `entrega_visible`/`sucursal_visible`). **La UI NO agrega ningún predicado** de sucursal.
- **Regla dura:** la UI **NUNCA** lee el `sucursal_id` de un exento para confinarlo. **Todo** (qué sucursales hay, qué
  filas se ven) se **deriva de lo que devuelven los RPCs** — que ya confinan. El selector de sucursal se puebla con las
  `sucursal_nombre`/`farmacia_id` **presentes en las filas devueltas** (no de una tabla aparte) → un confinable solo verá
  su sucursal en el selector (porque el RPC solo le devuelve esa), sin lógica de front.

## 2. Vista principal — lista de entregas (`listar_entregas_monitoreo`, gate `entregas_ver`)
- **Tabla** (desktop) / **cards** (mobile) con: estado (badge color, reusar `colorEstado`), `delivery_nombre`,
  `sucursal_nombre`, `monto`, `cobrado` (✓/—), `intentos`, `motivo_fallo`, `paciente_nombre`.
- **Filtros:** estado · **sucursal** (selector voluntario; opciones derivadas de las filas) · delivery (derivado de las
  filas: `delivery_id`/`delivery_nombre` distintos) · rango de fecha (`p_desde`/`p_hasta`). Cada filtro re-llama el RPC.
- **Flags de discrepancia por fila** (badges + leyenda/tooltip):
  - `disc_monto` (#1): "Monto cobrado menor al despachado".
  - `disc_cobrada_fallida` (#3): "Marcada fallida pero con cobro registrado".
- **Evidencia:** si la fila tiene `evidencia_path`, abrir con **`openSignedUrl('entregas-evidencia', path)` (120 s)** —
  **NUNCA `getPublicUrl`**.
  - **GAP a marcar:** `listar_entregas_monitoreo` hoy devuelve **un solo `evidencia_path`** (columna legacy), **no** el
    array `entrega_evidencias` (foto/firma separadas, F1.5). Para mostrar **foto y firma separadas en monitoreo** hace
    falta extender ese RPC de lectura (agregar el array) — eso es **lógica nueva mínima**, fuera del "cero lógica" de F3.
    **Sub-decisión Oscar:** (a) F3 muestra solo `evidencia_path` (la última) por ahora, o (b) se agrega un follow-up que
    extienda `listar_entregas_monitoreo` con el array de evidencias. (No puedo usar `detalle_entrega_delivery`: está
    confinado a `delivery_id=auth.uid()` → el gestor recibiría RAISE.)
- **PII:** `paciente_nombre`/`direccion_entrega`/`telefono_contacto` salen acá **dentro del scope del caller** (el RPC
  confina por empresa+sucursal). **NO se muestran medicamentos** (exclusivos de la PWA del delivery asignado; el RPC no
  los devuelve). La UI no pide ni infiere meds.

## 3. Stats (`stats_entregas_sucursal`)
- **Tarjetas por sucursal** (una card por fila del RPC): conteos por estado, entregadas/fallidas, **% éxito**
  (`pct_exito`), **monto cobrado**, **reintentos**, conteos de discrepancia. Opcional un gráfico de barras por estado.
- Respeta Q1: el exento ve **todas** sus sucursales (el RPC devuelve N filas); el confinable ve **una**. El selector de
  rango de fecha (`p_desde`/`p_hasta`) y el de sucursal alimentan el RPC.

## 4. Reconciliación (`reconciliar_entregas_faltantes`, discrepancia #2)
- **Panel/alerta SEPARADO** de la lista normal (la fila **no existe** en `entregas` → no es una entrega editable). Lista
  grupos `(receta_base_id, farmacia, sucursal_nombre)` **despachados SIN entrega**, con flag `fallo_log` (hubo fallo en
  el auto-create best-effort). Presentación: banner/lista de alertas "Entregas faltantes a reconciliar" con conteo.
- Acción sugerida: link al grupo / aviso para crear la entrega manual (si las acciones de gestión entran en F3 — ver §6).

## 5. Geocodificación (reubicada a F3 — decisión #7 de F1)
- El **GESTOR** (no el repartidor) dispara `actualizar_direccion_entrega(p_entrega_id, p_direccion, p_lat, p_lng)` +
  edge `geocodificar(direccion)` **desde el monitoreo**, on-demand: al **abrir una entrega sin coords** (`lat/lng` null)
  o al corregir una dirección. Gate **`entregas_gestionar`**.
- **Control:** botón "Geolocalizar / Corregir dirección" → abre un panel con la `direccion_entrega` editable +
  **`MapaInteractivo`** para ver/ajustar el pin; "Geolocalizar" llama al edge `geocodificar` (texto→lat/lng) y precarga
  el pin; "Guardar" llama `actualizar_direccion_entrega`. **Best-effort:** si geocodificar falla, **no bloquea** — el
  gestor puede guardar la dirección sin coords o ajustar el pin a mano (toast claro, no error fatal).
- **PII:** la dirección del paciente se envía al geocoder **solo** desde el scope del gestor que ya la ve (es la entrega
  confinada); no se expone fuera de scope. El botón solo aparece si `tienePermiso('entregas_gestionar')`.

## 6. Acciones de gestión desde el monitoreo (¿F3 o diferir?)
- **`actualizar_direccion_entrega`** (corregir dirección/geocode): **va en F3** (§5) — es el ítem que se reubicó acá.
- **`asignar_entrega` / `reasignar_entrega`** (gate `entregas_gestionar`): asignar un delivery a una entrega
  pendiente / reasignar (con sus salvaguardas server-side). **Requieren una LISTA de deliveries** de la empresa
  (`cuentas_proveedor` rol `delivery`) que **hoy ningún RPC expone** → necesitaría un endpoint de listado (lógica nueva).
- **Recomendación:** **F3 = monitoreo (lectura) + reconciliación + geocode/corregir dirección.** **Diferir
  asignar/reasignar a un F3.1** (necesitan la lista de deliveries + UI de las salvaguardas de reasignación). Así F3 cierra
  la **visibilidad** sin abrir trabajo nuevo de backend. (Decisión de Oscar — ver abajo.)

## 7. Dónde monta
- **Nav:** ítem nuevo en `FarmaciaLayout` (`NavItem { label: 'Entregas', path: '/farmacia/entregas', icon: Truck,
  accion: 'entregas_ver' }`) — el layout ya filtra por `tienePermiso(accion)`.
- **Ruta:** `/farmacia/entregas` (lista + stats + reconciliación, con tabs o secciones). Sub-vista/panel para geocode.
- **Estados:** loading (skeletons), empty ("No hay entregas en este rango/filtro"), error (reintentar). Reusar
  `tienePermiso`, `openSignedUrl`, `MapaInteractivo`, `colorEstado`.

## Archivos / componentes (estimado)
| Archivo | Rol |
|---|---|
| `src/farmacia/pages/EntregasMonitoreoPage.tsx` | página: tabs Lista / Stats / Reconciliación + filtros |
| `src/farmacia/hooks/useEntregasMonitoreo.ts` | consume los 3 RPCs de lectura + estados |
| `src/farmacia/components/EntregaRow.tsx` (o cards) | fila con badges disc + evidencia (signed URL) |
| `src/farmacia/components/StatsSucursales.tsx` | tarjetas/gráfico de `stats_entregas_sucursal` |
| `src/farmacia/components/ReconciliacionPanel.tsx` | alerta de faltantes |
| `src/farmacia/components/GeocodeEntregaDialog.tsx` | corregir dirección + MapaInteractivo + geocodificar (gate gestión) |
| `src/App.tsx` + `FarmaciaLayout.tsx` | ruta + nav item gated `entregas_ver` |

## Plan e2e QA
1. **Admin** (empresa) → ve **todas** las sucursales/entregas de su empresa; filtros funcionan.
2. **`gerente_farmacia` (exento)** → ve **toda la cadena igual que admin** (Q1); el selector de sucursal es filtro
   voluntario; **no** se confina por su `sucursal_id`.
3. **Rol confinable** (gerente de sucursal) → solo ve **su** sucursal (porque el RPC confina); el selector solo ofrece esa.
4. **Filtros** estado/sucursal/delivery/fecha → re-llaman el RPC y acotan.
5. **Discrepancias:** `disc_monto` (#1) y `disc_cobrada_fallida` (#3) como **badges** por fila con leyenda; **#2** como
   **alerta separada** (reconciliación), no como fila.
6. **Geocode best-effort:** abrir entrega sin coords → geolocalizar (edge) → pin en MapaInteractivo → guardar
   (`actualizar_direccion_entrega`); si el edge falla, se puede guardar a mano (no bloquea). Solo con `entregas_gestionar`.
7. **Evidencia** por **signed URL 120 s** (nunca getPublicUrl).
8. **Meds NO aparecen** en ninguna vista de monitoreo.
9. **PII** (paciente/dirección/teléfono) solo dentro del scope del caller; cross-empresa no ve nada (RPC confina).

## Decisión para Oscar
1. **Alcance de F3:** (a) **solo monitoreo + geocode + reconciliación** [recomendado] vs (b) **+ acciones de gestión
   (asignar/reasignar)** — (b) requiere exponer la lista de deliveries (lógica nueva) + UI de salvaguardas.
2. **Evidencia en monitoreo:** (a) mostrar solo `evidencia_path` (última) tal como viene hoy [más simple] vs (b) extender
   `listar_entregas_monitoreo` con el array `entrega_evidencias` para foto/firma separadas (follow-up de backend).
