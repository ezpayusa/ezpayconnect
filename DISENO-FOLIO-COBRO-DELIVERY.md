# DISEÑO — Folio de entrega + Referencia de cobro (Track 2, SOLO DOC)

> Pulido visual con respaldo de datos: 2 detalles del mockup que **hoy NO existen en backend** (folio "GT-2049",
> ref de cobro "COB-7781"). **NADA se aplica sin OK paso a paso de Oscar.** No urgente, **no toca el path crítico**.
> Hechos en vivo: `configuracion_pais.codigo` (ej. 'GT') existe; país derivable vía `farmacias.pais_id`/`recetas.pais_id`;
> `entregas` **no** tiene columnas `folio`/`cobro_ref`. Una entrega = un cobro (1:1).

## A) Folio de entrega (tipo "GT-2049")
Hoy la entrega tiene `id` interno (IDENTITY global). El folio debe ser legible, **no el id crudo**.

### Opción A1 — DERIVADO al leer (recomendado: SIN DDL, sin contador)
- **`folio = {configuracion_pais.codigo}-{entrega_id}`** → ej. `GT-51`. País vía `farmacias.pais_id` (sucursal de la
  entrega) → `configuracion_pais.codigo`. Se **compone al LEER** en `listar_entregas_delivery` + `listar_entregas_monitoreo`
  (o el front lo arma con los campos ya devueltos).
- **Cero migración, cero contador, cero cambio** en el auto-create (C) ni en `crear_entrega`. **No** toca el path caliente
  del despacho ni el patrón best-effort.
- **Trade-off:** el número es el `id` **GLOBAL** (único, legible, buscable) → **no** es secuencial por-empresa (hay
  "saltos" entre empresas porque el id es compartido). Para un folio **operativo** (único + legible + referenciable en
  soporte) alcanza. El "2049" del mockup es solo un número de muestra.

### Opción A2 — REAL (columna + correlativo por empresa, no-gapless)
- `entregas.folio_num bigint` + contador por empresa (`private.empresa_folio_entregas(empresa_id, ultimo)` con
  `UPDATE … RETURNING` + lock de fila). Folio = `{codigo}-{folio_num:04d}` → `GT-2049` secuencial por empresa.
- **Se setea en AMBOS paths** (auto-create C **y** `crear_entrega`), **dentro del mismo INSERT** de la entrega (atómico,
  NO best-effort separado): si el bump+INSERT fallan, la entrega no se crea (rollback del savepoint best-effort de C) →
  **consistente** (reconciliable, nunca entrega-sin-folio). **No rompe** el `UNIQUE(receta_base_id, farmacia_id)`.
- **gapless: NO** (un folio de entrega no es talonario regulatorio como el correlativo médico) → contador simple
  no-gapless alcanza.
- **Costo:** +1 columna, +1 tabla contador, +UPDATE con lock en el path caliente del despacho, +cambios en 2 RPCs.

**Recomendación:** **A1 (derivado)** — cero DDL/riesgo. **A2** solo si Oscar quiere folios **secuenciales por empresa**.
- **Visible:** repartidor (cola/detalle, F1) + monitoreo (F3). **Interno**, no necesariamente al paciente.

## B) Referencia de cobro (tipo "COB-7781")
Una entrega = un cobro (`cobrado` bool) → la ref es **1:1 con la entrega**.

### Opción B1 — DERIVADO (recomendado: SIN DDL, sin contador)
- **`cobro_ref = COB-{entrega_id}`** (único, porque hay 1 cobro por entrega) — o `COB-{to_char(cobrado_at,'YYYYMMDD')}-{entrega_id}`
  si se quiere fecha. Se **compone al LEER** (en `listar_entregas_monitoreo` / detalle / un recibo). `registrar_cobro_entrega`
  **NO cambia** (ya setea `cobrado/at/por/metodo`; la ref se deriva del id que ya existe).
- Cero migración, cero contador.

### Opción B2 — REAL (columna + contador de cobro por empresa)
- `entregas.cobro_ref text` seteado **dentro de `registrar_cobro_entrega`** (atómico con el snapshot de cobro) desde un
  contador por empresa (`private.empresa_cobros(empresa_id, ultimo)`). Da `COB-7781` secuencial por empresa.
- **Costo:** +1 columna, +1 tabla contador, +cambio en `registrar_cobro_entrega`.

**Recomendación:** **B1 (derivado `COB-{entrega_id}`)** — el id de la entrega ES la referencia única del cobro; sin contador.

## Resumen: ¿migración o derivado?
| | Derivado (recomendado) | Real (correlativo) |
|---|---|---|
| **DDL** | NINGUNA | columna + tabla contador |
| **RPCs que cambian** | solo LECTURA (`listar_entregas_delivery`/`_monitoreo`) componen el string — o el **front** lo arma | ESCRITURA (auto-create C + `crear_entrega` + `registrar_cobro_entrega`) setean la columna + mantienen el contador |
| **Path caliente** | sin impacto | +UPDATE con lock por despacho/cobro |
| **Semántica** | número = id global (único, no per-empresa secuencial) | secuencial por empresa (no-gapless) |
| **Riesgo** | nulo | contador a mantener; cuidar atomicidad con el best-effort de C |

## Impacto en los RPCs (si derivado — recomendado)
- **A1/B1:** lo más barato es que **el front componga** `folio`/`cobro_ref` a partir de campos ya devueltos
  (`entrega_id` + país de la sucursal). Si se prefiere server-side, agregar 2 claves calculadas a `listar_entregas_delivery`
  / `listar_entregas_monitoreo` (`folio`, `cobro_ref`) — **CREATE OR REPLACE** de esos RPCs de lectura (sin DDL de tablas,
  sin tocar escritura/despacho). El país: JOIN `farmacias.pais_id → configuracion_pais.codigo`.

## Plan de verificación
- **Derivado:** unit del formato (`GT-{id}`, `COB-{id}`) + que el país resuelve (entrega sin país → fallback, p.ej. `XX-{id}`
  o el código de la empresa); que el folio/ref es **estable** (mismo id → mismo string) y **único**. Sin smoke de contador.
- **Real:** smoke del contador (concurrencia por empresa, ambos paths setean, no-gapless aceptado), no rompe `UNIQUE`,
  y el bump dentro del best-effort de C no deja entrega-sin-folio (rollback atómico del savepoint).

## Nota — pulido visual de F1 vs mockups
Acercar la UI de F1 a las **9 pantallas de Design** (tipografía, espaciado, badges, jerarquía) va **junto con esto**, como:
- (a) un **pase de pulido sobre F1** después del merge (F1 ya está en prod; el pase es aditivo, no rompe), o
- (b) **dentro de F2** aplicando el **frontend-design skill** para calzar con RecetaModal/WebAppRecetas y, de paso, F1.
El folio/ref son parte de ese pase (mostrar `GT-51` en vez del id crudo, `COB-51` en el recibo de cobro).

## Decisiones para Oscar
1. **Folio:** A1 derivado `{codigo}-{id}` [recomendado] vs A2 real per-empresa secuencial. Y dónde se compone (front vs RPC de lectura).
2. **Ref de cobro:** B1 derivado `COB-{id}` [recomendado] vs B2 real con contador.
3. **Pulido visual F1:** pase aparte post-merge vs dentro de F2.
