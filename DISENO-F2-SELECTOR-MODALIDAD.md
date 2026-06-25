# DISEÑO — F2 · Selector de modalidad (pickup/delivery) — SOLO DOC

> F2 cablea UI sobre backend YA VIVO. **Nada de código/commit/deploy hasta OK paso a paso de Oscar.**
> Aplica el frontend-design skill = **calce visual EXACTO con cada superficie** (son dos estéticas distintas:
> RecetaModal usa marca `#1E5C8E` + shadcn `Card`; la WebApp del paciente usa paleta `slate` + `rounded-lg`).

## Backend (verificado en vivo, no se toca)
- **`fijar_modalidad_grupo(p_receta_id bigint, p_farmacia_id integer, p_modalidad text)`** — único RPC para ambos paths.
  Gate: médico de la receta **OR** `paciente_es_mio`. Uniformidad por grupo `(receta, farmacia)`. **Freeze server-side**:
  RAISE si el grupo ya despachó (alguna dispensación). La UI debe **reflejar** el freeze, no dejar tocar y comerse el error.
- Fuente del freeze en cliente: `receta_items.dispensado` (bool) — si algún ítem del grupo está `dispensado=true`,
  el grupo está en preparación/despachado.

## Parte MÉDICO — `src/components/consulta/RecetaModal.tsx`
Hoy: el médico agrega ítems y rutea cada uno a una sucursal (`seleccionarProveedor` → el ítem queda con `farmacia_id`);
`handleSubmit` → `createReceta(...)` que **retorna `data.id`** (la receta nueva) — confirmado en `useRecetas.ts:106`.

**Diseño:**
- Tras rutear, agrupar los ítems ruteados por `farmacia_id` y mostrar, **por grupo `(sucursal)`**, un control
  segmentado **Pickup / Delivery** (default **Pickup**). Es **pre-marca** del médico (sugerencia); el paciente la cambia después.
- **Timing:** el `receta_id` no existe hasta crear. → se guarda la elección en estado local keyed por `farmacia_id`
  (`Map<farmacia_id, 'pickup'|'delivery'>`). En `handleSubmit`, **después** de `createReceta` (con `data.id`), por cada
  grupo con modalidad elegida ≠ default llamar `fijar_modalidad_grupo(data.id, farmacia_id, modalidad)`.
  (Los ítems se crean con `modalidad='pickup'` por default del DB → solo hace falta el RPC para los grupos en `delivery`.)
- **Aditivo / no rompe emisión:** si el médico no toca el control, todo queda pickup; la receta se emite igual.
- **Estados:** control habilitado durante la edición; en submit, `loading/disabled` mientras los RPC están en vuelo;
  si un `fijar_modalidad_grupo` falla, **no bloquear** la emisión (la receta ya es válida) → toast warning
  "Receta creada; no se pudo fijar la modalidad de {sucursal}, el paciente puede ajustarla". Error de validación del
  server → toast claro.
- **Calce visual (skill):** mismo lenguaje que el modal — `#1E5C8E`/`#3A8ABF`, `Card`/`CardContent`, `Building2` para
  la sucursal, grises `#8a9aaa`. El segmentado pickup/delivery reusa el patrón de botones del modal (borde `#1E5C8E` +
  `bg-[#e8f0f8]` activo), íconos `Package`/`Truck`.

## Parte PACIENTE — `src/webapp/pages/WebAppRecetas.tsx` + `src/webapp/hooks/useWebAppRecetas.ts`
Hoy: el hook hace `select('*')` de `receta_items` pero **mapea solo campos clínicos** (`useWebAppRecetas.ts:55-63`) →
**NO expone `farmacia_id`, `modalidad`, `dispensado`**. El render lista los ítems planos, sin agrupar por farmacia.

**Cambios en el hook (`useWebAppRecetas`):**
- Agregar a `RecetaItemPaciente` (type) y al mapping: `farmacia_id`, `modalidad`, `dispensado`. (Ya vienen en `select('*')`.)
- Para el rótulo del grupo: traer el **nombre de la sucursal** por `farmacia_id` (fetch a `farmacias(id, nombre)` como ya
  se hace con los médicos), o exponer `farmacia_id` y resolver el nombre en la página. PII: solo la(s) farmacia(s) a las
  que la receta del propio paciente está ruteada — apropiado; no expone nada más de la farmacia.
- Exponer un `refetch`/optimismo para reflejar el cambio tras `fijar_modalidad_grupo`.

**Diseño UI (WebAppRecetas, dentro de la receta expandida):**
- Agrupar `r.items` por `farmacia_id`. Por grupo mostrar: nombre de sucursal + **modalidad actual** + toggle
  **Pickup ↔ Delivery**.
- **Freeze:** si **algún** ítem del grupo tiene `dispensado=true` → control **disabled** + leyenda
  "Ya en preparación/despachado, no se puede cambiar". (El server hace RAISE igual = red de seguridad.)
- Cambio → `fijar_modalidad_grupo(receta_id, farmacia_id, nueva)`; **última-escritura-gana** (el server resuelve).
- **Estados:** default (muestra modalidad actual); `loading/disabled` durante el RPC; `disabled-freeze` (leyenda);
  `error` → toast claro + revertir el optimismo.
- **Calce visual (skill):** lenguaje de la WebApp — `slate-*`, `rounded-lg`, `bg-slate-50`, ícono `Pill` ya presente;
  el toggle pickup/delivery como segmented control slate (activo `bg-white shadow` sobre `bg-slate-100`), íconos
  `Package`/`Truck`. NADA de `#1E5C8E` acá (esa es la marca del panel médico, no de la WebApp).

## Archivos que toca cada parte
| Parte | Archivos |
|---|---|
| Médico | `src/components/consulta/RecetaModal.tsx` (control por grupo + estado local + llamadas post-create); posible micro-componente `ModalidadToggle` reusable con prop de tema |
| Paciente | `src/webapp/hooks/useWebAppRecetas.ts` (exponer farmacia_id/modalidad/dispensado + nombre sucursal), `src/webapp/pages/WebAppRecetas.tsx` (agrupar por farmacia + control + freeze), `src/webapp/types/webapp.types.ts` (type del ítem) |

## Estados (resumen)
`default` (pickup pre-marca médico / modalidad actual paciente) · `loading/disabled` (RPC en vuelo) ·
`disabled-freeze` (grupo despachado, leyenda) · `error` (toast claro + revertir optimismo).

## Plan de verificación e2e (QA)
1. **Médico pre-marca delivery** en un grupo (sucursal) → emitir → los `receta_items` de ese grupo quedan `modalidad='delivery'`,
   uniformes por `(receta, farmacia)`; otros grupos pickup.
2. **Paciente cambia a pickup** ese grupo → `fijar_modalidad_grupo` → **última-escritura-gana** (queda pickup).
3. **Paciente intenta cambiar un grupo ya despachado** (sembrar una dispensación) → control **disabled** + leyenda;
   si se fuerza el RPC → **server RAISE** (red).
4. **Otro paciente** no puede tocar (gate `paciente_es_mio`) → ya cubierto server-side (sin UI que lo permita).
5. **No-regresión emisión:** médico emite SIN tocar el control → receta válida, todo pickup.

## Decisión para Oscar
- **¿El control del médico en RecetaModal es OPCIONAL (puede emitir sin tocarlo → pickup) o se le pide elegir por grupo?**
  **Recomiendo OPCIONAL con default pickup** (no agrega fricción a la emisión; el paciente decide después). Presentado, no cerrado.
