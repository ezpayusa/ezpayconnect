# DISEÑO — Meds visibles, cobrado_at y evidencias separadas (delivery) — SOLO DOC

> Las 3 decisiones de Oscar que convierten el pulido F1 en backend+UI. **Nada se migra/aplica/commitea acá.** Se aplica
> DESPUÉS, paso a paso; el pulido visual ya hecho espera en `feat/delivery-f1-pulido` para el merge conjunto.
>
> **Hechos en vivo (verificados):** `entregas` ya tiene `cobrado_at`, `cobrado_por`, `evidencia_path`. El **monto** de la
> entrega se RE-DERIVA de `SUM(dispensaciones.total_dispensado)` vía `recetas_avanzadas.receta_base_id` + `farmacia_id`.
> `dispensaciones.medicamentos_dispensados` (jsonb) = array `{item_id, nombre, cantidad}` = **snapshot de lo físicamente
> despachado** (se arma de `receta_items` al dispensar). `receta_items` tiene campos **clínicos** (`dosis, frecuencia,
> duracion, instrucciones`) que **NUNCA** se exponen. `medicamentos(nombre_comercial, presentacion, concentracion)`.
> **0 dispensaciones y 0 evidencias reales** en prod (la entrega 51 es seed manual).

---

## Decisión 1 — Medicamentos visibles al repartidor (PII clínica)
**RPC nuevo `detalle_entrega_delivery(p_entrega_id bigint)`** — DEFINER, `search_path=''`, STABLE, gate `entregas_ver`.
Confinamiento idéntico al resto del flujo delivery:
`empresa_id = public.mi_empresa_proveedor() AND COALESCE(private.sucursal_visible(farmacia_id),false) AND delivery_id = auth.uid()`.
Devuelve cabecera de la entrega **+ array de ítems** (y, por agrupación, también §2 y §3).

- **Fuente de verdad = `dispensaciones.medicamentos_dispensados`** (lo despachado), NO `receta_items` crudo (eso es lo
  *recetado*). Se mapea: `recetas_avanzadas WHERE receta_base_id = entrega.receta_base_id` → `ra_id`; luego
  `dispensaciones WHERE receta_avanzada_id = ra_id AND farmacia_id = entrega.farmacia_id`; se expande el jsonb array.
  **Reconcilia con el monto** (ambos salen de esas dispensaciones). `receta_items.dispensado` es alternativa, pero el blob
  es el snapshot autoritativo de cada dispensación.
- **[SUB-DECISIÓN PII — Oscar] ¿qué campos del ítem?**
  - (a) **nombre + cantidad** (directo del blob; sin join clínico). Mínimo para verificar el paquete.
  - (a)+presentación: une `item_id → receta_items.medicamento_id → medicamentos(nombre_comercial, presentacion,
    concentracion)` → "Amoxicilina 500mg · Cápsulas · x21". **SIN** `dosis/frecuencia/duracion/instrucciones`.
  - **Recomendado: (a)+presentación, sin contexto clínico.** El repartidor identifica el paquete, no el caso.
  - Regla dura: el RPC **no selecciona jamás** columnas clínicas (assert estructural en el harness).
- **[SUB-DECISIÓN — Oscar] ¿inline o detalle separado?** **Recomendado: detalle separado** (`detalle_entrega_delivery`)
  → la cola (`listar_entregas_delivery`) queda liviana; los meds se cargan al abrir la entrega. Inline = más data por fila.
- **Anti-patrón (fijo):** estos ítems **NO** van a monitoreo (F3) ni a ninguna superficie fuera de la PWA del delivery
  asignado. `listar_entregas_monitoreo` **no** devuelve ítems.
- **Migración:** **RPC nuevo de lectura** (sin DDL de tablas).

## Decisión 2 — `cobrado_at` (+ `cobrado_por` opcional) en el recibo
Las columnas **ya existen**. Solo exponerlas en lectura (en `detalle_entrega_delivery`; opcional también en la cola).
- Solo lectura, confinado igual. UI: "Cobro registrado · HH:MM" en el bloque de cobro.
- `cobrado_por` es uuid de cuenta proveedor (no paciente); mostrar "quién" requiere join a `cuentas_proveedor`
  (decisión menor — mostrar la **hora** sí; el "quién" opcional).
- **Migración:** **RPC extendido** (CREATE OR REPLACE de lectura; sin DDL).

