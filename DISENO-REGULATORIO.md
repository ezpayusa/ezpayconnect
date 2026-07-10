# DISEÑO — Work item REGULATORIO: registro médico→medicamento + clasificación de controlados + correlativo por médico

> Doc de diseño para revisión a fondo con Oscar. **NO es migración.** Nada aplicado, nada commiteado.
> Separado de la Fase 1 del delivery. Dos partes relacionadas; **comparten el punto de emisión de receta**.
> Convenciones del spine: RPCs DEFINER `search_path=''` schema-qualified; escritura sensible solo por RPC;
> gate-antes-de-efecto (l.54); RPC-vivo grandfather-inerte (l.51); validación en PREVIEW antes de main (l.25).

---

## ⭐ 12. SOLAPAMIENTO A↔B — `emitir_receta` es el punto común

Hoy la receta se emite con **insert directo del cliente** ([useRecetas.ts:63-95](src/hooks/useRecetas.ts#L63-L95)): insert `recetas` → insert `receta_items` → `notificar_receta` (best-effort) → `delete` manual si fallan los items. Sin transacción, sin validación server-side, y `medicamento_id` hoy se inserta como `i.medicamento_id || null` (permite NULL).

**Ambas partes exigen el mismo cambio → un único RPC `emitir_receta`:**
- **Parte A** necesita `medicamento_id` obligatorio **server-side** (para que el reporte clasifique por id).
- **Parte B** necesita asignar el **correlativo gapless atómico**.

→ `emitir_receta` se diseña **una sola vez**, sirve a las dos, y es la **primera ola** (habilita A2 y todo B). El resto de cada parte es independiente.

═══════════════════════════════════════════════════════════════
# PARTE A — REGISTRO REGULATORIO (médico → medicamento despachado)
═══════════════════════════════════════════════════════════════

Base ya existente (NO reconstruir): `dispensaciones` (append-only) captura por ítem `medico_id`, `paciente_id`, `farmacia_id`, `fecha_dispensacion`, `despachado_por`, `farmaceutico_nombre`, `medicamentos_dispensados` jsonb `[{item_id,nombre,cantidad}]`, `total_dispensado`. `medicos.cedula_profesional` existe. Catálogo `medicamentos` es **global** (sin `empresa_id`).

## A1 · DDL `categoria_regulatoria`

**Tipo: `text` + CHECK (extensible), NO `CREATE TYPE` nativo** — el enum nativo exige `ALTER TYPE` para crecer (no revertible fácil); `text+CHECK` se ajusta con drop/add constraint y es el patrón del repo (estados de receta/dispensación/entrega).
```sql
ALTER TABLE public.medicamentos ADD COLUMN categoria_regulatoria text;     -- NULL = sin_clasificar
ALTER TABLE public.medicamentos ADD CONSTRAINT chk_categoria_regulatoria
  CHECK (categoria_regulatoria IS NULL OR categoria_regulatoria IN
    ('venta_libre','receta_simple','psicotropico','estupefaciente','recetario_especial'));
```
**Default recomendado: `NULL` = sin_clasificar, NO `'venta_libre'`.** `'venta_libre'` por default **afirmaría** que todo el catálogo es venta libre (falso y peligroso: un controlado sin tocar aparecería como venta_libre en el desglose). `NULL` es **fail-safe**: "solo controlados" nunca incluye un NULL; un dashboard puede mostrar "N medicamentos sin clasificar" como deuda. "Todos" incluye NULL.

⚠️ **[CERRADO A1]** text+CHECK extensible con los **5 valores TENTATIVOS** de arriba, marcados **«pendiente validación MSPAS»**. Oscar valida/ajusta contra la norma GT (listas de estupefacientes/psicotrópicos) **antes del apply de O2**.

**[CERRADO A2-clasif] Población del catálogo:** **UI nueva para super_admin de plataforma** — marcar categoría **por medicamento** + **carga CSV masiva**. **NO seed por migración.** (El catálogo es global → lo clasifica la plataforma, no la farmacia.) Hasta que se clasifique, NULL=sin_clasificar es seguro.

## A2 · Obligar `medicamento_id` (server-side) + fallback histórico

- **De aquí en adelante (duro):** la validación vive en **`emitir_receta`** (Parte B / §8) — RAISE si algún ítem trae `medicamento_id` NULL. No solo UI.
- **Histórico (best-effort, solo filas viejas sin id):** fallback por nombre. **Algoritmo de match:**
  1. normalizar `receta_items.nombre_medicamento` (o el `nombre` del jsonb): `lower(trim(unaccent(...)))`, colapsar espacios (reusar la normalización del catálogo Inc.5 si aplica).
  2. match exacto normalizado contra `medicamentos.nombre_generico`; si no, contra `nombre_comercial`.
  3. si 0 o >1 match → **sin clasificar** (no adivinar).
  - El reporte marca cada fila con **origen de clasificación**: `'id'` (duro) vs `'nombre'` (inferido, baja confianza) vs `'sin_clasificar'`. Nunca mezclar id e inferido como equivalentes.

## A3 · RPC reporte nominal
```sql
registro_regulatorio_despachos(
  p_desde date, p_hasta date,
  p_categoria text DEFAULT NULL,     -- NULL=todos | 'controlados'=(psico+estupef+recetario) | valor exacto
  p_sucursal_id int DEFAULT NULL     -- NULL=todas las visibles
) RETURNS TABLE(
  fecha_dispensacion timestamptz, sucursal_id int, sucursal_nombre text,
  medico_nombre text, medico_cedula_profesional text,
  paciente_dpi text, paciente_nombre text, paciente_fecha_nacimiento date,  -- [CERRADO A5] DPI si poblado; fallback nombre+fecha_nac marcado "sin DPI" (ver §A7)
  medicamento text, categoria_regulatoria text, origen_clasificacion text,
  cantidad int, despachado_por uuid, farmaceutico_nombre text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
```
- **Gate:** `private.tiene_permiso('registro_regulatorio')` (permiso NUEVO, §A4). **NOMINAL, NO k-anónimo.**
- **Confinamiento:** `empresa_id = mi_empresa_proveedor()` **AND** `COALESCE(private.sucursal_visible(farmacia_id), false)` → admin-farmacia ve todas sus sucursales; gerente la suya. (Necesariamente DEFINER: la farmacia **no** tiene RLS de SELECT sobre `dispensaciones`.)
- **Join:** `dispensaciones` → `jsonb_array_elements(medicamentos_dispensados)` → `item_id` → `receta_items.medicamento_id` → `medicamentos.categoria_regulatoria` (duro); fallback nombre (A2) si id NULL. Médico vía `dispensaciones.medico_id → medicos` (nombre + cedula_profesional).
- **Filtros:** `p_categoria='controlados'` → `WHERE categoria IN ('psicotropico','estupefaciente','recetario_especial')`; valor exacto → ese; NULL → todos. `p_sucursal_id` acota (siempre dentro de lo visible).

## A4 · Permiso `registro_regulatorio`
- Fila nueva en `permisos_empresa_rol` (catálogo, `tipo_empresa='farmacia'`).
- **Roles default:** `admin` (todas sus sucursales) + `gerente_farmacia` (su sucursal, vía sucursal_visible). **NO** cajero/dependiente/delivery/inventario.
- **[CERRADO A3] Techo 117 (agregar a `acciones_techo`):** PII regulatoria **no-delegable** — un admin de empresa NO puede concederla vía override a roles no autorizados. `tiene_permiso` ignora el override → set fijo {admin, gerente_farmacia}.

## A5 · Export con auditoría obligatoria
- **Tabla append-only:**
```sql
CREATE TABLE public.registro_regulatorio_export_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  exportado_por uuid NOT NULL, empresa_id uuid NOT NULL, exported_at timestamptz NOT NULL DEFAULT now(),
  p_desde date, p_hasta date, categoria_filtro text, sucursal_id int, formato text, filas_exportadas int);
-- RLS: SELECT solo su empresa (+super_admin); sin write directo (solo el RPC).
```
- **Generación:** el export pasa por un RPC **`exportar_registro_regulatorio(mismos params + p_formato)`** que en una transacción **(1) inserta el log** y **(2) devuelve las filas** → el log **no se puede saltar**. El formateo CSV/PDF final es client-side (o un edge si se quiere PDF server-side; el log igual queda en el RPC).
- **[CERRADO A4] Minimización:** export **default SOLO-CONTROLADOS**. Exportar **todo** = acción **deliberada explícita** (param/confirmación dedicada) **+ logueada como tal** (el log marca si fue export completo). No es el camino por defecto.
- El export **sale del perímetro RLS** → por eso log obligatorio + gate `registro_regulatorio` estrecho (§A4).

## A6 · Inmutabilidad dura de `dispensaciones`
```sql
REVOKE TRUNCATE ON public.dispensaciones FROM authenticated;   -- TRUNCATE ignora RLS → quitarlo
CREATE FUNCTION private.dispensaciones_append_only() RETURNS trigger
  LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'dispensaciones es append-only (registro regulatorio): % denegado', TG_OP; END $$;
CREATE TRIGGER trg_dispensaciones_inmutable
  BEFORE UPDATE OR DELETE ON public.dispensaciones
  FOR EACH ROW EXECUTE FUNCTION private.dispensaciones_append_only();
```
- **Verificación de no-regresión:** `registrar_dispensacion` / `registrar_dispensacion_dirigida` **solo hacen INSERT** en dispensaciones (confirmado en el recon: el loop arma un `INSERT ... VALUES`, `estado_dispensacion` se fija en el INSERT, no hay UPDATE posterior). El trigger es **BEFORE UPDATE/DELETE** → **no toca INSERT** → la inserción sigue intacta.
- Hace la inmutabilidad **regla explícita** (no por ausencia de grant): ni super_admin (policy `disp_superadmin_all`) ni el owner pueden UPDATE/DELETE.
- Si en el futuro hace falta "anular una dispensación", será un **INSERT de contra-asiento**, nunca UPDATE/DELETE.

## A7 · DPI del paciente (identificador del registro)
```sql
ALTER TABLE public.pacientes ADD COLUMN dpi text;   -- nullable; sin exigencia retroactiva
```
- **Entidad compartida (no del panel farmacia):** `pacientes` la usan varios paneles → la columna es transversal, **nullable** (los pacientes existentes no lo tienen y no se exige retroactivo).
- **[CERRADO A5] Uso en el reporte:** el registro regulatorio muestra **`dpi` cuando esté poblado**; **fallback** a `nombre completo + fecha_nacimiento` mientras `dpi` sea NULL, marcado **«sin DPI»**. El RPC `registro_regulatorio_despachos` devuelve `paciente_dpi` (NULL si falta) + `paciente_nombre` + `paciente_fecha_nacimiento`; la UI/columna del reporte resuelve la preferencia.
- **Propósito:** el DPI **desambigua homónimos** en el registro de prescripción de medicina regulada — `fecha_nacimiento` sola **no garantiza unicidad** (dos pacientes pueden compartir nombre+fecha). El DPI es la clave fuerte exigible por la autoridad.
- **⚠️ CAPTURA = dependencia de la fase CLÍNICA (NO este work item):** la **columna se crea ahora** (la consume el registro regulatorio); la **UI de captura** del DPI es de la fase Clínica — en el panel **asistente-médico/secretaría** al registrar la cita. El rol **`asistente-médico`** (permiso de escribir **signos vitales** en el expediente, **NO** contenido clínico del médico) es también de la fase Clínica y es **donde naturalmente se captura el DPI**. Hasta que esa UI exista, `dpi` queda NULL y el reporte usa el fallback. → este work item **no** construye la captura; solo deja la columna lista.

═══════════════════════════════════════════════════════════════
# PARTE B — CORRELATIVO POR MÉDICO (recetario, semántica talonario)
═══════════════════════════════════════════════════════════════

## B7 · DDL contador + columna
```sql
CREATE TABLE public.medico_correlativos (
  medico_id uuid PRIMARY KEY,                       -- = recetas.medico_id (auth uid del médico)
  ultimo_numero bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.medico_correlativos ENABLE ROW LEVEL SECURITY;   -- sin write directo; lectura propia/super_admin
ALTER TABLE public.recetas ADD COLUMN numero_correlativo bigint;    -- NULL para las 16 históricas; lo setea emitir_receta
CREATE UNIQUE INDEX uq_recetas_corr_medico ON public.recetas (medico_id, numero_correlativo)
  WHERE numero_correlativo IS NOT NULL;             -- unicidad por médico; NULLs históricos no chocan
```
- `numero_correlativo` queda **nullable** (no se puede NOT NULL con 16 filas viejas) — la **obligatoriedad para nuevas** la garantiza `emitir_receta` (siempre lo asigna). Las 16 históricas se ven como **pre-numeración** (B-decisión: no retroactivo).
- **Número formateado: se compone al LEER, NO se persiste.** Es derivable de `cedula_profesional` + `numero_correlativo` + `created_at`; persistirlo duplica y deriva si cambia la cédula. Formato **[CERRADO B1]**:
  **`{cedula_profesional}-{numero_correlativo:06d}-{YYYYMMDD}`** → ej. `12345-000042-20260624`. El `bigint` crudo ordena y garantiza gapless; el formateado es solo presentación (lo arma el RPC `recetario_medico` / la UI).

## B8 · RPC `emitir_receta` (atómico)
```sql
emitir_receta(
  p_paciente_id bigint,
  p_instrucciones_generales text,
  p_items jsonb               -- [{medicamento_id, nombre_medicamento, dosis, frecuencia, duracion,
                              --   instrucciones, cantidad, farmacia_id, precio_unitario, stock_actual}, ...]
) RETURNS jsonb               -- { receta_id, numero_correlativo, numero_formateado }
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
```
**Orden de operaciones (todo en UNA transacción del RPC):**
1. **Gate + pre-validación (antes de consumir número):** `auth.uid()` es médico (perfiles.rol='medico'); `p_paciente_id` válido; `p_items` no vacío; **cada ítem: `medicamento_id` NOT NULL** (A2) + `dosis` + `frecuencia`. Fallo aquí → RAISE → **nada se consume, nada se inserta**.
2. **Bump contador (gapless):**
   ```sql
   UPDATE public.medico_correlativos SET ultimo_numero=ultimo_numero+1, updated_at=now()
     WHERE medico_id=auth.uid() RETURNING ultimo_numero INTO v_num;   -- lock de fila → serializa al MISMO médico
   IF NOT FOUND THEN INSERT INTO public.medico_correlativos(medico_id,ultimo_numero) VALUES (auth.uid(),1) RETURNING ultimo_numero INTO v_num; END IF;
   ```
3. **Insert `recetas`** (réplica EXACTA de los campos actuales: `paciente_id`, `instrucciones_generales`, `medico_id=auth.uid()`, `estado='activa'`, `pais_id`= país del médico, **`numero_correlativo=v_num`**) → `v_receta_id`.
4. **Insert `receta_items`** (los 10 campos actuales) desde `p_items`. **[Dependencia DELIVERY Ola A]** si ya existe `receta_items.modalidad`, `emitir_receta` debe incluirla en el insert (default `'pickup'` si `p_items` no la trae); la pre-marca real del médico se hace tras rutear vía `fijar_modalidad_grupo`. Ver DISENO-DELIVERY-FASE1 §9.5.
5. RETURN `{receta_id, numero_correlativo, numero_formateado}`.

**Manejo de fallo (resuelve "rollback vs anulada"):**
- **Fallo DENTRO de `emitir_receta`** (validación, constraint, error DB) → **ROLLBACK total** de la transacción → el bump del contador se revierte → **el número NO se consume** (no hay hueco; el siguiente emit reusa el número). El delete-manual actual desaparece.
- **`anulada` NO es para fallos de emisión** — es para una receta **ya emitida** que luego se invalida (médico la cancela / se reemplaza). Eso es una acción separada (`anular_receta`, §B9): el número **queda consumido**, `estado='anulada'`, sin borrar. → Talonario: una hoja que nunca se escribió no se consume (rollback); una hoja escrita y anulada conserva su número (anulada). **Gapless en ambos casos.**

**Qué pasa con lo existente:**
- **`trg_historial_receta`** (AFTER INSERT en recetas) → **sigue disparando dentro** del insert del paso 3 (automático, sin cambios). Su fallo abortaría la txn (es un insert simple a `historial_medico`, bajo riesgo).
- **`notificar_receta`** → **FUERA del RPC** (best-effort, como hoy). El front lo llama después de que `emitir_receta` retorna OK. Razón: una falla de notificación **no debe** anular/rollback una receta válida. Se mantiene el `try/catch` no-bloqueante actual.
- **Front (`useRecetas.createReceta`)** → pasa a `supabase.rpc('emitir_receta', {p_paciente_id, p_instrucciones_generales, p_items})` en vez de los 2 inserts + delete; luego `notificar_receta` best-effort; luego actualiza el estado local con `{receta_id, numero_formateado}`.
- **`recetas_avanzadas`/`dispatch_token`** → **NO** se tocan aquí (se generan aparte al producir el PDF, confirmado en useRecetas:61). `emitir_receta` no los crea.

## B9 · Semántica `anulada`
- `recetas.estado` es texto libre (hoy `'activa'`). Se reconoce un nuevo valor **`'anulada'`**.
- **[CERRADO B3] Cuándo:** RPC `anular_receta(p_receta_id, p_motivo)` — **`p_motivo` OBLIGATORIO** (RAISE si vacío). Gate `recetas.medico_id=auth.uid()` (su receta) o super_admin **Y ventana = SOLO antes del despacho**: si existe **cualquier** dispensación ligada (recetas_avanzadas→dispensaciones de esa receta), **NO anulable** → solo queda **constancia** (no cambia estado). Sin dispensación → marca `estado='anulada'` + motivo/fecha. **Nunca borra**; `numero_correlativo` permanece (gapless).
- **En el recetario:** aparece como **entrada anulada** (número consumido, tachado/etiqueta), preservando la secuencia sin hueco.

## B10 · RPC `recetario_medico`
```sql
recetario_medico(p_medico_id uuid DEFAULT NULL, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)
  RETURNS TABLE(numero_correlativo bigint, numero_formateado text, fecha timestamptz,
                paciente_nombre text, estado text)   -- lista: sin diagnóstico (minimización, §B11)
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
  Gate:  private.tiene_rol(ARRAY['super_admin'])                       -- plataforma: TODOS (p_medico_id filtra/null=todos)
      OR (recetas.medico_id = auth.uid())                              -- médico: SOLO el suyo (ignora p_medico_id≠self)
  Orden: ORDER BY medico_id, numero_correlativo                        -- secuencia del talonario
```
- **NO** el admin-farmacia (no es médico ni super_admin; ni tiene SELECT sobre recetas). El médico ya tiene "mis recetas" ([useRecetas.ts:112](src/hooks/useRecetas.ts#L112)); el recetario lo extiende con `numero_*` + estado. La vista super_admin es nueva, **consolidada cross-médico**.

## B11 · Gobernanza super_admin [CERRADO B2]
- **Vista consolidada = METADATA por defecto:** `correlativo + fecha + médico + paciente + estado`, **SIN diagnóstico**.
- **Diagnóstico completo** detrás de acción explícita **«ver detalle»** → **también se loguea**.
- **Log de acceso OBLIGATORIO en AMBOS niveles** (lista consolidada y ver-detalle): quién super_admin, qué médico/receta/rango, cuándo → tabla nueva `recetario_acceso_log` (análoga a `registro_regulatorio_export_log` de A5).
- Inmutabilidad del correlativo: asignado no se reasigna/edita (talonario).

═══════════════════════════════════════════════════════════════
# 13. PLAN DE OLAS (no-regresivo)
═══════════════════════════════════════════════════════════════

| Ola | Parte | Contenido | Nota |
|---|---|---|---|
| **O1** | A+B (común) | `medico_correlativos` + `recetas.numero_correlativo` + `recetas.estado='anulada'` reconocido + **RPC `emitir_receta` atómico** (bump+receta+items, valida medicamento_id) + **cutover del front** (useRecetas → RPC) | **camino crítico** — §14 |
| **O2** | A | `categoria_regulatoria` (columna+CHECK, default NULL) + UI/seed de clasificación (super_admin) | inerte (NULL); independiente de O1 salvo que el reporte (O4) la usa |
| **O3** | A | inmutabilidad dura dispensaciones (REVOKE TRUNCATE + trigger append-only) | ortogonal; aplicable cuando Oscar diga |
| **O4** | A | **`pacientes.dpi` (col nullable, §A7)** + permiso `registro_regulatorio` (+ techo 117) + RPC `registro_regulatorio_despachos` + fallback por nombre/DPI | depende de O2; el reporte es el único consumidor del DPI hoy |
| **O5** | A | `registro_regulatorio_export_log` + RPC `exportar_registro_regulatorio` auditado | depende de O4 |
| **O6** | B | RPC `recetario_medico` + `anular_receta` + UI (médico + super_admin) + log de acceso | depende de O1 |

- **O1 es la piedra angular** (habilita A2 + todo B). **O2/O3** pueden ir en paralelo a O1 (no tocan emisión). **O3** sirve como hardening temprano si se quiere.
- UI por ola la marca el front (no en estas migraciones).

═══════════════════════════════════════════════════════════════
# 14. RIESGO Y PLAN DE VERIFICACIÓN — cutover de `emitir_receta` (O1)
═══════════════════════════════════════════════════════════════

**Por qué es delicado:** es el **camino crítico de emisión** (16 recetas reales + producción). El front cambia de insert directo a RPC; hay que preservar `notificar_receta`, `trg_historial_receta`, el flujo de items, `estado='activa'`, `pais_id`.

**[CERRADO C1] Estrategia front = FEATURE-FLAG (no swap directo):** `createReceta` decide por flag entre el insert directo actual y `emitir_receta`. Activar el flag → verificar en prod con una receta real → si falla, **apagar el flag sin redeploy** (vuelve al insert directo). **Este flag ES el backout del paso 6.**

**[CERRADO C2] Censo de escritores de `recetas` (hecho en este recon):** el ÚNICO escritor es `useRecetas` — `useRecetas.ts:63` (insert/emisión → pasa a `emitir_receta`), `:89` (delete de compensación → desaparece con el RPC), `:192` (update/edición — path aparte, no crea ni renumera). **Ningún edge ni RPC/migración server-side inserta en `recetas`.** → el feature-flag sobre `createReceta` cubre el 100% del path de emisión; no hay otro caller que rompa el gapless. (Re-verificar el censo en build inmediatamente antes del cutover por si entró código nuevo.)

**Plan de verificación (espejo del protocolo del spine):**
1. **Build + dry-run del RPC** con harness (txn BEGIN…ROLLBACK), probes nuevos:
   - emit normal → receta+items insertados, `numero_correlativo` asignado, `numero_formateado` correcto.
   - **gapless bajo carrera** (simular 2 emits del mismo médico) → números consecutivos, sin colisión (el lock de fila serializa).
   - **rollback en fallo** → ítem sin `medicamento_id` → RAISE, **contador NO avanza**, 0 filas.
   - médicos distintos → contadores independientes, no se bloquean.
   - `trg_historial_receta` sigue escribiendo `historial_medico`.
2. **Réplica de campos:** verificar que el RPC inserta EXACTAMENTE los campos del insert actual (recetas: paciente_id, instrucciones_generales, medico_id, estado, pais_id; items: los 10).
3. **Front en PREVIEW (rama, no main — l.25):** `createReceta` → RPC; `notificar_receta` después (best-effort); estado local con `numero_formateado`. Validar emisión e2e en preview con cuenta médico QA.
4. **No-regresión:** las 16 recetas viejas intactas (`numero_correlativo` NULL, mostradas como pre-numeración); el QR/`dispatch_token` del PDF sigue generándose aparte; `fetchRecetas` y `getRecetaCompleta` sin cambios.
5. **Cutover:** desplegar RPC (dormant, nadie lo llama aún) → cambiar el front en preview → validación de Oscar → merge a main → smoke en vivo (emitir una receta QA, verificar correlativo + historial + notificación + limpieza del artefacto QA).
6. **Backout:** si algo falla post-merge, el front puede volver al insert directo (el RPC queda inerte); el contador no se corrompe (gapless por transacción).

═══════════════════════════════════════════════════════════════
# DECISIONES CERRADAS (Oscar, 2026-06-24)
═══════════════════════════════════════════════════════════════
**Parte A:**
- **A1** — enum `text+CHECK` extensible, 5 valores **TENTATIVOS**, «pendiente validación MSPAS» → Oscar valida vs norma GT **antes del apply de O2**. Default `NULL=sin_clasificar`.
- **A2 (clasif.)** — clasificación por **UI super_admin (por medicamento) + carga CSV masiva**. **NO seed por migración.**
- **A3 (permiso)** — `registro_regulatorio` en **techo 117** (no-delegable); default {admin, gerente_farmacia}.
- **A4 (export)** — default **SOLO-CONTROLADOS**; exportar todo = acción deliberada explícita + logueada.
- **A5 (paciente)** — se **agrega `pacientes.dpi` (text nullable, §A7)**. Reporte muestra **DPI si poblado**; **fallback** a nombre completo + `fecha_nacimiento` (marcado «sin DPI») mientras sea NULL. Propósito: desambiguar homónimos (fecha_nac sola no es única). **Captura del DPI = fase Clínica** (UI asistente-médico/secretaría al registrar la cita) — **NO** este work item; la columna se crea ahora (la consume el reporte), va en **O4**.

**Parte B:**
- **B1 (folio)** — `{cedula}-{correlativo:06d}-{YYYYMMDD}` **CONFIRMADO** (crudo bigint persistido; formateado al leer).
- **B2 (gobernanza)** — consolidada = **metadata** por defecto; diagnóstico tras «ver detalle» **logueado**; **log de acceso obligatorio en ambos niveles** (`recetario_acceso_log`).
- **B3 (anular)** — `p_motivo` **obligatorio** + ventana **solo antes del despacho** (con dispensación ligada → no anulable, solo constancia); gate en el RPC.

**Cutover O1:**
- **C1** — front por **feature-flag** (no swap); apagable sin redeploy = backout.
- **C2** — censo hecho: **único escritor de `recetas` = `useRecetas`**; sin edges/RPCs server-side. El flag cubre todo el path. Re-verificar en build pre-cutover.

═══════════════════════════════════════════════════════════════
# ADDENDUM — Recon catálogos + acuse del médico (área O2 / emisión, 2026-06-24)
═══════════════════════════════════════════════════════════════
> Recon en vivo. **Reportado contra hallazgos, no contra suposiciones.** Opciones enumeradas; Oscar decide en revisión. Nada toca prod.

## 1 · Carga de catálogo FARMACIA (inventario por sucursal → `farmacia_medicamentos`)
- **Cómo agrega hoy:** DOS vías — **importación masiva Excel/CSV** ([ImportarCatalogoModal.tsx](src/farmacia/pages/ImportarCatalogoModal.tsx), `XLSX` + `.csv`, plantilla descargable) **y alta manual** ([FarmaciaInventarioPage.tsx:81](src/farmacia/pages/FarmaciaInventarioPage.tsx#L81), [FarmaciasPage.tsx:175](src/pages/FarmaciasPage.tsx#L175)).
- **Único escritor (masivo):** RPC **`cargar_catalogo_farmacia`** (de-dup autoritativo por `private.norm_med_nombre`, anti-drift). Manual: `insert/update` directos a `farmacia_medicamentos`.
- **Columnas que captura:** `nombre_medicamento` (req), `presentacion`, `descripcion`, `laboratorio`, `stock_actual`, `stock_minimo`, `precio_unitario`, `fecha_vencimiento`, `activo`. **NO existe campo regulado/categoría** (confirmado en vivo).
- **⭐ CLAVE:** la farmacia **teclea nombre + precio LIBRES** — `farmacia_medicamentos` **NO referencia `medicamento_id` del catálogo global**. → `categoria_regulatoria` (O2) **NO la hereda ni la puede tocar la farmacia**; vive **solo en el global `medicamentos`** y se consume en la **prescripción** (no en el inventario de la farmacia). El inventario es surtido/precio, no fuente regulatoria.

## 2 · Carga de catálogo LABORATORIO FARMACÉUTICO (proveedor al que el médico refiere)
> **Corrección:** «laboratorio» aquí = **laboratorio FARMACÉUTICO** (empresa `tipo='laboratorio_farmaceutico'`), al que el médico **refiere** desde RecetaModal junto a la farmacia. (Mi recon previo apuntó por error al laboratorio **clínico** = `examenes_catalogo` — otra entidad, fuera de alcance.)
- **Modelo (IGUAL que la farmacia):** el lab farmacéutico se modela como filas de **`farmacias` con `tipo='laboratorio'`** (3 puntos) y su catálogo vive en **`farmacia_medicamentos`** (38 ítems hoy) — **misma tabla que las farmacias**. `empresas_proveedoras.tipo='laboratorio_farmaceutico'` ↔ sus `farmacias.tipo='laboratorio'`.
- **El médico lo refiere desde `farmacia_medicamentos`:** «Laboratorios» en RecetaModal ([abrirModalLaboratorio:130](src/components/consulta/RecetaModal.tsx#L130), [renderResultadosBusqueda:162](src/components/consulta/RecetaModal.tsx#L162)) usa el **mismo `buscar`** que farmacia y filtra `resultadosBusqueda` por **`farmacias.tipo='laboratorio'`**. → el surtido que ve el médico para un lab es `farmacia_medicamentos`, NO `productos_empresa`.
- **⚠️ GAP (tu observación):** hoy el lab farmacéutico **NO tiene la función de carga de catálogo**. **`FarmaciaPrivateRoute:23` bloquea** todo `empresa.tipo !== 'farmacia'` → el lab **no entra a /farmacia/\*** (donde viven `FarmaciaInventarioPage` + `ImportarCatalogoModal`/Excel). El lab está en el panel **proveedor**, cuyo import ([ImportarProductosModal](src/proveedor/pages/productos/ImportarProductosModal.tsx)) escribe **`productos_empresa`** — **otra tabla, desconectada de lo que el médico refiere** (`farmacia_medicamentos`). Por eso los 38 ítems lab existentes no son auto-gestionables por el lab (seed/admin).
- **El BACKEND ya lo soporta:** el RPC **`cargar_catalogo_farmacia` es tipo-agnóstico** — gatea por `tiene_permiso('inventario_editar')` + que la farmacia pertenezca a `mi_empresa_proveedor()`; **NO** exige `tipo='farmacia'`. → serviría a las `farmacias.tipo='laboratorio'` del lab si el lab pudiera alcanzarlo. **El bloqueo es solo de front** (ruta + ubicación del modal).
- **[CERRADO D-CAT-1] Dar al laboratorio farmacéutico la carga (Excel) escribiendo a `farmacia_medicamentos`:** montar una **página NUEVA de inventario + import Excel en el panel PROVEEDOR** para `tipo='laboratorio_farmaceutico'`, que llame al RPC existente **`cargar_catalogo_farmacia`** (ya tipo-agnóstico). **NO relajar `FarmaciaPrivateRoute`** (paneles separados). Gating por `inventario_editar` + `sucursal_visible`, idéntico a farmacia.
  - **GAP de origen a corregir:** el import actual del panel proveedor ([ImportarProductosModal](src/proveedor/pages/productos/ImportarProductosModal.tsx)) escribe **`productos_empresa`** — tabla **desconectada de lo que el médico refiere** (`farmacia_medicamentos`). La página NUEVA debe apuntar a **`farmacia_medicamentos`**, no reusar ese import.
  - **Registro:** **dependencia de producto del panel farmacia/proveedor, NO bloqueante** del work item regulatorio (la clasificación es independiente del surtido — §4/§5). Verificar en build que ningún punto asuma `tipo='farmacia'` duro en esa ruta.
- **Implicación REGULATORIA: el gap de carga del lab NO toca la clasificación.** `farmacia_medicamentos` y `productos_empresa` son **surtido free-text** que **NO portan `categoria` ni `medicamento_id`** (verificado §4: `farmacia_medicamentos` no tiene la columna). El `medicamento_id` lo aporta **solo** `handleAddMedicamento` (global), nunca el ruteo a farmacia/lab. → cerrar el gap de carga del lab es **operativo, sin acoplamiento regulatorio**; queda como **dependencia de producto del panel farmacia/proveedor**, no bloquea O2. **⚠️ Pero «todo ítem nace del global con medicamento_id» es matizado: cierto para el path ACTUAL, FALSO para el histórico (2/17 NULL) → ver §4.**
- **Catálogo GLOBAL `medicamentos`** (fuente de prescripción + hogar de `categoria_regulatoria`): lo **siembra solo `001_inicial.sql`**; ningún front/edge lo escribe → lo clasifica **únicamente la UI super_admin** (A2). **No hay flujo Excel existente que tocar** para "regulado".
- **[CERRADO D-CAT-2, ver §5]** la columna `regulado` del Excel del lab es **ADVISORY** (pista visible en el import, NO setea ni propaga la categoría autoritativa, que vive solo en el global, write super_admin). Fail-safe `NULL`, nunca venta_libre.

## 3 · Gate de ACUSE del médico (regulado → iniciales)
- **Dónde selecciona:** `handleAddMedicamento(med)` ([RecetaModal.tsx:100](src/components/consulta/RecetaModal.tsx#L100)) — `med` es una fila del **catálogo global** (`useMedicamentos` = `supabase.from('medicamentos').select('*')`, [useRecetas.ts:212](src/hooks/useRecetas.ts#L212)). El ítem nace con **`medicamento_id: med.id`** + nombre; el ruteo a farmacia ([RecetaModal.tsx:138](src/components/consulta/RecetaModal.tsx#L138)) solo **agrega `farmacia_id`/precio** (preserva el id).
- **⭐ `categoria_regulatoria` ya estará disponible** en `med` sin tocar la query (`select('*')` la trae al agregar O2) → el gate se lee **en el punto de selección**, sin refactor.
- **Dónde vive el gate:** en `handleAddMedicamento`, **antes** de `setItems([...items, nuevoItem])`: si `med.categoria_regulatoria` ∈ {psicotropico, estupefaciente, recetario_especial} → exigir **iniciales del médico** como acuse deliberado antes de agregar el ítem.
- **Nota A2 (corregida por §4):** `medicamento_id` está presente en **todo ítem agregado por el path ACTUAL** (`handleAddMedicamento` es el **único** alta en RecetaModal; no hay alta libre). PERO la **data histórica tiene 2/17 con NULL** (legacy, pre-columna). → obligarlo en `emitir_receta` (A2/O1) es **consistente con la UX actual y no la rompe** (red de seguridad server-side); el **fallback por nombre (§A2) es necesario para el histórico** y para el reporte (A3). El **acuse** (al seleccionar) sí es robusto: todo ítem NUEVO trae el `med` del global → `categoria_regulatoria` disponible en la selección.
- **[CERRADO D-ACUSE] Acuse PERSISTIDO server-side dentro de `emitir_receta` (O1), auditable.** Descartado el solo-UI efímero (cosmético, no deja evidencia, evadible desde el cliente). El gate de UI vive en `handleAddMedicamento` antes de `setItems` (la `categoria_regulatoria` del global ya está disponible al agregar tras O2, **sin refactor de la selección**); pero la **constancia se persiste y se valida en el servidor**.
- **Las DOS opciones de persistencia (Oscar elige al revisar O1):**
  - **(b1) Campo en `receta_items`:** `acuse_iniciales text` + `acuse_at timestamptz` (+ `acuse_categoria text` opcional para snapshot). Simple, 1 acuse por ítem, sin tabla nueva; la evidencia viaja con el ítem.
  - **(b2) Tabla dedicada `receta_item_acuse`:** `(id, receta_item_id FK, iniciales text, medico_id uuid, categoria text, created_at timestamptz)`. Permite más metadata / múltiples acuses / auditoría separada; append-only natural.
  - **En AMBAS:** `emitir_receta` **valida con RAISE** — si un ítem es regulado (`med.categoria_regulatoria ∈ {psicotropico, estupefaciente, recetario_especial}`) y **falta el acuse** → aborta la emisión (gate-antes-de-efecto, transacción O1). La clasificación se resuelve por `medicamento_id` (siempre presente en emisiones nuevas, §4); el acuse queda ligado a la receta/ítem como evidencia no evadible.
  - Trade-off para Oscar: b1 = menos superficie (1 migración de columnas, lectura trivial en el recetario/reporte); b2 = más flexible/auditable pero +1 tabla + join.

## 4 · VERIFICACIÓN EN VIVO — ¿`medicamento_id` siempre alcanzable? (corrige §2/§3) — **NO**
Comprobado en BD viva (2026-06-24):
| Hecho | Valor |
|---|---|
| `farmacia_medicamentos.medicamento_id` (FK al global) | **NO EXISTE la columna** (`fm_medid_existe=0`) → el surtido NO linkea al global |
| `receta_items.medicamento_id` | **nullable** |
| `receta_items` total / con id / sin id | **17 / 15 / 2** → **88% poblado, NO 100%** (2 NULL) |
| Único alta de ítem en RecetaModal | `handleAddMedicamento` (setea `medicamento_id=med.id` del global); **no hay alta libre hoy** |
| Ruteo a farmacia/lab (`seleccionarProveedor`) | solo agrega `farmacia_id`/precio a un ítem existente; **no toca `medicamento_id`** (y no podría: `farmacia_medicamentos` no tiene esa columna) |

**Conclusión precisa (corrige mi "independiente y limpio"):**
- **Ítems NUEVOS por el path actual:** `medicamento_id` **siempre presente** (único alta = catálogo global) → `categoria_regulatoria` **siempre alcanzable** en la selección → **el ACUSE es robusto** y la clasificación dura por id funciona.
- **Ítems históricos:** **2/17 con `medicamento_id` NULL** (legacy, anteriores a la columna) → para esos el global **NO es alcanzable por id** → **el REPORTE (A3) depende del fallback por nombre (§A2)**. NO son "independientes y limpios".
- **El ruteo a farmacia/lab nunca aporta `medicamento_id`** (la tabla de surtido no lo tiene) → la única fuente del id es `handleAddMedicamento`. Si en el futuro se agregara un alta libre o el surtido se volviera fuente de ítems, quedarían NULL → **A2 (obligar en `emitir_receta`) es la red de seguridad correcta, NO redundante**.
- **Neto:** O2 + acuse son **limpios para emisiones NUEVAS**, pero **dependen del fallback por nombre para el histórico**; la afirmación previa de independencia total era inexacta.

## 5 · Catálogo GLOBAL — quién clasifica + el "regulado" del Excel del lab
**Quién puebla/edita el global `medicamentos` hoy:**
- **RLS write = SOLO `super_admin`** (`medicamentos_write_admin: tiene_rol(['super_admin'])`; SELECT = todos). 40 filas. **No hay UI ni import para el global**; lo siembra `001_inicial.sql` y solo super_admin podría editarlo directo. → coherente con A2 (clasifica la UI super_admin, a construir).

**[CERRADO D-CAT-2] Dónde se setea `categoria_regulatoria` + el `regulado` del Excel del lab:**
- **La clasificación autoritativa se setea SOLO en el catálogo global `medicamentos`, write = `super_admin`** (gobernanza única; la lista de controlados es **nacional**, no la define cada tenant). Estado actual confirmado: 40 filas, sin UI/import, seed 001. La UI/CSV de clasificación super_admin es a construir (A2).
- **La columna `regulado` del Excel del lab queda ADVISORY:** **pista visible** en el import (p.ej. resaltar/avisar al cargar), **NO setea ni propaga** la `categoria_regulatoria` autoritativa. El surtido (`farmacia_medicamentos`) **NO es fuente regulatoria**; el médico clasifica por el **global** al recetar.
- **Descartadas:** (ii) propagar surtido→global por match de nombre (frágil + tenant escribiendo catálogo nacional); (iii) flag tenant-local autoritativo (duplica/diverge).
- **Fail-safe:** valor faltante/inválido → **`NULL`=sin_clasificar, NUNCA `venta_libre`**.
```
```