## Decisión 3 — Foto Y firma como evidencias separadas
Hoy: un solo `entregas.evidencia_path`. **0 evidencias reales en prod → cambio limpio, sin backfill de datos.**
- **[SUB-DECISIÓN — Oscar] esquema:**
  - (a) **2 columnas** `entregas.foto_path` + `entregas.firma_path`. Más simple, menos joins; rígido (1 de cada tipo).
  - (b) **tabla `public.entrega_evidencias`** (`id, entrega_id FK, tipo CHECK IN ('foto','firma'), path, subido_at,
    subido_por, created_at`). N evidencias por tipo, rastro de auditoría, extensible.
  - **Recomendado: (b)** por extensibilidad y auditoría. Trade-off: (a) más simple, (b) más flexible/limpia.
- `registrar_evidencia_entrega(p_entrega_id, p_tipo, p_path)` ya recibe el tipo: con (b) hace **INSERT** en
  `entrega_evidencias`; con (a) hace **UPDATE** de la columna del tipo. El **path-scoping** actual
  `{empresa_id}/{entrega_id}/{tipo}_{ts}` y la **storage policy** ya encajan sin cambios.
- **RLS de la tabla nueva (b):** espejo — SELECT/INSERT con
  `empresa_id = mi_empresa_proveedor() AND sucursal_visible(farmacia_id) AND (delivery propio o entregas_gestionar)`;
  REVOKE U/D/TRUNCATE directo. (`entrega_evidencias` deriva empresa/farmacia de la entrega via JOIN o columnas espejo.)
- **Lectura:** `detalle_entrega_delivery` devuelve las evidencias (con (b) un array `{tipo, path}`; con (a) 2 campos).
  UI: 2 miniaturas "Ver foto" / "Ver firma" por **signed URL 120 s** (nunca `getPublicUrl`).
- **Migración:** (a) **columnas** + CREATE OR REPLACE de `registrar_evidencia_entrega` (+ deprecar/migrar `evidencia_path`,
  0 datos → no-op); (b) **tabla nueva** + RLS + policies + CREATE OR REPLACE de `registrar_evidencia_entrega` + el detalle
  devuelve el array. Recomiendo (b).

---

## ¿Una migración o varias?
Las 3 tocan la **misma superficie de detalle** del delivery. **Recomendado: UNA sola migración** que cierra las 3:
1. (3b) crea `entrega_evidencias` + RLS + policies; 2. CREATE OR REPLACE `registrar_evidencia_entrega` (INSERT por tipo);
3. crea `detalle_entrega_delivery` que devuelve **ítems (1) + `cobrado_at` (2) + evidencias (3)**.
Un cutover, una corrida de harness. **Alternativa si Oscar prefiere fasear:** mig-1 = `detalle_entrega_delivery` con
ítems + `cobrado_at` (decisiones 1+2, **RPC-only, sin DDL**, bajo riesgo) → mig-2 = evidencias (decisión 3, DDL). La
única es más limpia; la faseada aísla el DDL.

## Plan de verificación
- **Meds confinados:** otro delivery / admin / cross-empresa → `detalle_entrega_delivery` RAISE o 0 ítems; el delivery
  asignado ve solo SUS ítems. **Assert estructural:** `prosrc` del RPC **no** referencia `dosis/frecuencia/duracion/
  instrucciones`. **No** aparecen en monitoreo (probe: `listar_entregas_monitoreo` sin ítems).
- **Ítems = lo despachado:** sembrar una dispensación real → el detalle lista exactamente esos ítems+cantidades y
  **reconcilia con el monto** (`SUM(total_dispensado)`).
- **cobrado_at:** tras `registrar_cobro_entrega`, el detalle devuelve `cobrado_at` correcto; confinado.
- **Evidencias:** subir foto + firma por separado → 2 filas/2 campos; ambas legibles por signed URL (propio 200,
  cross-empresa 4xx); REVOKE directo efectivo; **0 backfill** (limpio).
- **No-regresión:** harness 141/143 verde; entrega 51 operable; la **PWA en prod** (que aún lee `evidencia_path` único)
  no rompe hasta el merge conjunto con la rama de pulido (que se actualizará para leer el array/2-campos + el detalle).

## Decisiones de Oscar pendientes
1. **Scope PII de meds:** (a) nombre+cantidad vs (a)+presentación [recomendado]. Nunca clínico.
2. **Fuente de ítems:** `dispensaciones.medicamentos_dispensados` [recomendado, reconcilia con monto] — confirmar.
3. **Carga:** detalle separado [recomendado] vs inline en la cola.
4. **Evidencias:** (a) 2 columnas vs (b) tabla `entrega_evidencias` [recomendado].
5. **Empaque:** una migración para las 3 [recomendado] vs faseada (RPC-only + DDL).
