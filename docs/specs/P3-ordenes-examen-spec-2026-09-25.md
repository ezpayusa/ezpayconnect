# P3 — Spec de la mig 332: órdenes de examen por RPC con `catalogo_id`

Estado: **solo diseño**. Base medida contra prod el 25-sep-2026 (main `34e4490`), solo SELECT.
Decisiones de Oscar que no se re-discuten: RPC atómica única vía de creación, con REVOKE del INSERT
directo; nombre de catálogo copiado por el servidor; texto libre explícito (`catalogo_id NULL`);
`examenes.catalogo_id` con FK `ON DELETE RESTRICT` y `tipo` como snapshot; backfill 10/4.

---

## 0. Hechos de partida (medidos)

- El nombre del examen vive en `examenes.tipo text NOT NULL`. `ordenes_examen` es la cabecera y
  `examenes.orden_id` la referencia con `ON DELETE CASCADE`.
- Hoy toda orden nace por **INSERT directo** del cliente, en dos sentencias no atómicas (cabecera y
  después ítems):
  - Médico: `ConsultaPage.tsx:183-193` y `202-216`.
  - Walk-in: `useLaboratorio.ts:230-238` y `241-253`.
- Ninguna función SQL, edge ni script inserta en `examenes` ni en `ordenes_examen`. El harness lo
  hace, pero siempre como `postgres` (`set_config('role','none')`): líneas 4774, 11210, 18861-18876
  y 19117-19121 de `tests/rls/probes_escritura.sql`.
- Las policies de INSERT actuales (`ordenes_medico_insert`, `examenes_medico_insert`) validan
  `medico_id = auth.uid()` y la pertenencia del paciente. **No validan `laboratorio_id`, `clinica_id`
  ni ninguna copia de texto**: un médico puede hoy dirigir una orden a cualquier `laboratorio_id` o
  declarar cualquier `clinica_id`.
- `examenes_catalogo` no tiene ningún UNIQUE de nombre. Tiene 9 filas, todas activas y todas del
  laboratorio QA `a5cf575a`. Hay 0 duplicados por `lower(btrim(nombre))`. El nombre más largo mide
  26 caracteres.
- Datos: 14 exámenes en 4 órdenes; la orden más grande tiene 5 ítems. 10 exámenes coinciden exacto
  dentro del mismo laboratorio y 4 son texto libre (ids 4, 158, 254 y 720).
- `pacientes.id` es `bigint`, `ordenes_examen.paciente_id` es `bigint` y `examenes.paciente_id` es
  `integer`.
- `pacientes` **no tiene columna de documento**; solo tiene `telefono`.
- `examenes` está en la publicación `supabase_realtime`: la bandeja del laboratorio se refresca por
  `postgres_changes` (`useLaboratorio.ts:112-122`).
- La app es una PWA con service worker (`dist/sw.js`, precache): hay clientes que siguen con el
  bundle viejo hasta que el service worker se actualiza.

---

## A. Campo por campo: qué manda hoy el cliente y de dónde lo saca la RPC

### A.1 Médico — `src/pages/ConsultaPage.tsx`

**`ordenes_examen`** (líneas 183-193)

| Campo | Hoy lo manda el cliente (línea) | En la RPC |
|---|---|---|
| `laboratorio_id` | `labSel \|\| null` (184) | **Parámetro validado** `p_laboratorio_id` (NULL = "sin asignar", ver D.6) |
| `clinica_id` | `clinica?.clinica_id`, sacado de `rpc('mi_clinica_medico')` (176, 185) | **Derivado**: `obtener_clinica_principal_medico(auth.uid())`; puede ser NULL, como hoy |
| `medico_id` | `perfil?.id` (186) | **Derivado**: `auth.uid()` |
| `paciente_id` | `paciente.id` (187) | **Parámetro validado** `p_paciente_id` (existe + pertenencia, ver C.1) |
| `origen` | `'medico'` (188) | **Fijo**: `'medico'` |
| `instrucciones` | `examenForm.descripcion.trim() \|\| null` (189) | **Parámetro validado** `p_instrucciones`: `NULLIF(btrim(...), '')`, máximo 2000 |
| `paciente_nombre` | `` `${nombre} ${apellido}` `` (190) | **Derivado**: `btrim(pacientes.nombre \|\| ' ' \|\| pacientes.apellido)` |
| `medico_nombre` | `perfil?.nombre_completo` (191) | **Derivado**: `perfiles.nombre_completo` de `auth.uid()` |
| `clinica_nombre` | `clinica?.clinica_nombre` (192) | **Derivado**: `clinicas.nombre` de la clínica derivada |
| `prioridad` | no la manda (default `'normal'`) | **Fijo**: `'normal'`; la UI del médico no tiene prioridad |
| `paciente_documento` / `paciente_telefono` | no los manda | **NULL**, como hoy (ver M.12) |

**`examenes`**, una fila por ítem (líneas 202-216)

| Campo | Hoy (línea) | En la RPC |
|---|---|---|
| `orden_id` | `orden.id` (203) | **Derivado**: la cabecera recién creada |
| `paciente_id`, `medico_id`, `laboratorio_id`, `clinica_id`, `origen`, `paciente_nombre`, `medico_nombre`, `clinica_nombre` | los mismos valores que la cabecera (204-213) | **Copia server-side** de la cabecera; `paciente_id` con cast a `integer` |
| `tipo` | el string elegido o tipeado (206) | Si hay `catalogo_id`: **copiado de `examenes_catalogo.nombre`**. Si es texto libre: `btrim(nombre)` validado |
| `catalogo_id` | no existe | **Nuevo**: el `catalogo_id` del ítem, o NULL si es texto libre |
| `descripcion` | `instrucciones` (207) | **Copia** de `instrucciones`; se conserva la duplicación de hoy |
| `estado` | `'pendiente'` (208) | **Fijo**: `'pendiente'` |
| `prioridad` | no la manda | **Fijo**: `'normal'` |
| `fecha_solicitud` | default | default `CURRENT_DATE` |

### A.2 Walk-in del laboratorio — `LabWalkInPage.tsx` y `useLaboratorio.ts:crearWalkIn`

**`ordenes_examen`** (`useLaboratorio.ts:230-238`)

| Campo | Hoy (línea) | En la RPC |
|---|---|---|
| `laboratorio_id` | `labId = empresa.id` de `useProveedorAuth` (231) | **Derivado**: `mi_empresa_proveedor()` |
| `origen` | `'walk_in'` (232) | **Fijo**: `'walk_in'` |
| `prioridad` | `datos.prioridad \|\| 'normal'` (233); la UI ofrece `normal` y `urgente` (`LabWalkInPage.tsx:94-95`) | **Parámetro validado** `p_prioridad IN ('normal','urgente')`; NULL = `'normal'` |
| `instrucciones` | (234) | **Parámetro validado**, igual que en el médico |
| `paciente_nombre` | (235) | **Parámetro validado** y obligatorio: `btrim`, no vacío, máximo 200. No hay otra fuente: el walk-in no tiene `paciente_id` |
| `paciente_documento` | (236) | **Parámetro validado**, opcional: `NULLIF(btrim)`, máximo 50 |
| `paciente_telefono` | (237) | **Parámetro validado**, opcional: `NULLIF(btrim)`, máximo 30 |
| `clinica_id`, `medico_id`, `paciente_id`, `medico_nombre`, `clinica_nombre` | no los manda | **NULL fijo** |

**`examenes`** (`useLaboratorio.ts:241-253`): la misma copia de la cabecera que en el médico, con estas
diferencias:
- `estado` **fijo en `'recibida'`** (248).
- `prioridad` = la de la cabecera (245).
- `descripcion` = `instrucciones` (244).
- `tipo` y `catalogo_id` como en A.1.

**Regla general**: ni la identidad (`medico_id`, `laboratorio_id`, `clinica_id`) ni las copias de texto
de médico o clínica vienen del cliente. Del cliente solo vienen el paciente elegido (validado), el
laboratorio elegido por el médico (validado), los ítems, las instrucciones y, en el walk-in, los datos
del paciente sin cuenta, que no tienen otra fuente.

---

## B. Dos RPCs, no una

**Recomendación: dos funciones.** Los gates, las derivaciones y el estado inicial no comparten nada
salvo el armado de ítems. Una sola función con un parámetro de modo mezclaría dos modelos de
autorización en un mismo cuerpo, con el riesgo de que un brazo filtre al otro. La validación de ítems
se factoriza en un helper `private.` que usan las dos.

```
public.crear_orden_examen_medico(
  p_paciente_id    bigint,
  p_laboratorio_id uuid,      -- NULL = sin asignar
  p_items          jsonb,
  p_instrucciones  text DEFAULT NULL
) RETURNS jsonb             -- {orden_id, examen_ids:[...], n_items}

public.crear_orden_examen_walkin(
  p_items              jsonb,
  p_paciente_nombre    text,
  p_paciente_documento text DEFAULT NULL,
  p_paciente_telefono  text DEFAULT NULL,
  p_instrucciones      text DEFAULT NULL,
  p_prioridad          text DEFAULT 'normal'
) RETURNS jsonb             -- {orden_id, examen_ids:[...], n_items}
```

Las dos son `SECURITY DEFINER`, `SET search_path = ''`, owner `postgres` y `VOLATILE`. GRANT EXECUTE
solo a `authenticated` y `service_role`; REVOKE de `PUBLIC` y `anon`. Son plpgsql en una sola
transacción: si cualquier ítem falla, no queda nada escrito.

**Formato de ítems**: un array jsonb de objetos, y **cada objeto trae exactamente una** de las dos
claves:
- `{"catalogo_id": "<uuid>"}`: examen de catálogo. El nombre lo pone el servidor.
- `{"nombre": "<texto>"}`: examen fuera de catálogo.

Si un objeto trae las dos claves, o ninguna, es un ítem mal formado (EX010). Así el cliente no puede
mandar un nombre "de catálogo" que no coincida con el catálogo.

**Helper**: `private.armar_items_orden_examen(p_laboratorio_id uuid, p_items jsonb) RETURNS TABLE(tipo text, catalogo_id uuid)`.
- Aplica toda la sección D y devuelve los ítems ya resueltos.
- Es SECURITY DEFINER, sin EXECUTE para `authenticated` (como `exigir_empresa_activa`: ACL solo
  `postgres`).

---

## C. Gates (todos fail-closed con `COALESCE(..., false)`, en este orden)

### C.1 Médico

1. `auth.uid() IS NULL` → **EX001**.
2. `NOT COALESCE(private.tiene_rol(ARRAY['medico']), false)` → **EX002**. Es el mismo patrón que
   `emitir_receta` (mig 316, PR002). `tiene_rol` ya exige un perfil activo (mig 315).
3. `p_paciente_id IS NULL` o el paciente no existe → **EX003**.
4. Pertenencia → **EX004**. Es exactamente el predicado de hoy de `ordenes_medico_insert` y de
   `emitir_receta` (PR009): `private.medico_atiende_paciente(p_paciente_id) OR EXISTS (pacientes pa
   WHERE pa.id = p_paciente_id AND pa.medico_id = auth.uid())`.
5. Laboratorio, si `p_laboratorio_id IS NOT NULL` → **EX005**. El laboratorio tiene que existir en
   `empresas_proveedoras`, con `tipo = 'laboratorio_clinico'`, `estado = 'activa'` y
   `pais_id = private.mi_pais()`, envuelto en `COALESCE(..., false)`. **Es el mismo universo que
   ofrece `laboratorios_para_medico()`** (tipo, estado y país). Hoy esto no lo valida nadie.
6. Clínica: **hoy `clinica_id` no se valida**; el cliente la manda desde `mi_clinica_medico()` y la
   policy no la mira. En la RPC deja de ser una entrada: se deriva de
   `obtener_clinica_principal_medico(auth.uid())`, la misma fuente que usa `mi_clinica_medico()`. Si
   el médico no tiene clínica principal, queda NULL, como hoy. No se agrega ningún gate "paciente de la
   clínica", porque hoy no existe (ver M.10).

### C.2 Walk-in

1. `auth.uid() IS NULL` → **EX001**.
2. `PERFORM private.exigir_empresa_activa()`. Lanza **42501** si la cuenta está inactiva o la empresa
   no está activa (M4, mig 326). Conserva su errcode de siempre y no se renumera.
3. `v_lab := public.mi_empresa_proveedor()`; si es NULL, o la empresa no es `laboratorio_clinico` →
   **EX006**. Hace falta porque `exigir_empresa_activa` no hace nada cuando el llamante no es
   proveedor (devuelve NULL sin lanzar). `mi_empresa_proveedor()` ya filtra cuenta y empresa activas.
4. `NOT COALESCE(private.tiene_permiso('walkin_registrar'), false)` → **EX007**. Es el mismo permiso
   que gatea la UI (`LabWalkInPage.tsx:53`). Hoy lo tienen `laboratorio_clinico/admin` y
   `laboratorio_clinico/recepcion`, sin overrides.
   - `tiene_permiso` ya acota por tipo de empresa, y `set_permiso_override` impide conceder una acción
     de otro tipo (PR003). El chequeo de tipo del paso 3 queda como defensa explícita.

---

## D. Validación de ítems (helper común, en este orden)

1. `p_items` NULL, no es un arreglo o está vacío → **EX008**.
2. `jsonb_array_length(p_items) > 30` → **EX009**. El máximo real hoy es 5; ver M.14.
3. Por cada elemento:
   - No es un objeto, o trae ambas claves o ninguna, o `catalogo_id` no es un uuid válido (el cast se
     captura en un sub-bloque) → **EX010**.
   - Con `catalogo_id`:
     - La orden no tiene laboratorio → **EX013** ("una orden sin laboratorio solo admite exámenes
       escritos a mano").
     - No existe una fila con ese id **y** `laboratorio_id = laboratorio de la orden` → **EX011**. No
       distingue "no existe" de "es de otro laboratorio", así no filtra la existencia de filas de otro
       laboratorio.
     - Existe, pero `activo = false` → **EX012**.
     - El país queda cubierto porque el laboratorio ya pasó C.1.5, y el ítem tiene que ser de ese
       mismo laboratorio.
     - Se lee `examenes_catalogo` como DEFINER, sin depender de la RLS del llamante. Por eso el chequeo
       de `activo` tiene que ser explícito.
   - Con `nombre`:
     - `btrim(nombre)` vacío → **EX015**.
     - `length(btrim(nombre)) > 200` → **EX016**.
     - (Punto abierto M.3) coincide con `lower(btrim())` de un examen **activo** del catálogo del mismo
       laboratorio → **EX017**, "Ese examen está en el catálogo: selecciónelo de la lista".
4. Duplicados dentro de la orden → **EX014**: el mismo `catalogo_id` dos veces o, según M.4, el mismo
   texto libre dos veces (comparado con `lower(btrim())`).
5. **Orden sin laboratorio**: se permite solo en el médico (hoy la opción está en `ConsultaPage.tsx:862`,
   "— Sin asignar (el paciente elige) —"), y solo con ítems de texto libre. El walk-in siempre tiene
   laboratorio (el derivado).
6. Resto de parámetros:
   - `p_instrucciones` de más de 2000 caracteres → **EX020**.
   - En el walk-in, `p_paciente_nombre` vacío o de más de 200, `p_paciente_documento` de más de 50 o
     `p_paciente_telefono` de más de 30 → **EX018**.
   - `p_prioridad` fuera de `('normal','urgente')` → **EX019**.

---

## E. Errcodes — familia nueva `EX` (exámenes)

**Verificado con grep** en `supabase/migrations`, `supabase/fixes`, `src` y `tests`: no hay ningún
`EX0nn`. Los prefijos en uso son PT, PC, PR, PA, SV, PP, PV y PE. Los de `notificar_orden_lab` son
PT001-PT003 y no se tocan.

| Código | Causa | Mensaje |
|---|---|---|
| EX001 | Sin sesión | No autorizado: inicie sesión |
| EX002 | El llamante no es médico (RPC del médico) | No autorizado: solo un médico puede ordenar exámenes |
| EX003 | Paciente nulo o inexistente | Paciente no encontrado |
| EX004 | El médico no atiende a ese paciente | No autorizado: no atiende a este paciente |
| EX005 | Laboratorio inexistente, que no es de tipo clínico, inactivo o de otro país | Laboratorio no disponible para esta orden |
| EX006 | El llamante no es una cuenta de un laboratorio clínico activo (walk-in) | No autorizado: su cuenta no pertenece a un laboratorio clínico activo |
| EX007 | Sin el permiso `walkin_registrar` | No autorizado: no tiene permiso para registrar pacientes sin cita |
| EX008 | Lista de ítems nula, que no es un arreglo o vacía | Seleccione o escriba al menos un examen |
| EX009 | Más de 30 ítems | Una orden admite como máximo 30 exámenes |
| EX010 | Ítem mal formado | Examen mal formado en la orden |
| EX011 | `catalogo_id` que no es del laboratorio de la orden, o que no existe | El examen seleccionado no pertenece al catálogo de este laboratorio |
| EX012 | `catalogo_id` inactivo | El examen seleccionado ya no está disponible en el catálogo |
| EX013 | `catalogo_id` en una orden sin laboratorio | Una orden sin laboratorio solo admite exámenes escritos a mano |
| EX014 | Ítem repetido | Hay exámenes repetidos en la orden |
| EX015 | Nombre de texto libre vacío | El nombre del examen no puede estar vacío |
| EX016 | Nombre de más de 200 caracteres | El nombre del examen es demasiado largo (máximo 200) |
| EX017 | (Si se aprueba M.3) texto libre que coincide con el catálogo activo | Ese examen está en el catálogo: selecciónelo de la lista |
| EX018 | Datos del paciente del walk-in inválidos | Datos del paciente inválidos (nombre obligatorio, máximo 200; documento máximo 50; teléfono máximo 30) |
| EX019 | Prioridad inválida | Prioridad inválida (normal o urgente) |
| EX020 | Instrucciones de más de 2000 caracteres | Las instrucciones son demasiado largas (máximo 2000) |
| EX021 | (Si en I se elige el bloqueo por trigger) renombrar un examen de catálogo ya ordenado | Este examen ya fue ordenado: no se puede renombrar; desactívelo y cree uno nuevo |
| EX022 | Cambiar `tipo` o `catalogo_id` de un examen ya creado (trigger de H) | El examen de una orden no se puede cambiar una vez creado |

Errores que no son de la familia EX: **42501** de `exigir_empresa_activa`, **23503** de la FK RESTRICT
(borrar un examen de catálogo ya ordenado) y **23505** del UNIQUE del catálogo, si se aprueba I.

**Próximos números libres después de esta mig**: EX023 (o EX021 si I y H se resuelven sin trigger), la
probe que siga a las de K y la mig 334 si se aprueba el despliegue en dos fases (M.1).

---

## F. `notificar_orden_lab`

**Su gate funciona invocado desde un DEFINER.** Compara `v_med = auth.uid()`, y `auth.uid()` lee
`request.jwt.claims` (un GUC de la sesión), no `current_user`. Dentro de una función SECURITY DEFINER
el JWT sigue siendo el del médico, así que el gate pasa por el mismo motivo que hoy.

Otros hechos:
- Para el **walk-in no sirve**: exige médico y paciente no NULL en todos los ítems (PT003). Hoy el
  walk-in no la llama, y así debe seguir.
- Con una orden sin laboratorio funciona: solo notifica al paciente (su comentario lo contempla).
- Hoy el médico la llama después de los inserts (`ConsultaPage.tsx:228`), como best-effort.

**Recomendación**: llamarla **desde `crear_orden_examen_medico`**, al final, dentro de un sub-bloque
`BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING … END`.
- El sub-bloque es un savepoint: si la notificación falla, se deshacen solo sus escrituras y la orden
  se confirma igual. Es el mismo contrato best-effort de hoy.
- El cliente hace un solo llamado y no puede olvidarse de notificar.
- `ConsultaPage.tsx:223-229` se elimina.
- La alternativa es dejarla en el cliente. Es la opción conservadora, pero mantiene dos llamados y el
  riesgo de una orden sin aviso. Ver M.2.

---

## G. REVOKE, DROP y grants

**Policies que se eliminan**
- `ordenes_examen.ordenes_medico_insert`.
- `examenes.examenes_medico_insert`.

**Policies ALL que incluyen INSERT** (`ordenes_lab_all`, `examenes_laboratorio_all`,
`examenes_superadmin_all`):
- Con el INSERT revocado del grant, el INSERT directo muere de todas formas, porque el chequeo de
  privilegio va antes que la RLS.
- **Recomendación**: partirlas igual que la mig 328 (d), en SELECT, UPDATE y DELETE con la misma
  expresión, para que el catálogo de policies no diga que existe un INSERT que no existe.
- `catalogo_lab_all` **no se toca** (es del catálogo, no de las órdenes).

**Grants (regla del 30-oct: grants explícitos de lo que queda en uso)**
- `REVOKE INSERT ON ordenes_examen, examenes FROM authenticated, anon, PUBLIC`. Hoy `anon` y
  `PUBLIC` no tienen grants sobre estas tablas; se revocan igual, de forma explícita.
- `REVOKE TRUNCATE, TRIGGER, REFERENCES ON ordenes_examen, examenes FROM authenticated`. Hoy los
  tiene y nada los usa (ver M.8).
- `ordenes_examen`: `authenticated` se queda con **SELECT, DELETE**. El UPDATE se revoca porque nadie
  lo usa: ni el front, ni una edge, ni una RPC (ver M.7).
- `examenes`: `authenticated` se queda con **SELECT, DELETE** y **UPDATE solo por columna**
  (sección H).
- `service_role`: SELECT, INSERT, UPDATE y DELETE en las dos.
- `examen_adjuntos`: no se toca.

**Otros writers: confirmado que no hay**
- Edges: ninguna escribe estas tablas (grep en `supabase/functions`, `scripts` y `api`).
- RPCs: solo UPDATE, desde las funciones DEFINER de liberación y reversión, cuyo owner es `postgres`
  y no dependen de grants.
- Scripts: ninguno.
- Harness: inserta como `postgres` (líneas citadas en la sección 0) y **sigue funcionando**. No
  encontré ninguna probe que inserte en estas tablas como `authenticated`.

**Lección de la mig 284**
- Acá solo se revoca INSERT, UPDATE sobre `ordenes_examen` y UPDATE por columna sobre `examenes`.
  **No se revoca SELECT**, que es lo que consultan otras policies en su USING, por ejemplo
  `private.puede_ver_examen` en `examen_adjuntos`.
- Igual va una probe que **ejercite** a médico, laboratorio y paciente contra `examenes`,
  `ordenes_examen` y `examen_adjuntos`, esperando 0 errores (K, P877).

---

## H. Congelar `tipo` y `catalogo_id` después del INSERT

**Quién hace UPDATE de `examenes` hoy y qué columnas toca**

| Writer | Vía | Columnas |
|---|---|---|
| `useLaboratorio.cambiarEstado` (`:124-132`) | directo, laboratorio (`examenes_laboratorio_all`) | `estado`, `fecha_resultado` |
| `useLaboratorio.subirResultado` (`:155-160`) | directo, laboratorio | `resultados`, `archivo_url`, `estado`, `fecha_resultado` |
| `liberar_examen_al_paciente` / `liberar_orden_al_paciente` | DEFINER | `liberado_al_paciente`, `fecha_liberacion`, `liberado_por` |
| `revertir_liberacion_examen` | DEFINER | `liberado_al_paciente`, `revertido_por`, `fecha_reversion` |
| Setup del harness (líneas 6146-6211, 6964) | `postgres` | `laboratorio_id`, `paciente_id`, `medico_id` |
| `examenes_medico_update` | policy existente | **nadie la usa** (grep del front) |

`updated_at` no la escribe nadie: no hay trigger y no se manda.

**Propuesta, en dos capas**
1. **Grants por columna**: `REVOKE UPDATE ON examenes FROM authenticated` y después
   `GRANT UPDATE (estado, fecha_resultado, resultados, archivo_url) ON examenes TO authenticated`.
   - Eso congela para el cliente **todas** las demás columnas: `tipo` y `catalogo_id`, pero también
     `laboratorio_id`, `paciente_id`, `medico_id`, `orden_id` y las columnas de liberación. Así se
     cierra además la clase "laboratorio muta la identidad del examen" que prueban los fixtures `lx_*`.
   - Hay precedente en la mig 277 (privilegio por columna).
   - Liberación y reversión no se rompen: son DEFINER con owner `postgres`.
   - `supabase-js` manda en el UPDATE solo las claves del patch, así que los dos writers del
     laboratorio siguen andando.
2. **Trigger** `BEFORE UPDATE OF tipo, catalogo_id ON examenes` que rechaza con **EX022** si
   `NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.catalogo_id IS DISTINCT FROM OLD.catalogo_id`.
   - Ataja también a los DEFINER y a `postgres`.
   - Se crea **después** del backfill dentro de la misma migración, porque el backfill escribe
     `catalogo_id`.

**Además**: `DROP POLICY examenes_medico_update`, porque no la usa nadie (ver M.7). Con los grants por
columna, dejarla le permitiría al médico cambiar `estado` o `resultados` de sus exámenes, algo que hoy
no hace ninguna pantalla.

---

## I. Catálogo: unicidad y renombre

**UNIQUE**
- **Los datos lo permiten**: 0 duplicados por `(laboratorio_id, lower(btrim(nombre)))`, y también 0
  si además se sacan los acentos.
- Opción 1, recomendada: `CREATE UNIQUE INDEX ux_examenes_catalogo_lab_nombre ON examenes_catalogo
  (laboratorio_id, lower(btrim(nombre)))`.
  - A favor: la expresión es IMMUTABLE, es fácil de explicar y evita que "Hemograma" y "hemograma "
    convivan. `crearCatalogo` recibe un 23505 que el front traduce.
  - En contra: "Coprológico" y "Coprologico" pueden convivir.
- Opción 2: agregar `translate(...)` para sacar los acentos.
  - A favor: detecta también las variantes sin tilde.
  - En contra: la lista de caracteres es arbitraria (`unaccent` no está instalada y además no es
    IMMUTABLE), y es más difícil de explicar el mensaje de rechazo.

**Renombre**
- Hoy no hay UI para renombrar, pero `catalogo_lab_all` más el GRANT de UPDATE a `authenticated`
  permiten hacerlo por API.
- Con `catalogo_id` la identidad ya no depende del nombre, pero el riesgo semántico sigue: renombrar
  "Hemograma" a "Glucosa" cambia el significado de todas las órdenes que apuntan a esa fila.
- Opción 1, recomendada: grants por columna, `REVOKE UPDATE ON examenes_catalogo FROM authenticated`
  y `GRANT UPDATE (activo, categoria)`.
  - A favor: no se puede renombrar ninguna fila, nadie lo usa hoy, no hay trigger ni errcode nuevo, y
    es coherente con H.
  - En contra: tampoco se puede corregir un typo en una fila nunca ordenada. El camino es borrarla (se
    puede, porque no está referenciada) y crearla de nuevo.
- Opción 2: un trigger que bloquee `UPDATE OF nombre` solo si hay algún `examenes.catalogo_id` que
  apunte a la fila (EX021).
  - A favor: deja corregir typos antes del primer uso.
  - En contra: más piezas, y una regla que cambia según el estado de la fila.

---

## J. Front

**`src/pages/ConsultaPage.tsx`**
- `examenesSel` pasa de un `Set<string>` de nombres a un `Set<string>` de **ids de catálogo** (134,
  158-159, 913: `has(c.id)` / `toggle(c.id)`).
- `handleCrearExamen` (161-240) se reemplaza por **un solo** `rpc('crear_orden_examen_medico', { p_paciente_id,
  p_laboratorio_id: labSel || null, p_items, p_instrucciones })`, con:
  - `p_items` = `[...sel].map(id => ({catalogo_id: id}))` + las líneas de "Otros" como `{nombre}`.
  - Sin laboratorio, solo el `tipo` libre como `{nombre}`.
- Se eliminan el `rpc('mi_clinica_medico')` de la línea 176, los dos inserts y (si se aprueba F) el
  llamado a `notificar_orden_lab` de 223-229.
- Los errores EX se muestran como toast con `error.message`: los mensajes están en español.

**`src/laboratorio/pages/LabWalkInPage.tsx`**
- `sel` pasa a guardar ids (31-33 y 116).
- `crearWalkIn` recibe `items: {catalogo_id?: string; nombre?: string}[]` en lugar de
  `examenes: string[]` (36-47).

**`src/laboratorio/hooks/useLaboratorio.ts`**
- `crearWalkIn` (223-259) pasa a `rpc('crear_orden_examen_walkin', ...)`.
- `fetchOrdenes` (60) agrega `catalogo_id` al select.
- `OrdenExamen` (7-25) agrega `catalogo_id: string | null`.
- `eliminarCatalogo` (206-212): si `error.code === '23503'`, muestra "Este examen ya fue ordenado y no
  se puede eliminar. ¿Desactivarlo?" con una acción que llama a `toggleCatalogo(id, false)`, en lugar
  del "No se pudo eliminar" genérico.
- `crearCatalogo` (189-198): si `error.code === '23505'` (UNIQUE de I), muestra "Ya existe un examen
  con ese nombre en su catálogo".

**`src/laboratorio/pages/LabCatalogoPage.tsx`**
- El botón de borrar (108) usa el nuevo flujo de `eliminarCatalogo`.
- Si se aprueba el bloqueo de renombre, no hay nada que cambiar: no existe UI de renombre.

**`src/laboratorio/pages/LabOrdenesPage.tsx:144`**
- Al lado de `{i.tipo}` va un badge **"fuera de catálogo"** cuando `i.catalogo_id == null`.
- Los 4 exámenes viejos de texto libre lo van a mostrar, que es lo correcto.

Fuera de alcance, aunque son candidatos a la misma marca: el panel de exámenes de la consulta
(`ConsultaPage.tsx:763`) y la ficha del paciente (`PacienteDetallePage.tsx:722`).

---

## K. Probes propuestas (desde P866)

**Fixture**: todo dentro de la transacción del harness y como `postgres`.
- Médico QA `09d243d5` con el paciente 23 (tiene la cita 970, así que pasa la pertenencia).
- Laboratorio QA `a5cf575a` (GT, activo), con sus cuentas `recepcion`, `admin` y `tecnico`.
- Se siembran:
  - Una fila inactiva en el catálogo de `a5cf575a`.
  - Una fila de catálogo de otro laboratorio.
  - Un laboratorio de otro país.
  - Un paciente que el médico no atiende.
- Se impersona con `request.jwt.claims` y `role authenticated`, como en P848-P865.

**Restauración**
- Cada probe toma un snapshot `md5(string_agg(row_to_json))` de `examenes`, `ordenes_examen` y
  `examenes_catalogo` (filas con id menor o igual al máximo al inicio), más los `max(id)` de
  `notificaciones` y `notificaciones_pacientes`.
- Al final borra lo que creó: las órdenes creadas, cuyos exámenes caen por CASCADE, y las
  notificaciones con id mayor al snapshot que apunten a esas órdenes.
- Verifica que el snapshot quedó igual.

| Probe | Qué prueba | Esperado |
|---|---|---|
| P866 | Médico, positivo con efecto: 2 de catálogo + 1 de texto libre | 1 orden y 3 exámenes. `tipo` de catálogo = `examenes_catalogo.nombre` sin que el cliente lo mande. `catalogo_id` puesto en los de catálogo y NULL en el libre. `medico_id` = uid; `clinica_id` y los nombres derivados del servidor; estado `pendiente`; prioridad `normal`. Una notificación al laboratorio y una al paciente (si se aprueba F) |
| P867 | Médico sin laboratorio | Solo texto libre: OK, con `laboratorio_id` NULL. Con un `catalogo_id`: EX013 y ninguna fila |
| P868 | Walk-in (recepción), positivo con efecto | Laboratorio derivado, `origen = 'walk_in'`, estado `recibida`, prioridad `urgente`, sin notificación |
| P869 | Rechazos del médico, uno por causa, por SQLERRM exacto y sin filas nuevas | EX001, EX002 (cuenta de laboratorio), EX003, EX004, EX005 (tres casos: otro país, inactivo y farmacia), EX008 a EX016, (EX017), EX020 |
| P870 | Rechazos del walk-in, uno por causa | EX006 (el médico llama al walk-in), EX007 (técnico), 42501 (cuenta inactiva) y 42501 (empresa no activa), EX018, EX019, EX020 |
| P871 | Atomicidad | 2 ítems válidos y el 3.º inválido: EX y **0** órdenes y **0** exámenes nuevos |
| P872 | INSERT directo denegado | Médico, laboratorio y super_admin: `INSERT` en `ordenes_examen` y en `examenes` → 42501. UPDATE de `ordenes_examen` → 42501 |
| P873 | FK RESTRICT | Borrar una fila de catálogo referenciada (como admin del laboratorio) → 23503 y la fila sigue. Borrar una no referenciada → OK. Desactivar una referenciada → OK |
| P874 | Congelamiento | El laboratorio hace UPDATE de `tipo` → 42501; de `catalogo_id` → 42501; de `laboratorio_id` o `paciente_id` → 42501. Como `postgres`, UPDATE de `tipo` → EX022. Controles OK: el laboratorio actualiza `estado`, `resultados`, `archivo_url` y `fecha_resultado`, y liberar y revertir siguen funcionando |
| P875 | Backfill 10/4 | Los ids 1, 2, 3, 157, 250, 251, 252, 253, 718 y 719 tienen el `catalogo_id` exacto de la tabla de L.1. Los ids 4, 158, 254 y 720 están en NULL |
| P876 | Catálogo | UNIQUE → 23505 (si se aprueba). Renombrar → 42501 (si se aprueban los grants por columna) o EX021. El médico no ve filas inactivas por SELECT directo |
| P877 | Dependientes (lección de la mig 284) | Médico, laboratorio y paciente leen `examenes`, `ordenes_examen` y `examen_adjuntos` sin error |
| P878 | Catálogo de objetos | Las 2 RPCs y el helper con firma única, SECURITY DEFINER, `search_path=""`, ACL exacta (sin anon ni PUBLIC; el helper sin `authenticated`) y md5 fijado. Grants exactos por tabla y por columna. Sin policies de INSERT en las dos tablas. Trigger presente. FK `confdeltype = 'r'`. Los 5 lectores de P860 sin cambios |

- Con el rollback aplicado: P866 a P871 dan ROJO (la RPC no existe o se revierte, según L), P872 da
  ROJO, P874 da ROJO y P878 da ROJO. P875 y P877 quedan OK.
- **Deuda del harness a revisar en el dry-run**: las probes `lx_*` (líneas 6146-6211) y cualquier
  probe que haga UPDATE de columnas ahora congeladas como `authenticated`, esperando éxito. Mi grep no
  encontró ninguna, pero el dry-run es el que lo confirma.

---

## L. Backfill y rollback

### L.1 Backfill (dentro de la 332, antes del trigger de H)

`UPDATE examenes e SET catalogo_id = c.id FROM examenes_catalogo c WHERE c.laboratorio_id = e.laboratorio_id AND c.nombre = e.tipo AND e.catalogo_id IS NULL`.

Resultado esperado hoy:

| ids | tipo | catalogo_id |
|---|---|---|
| 1, 250, 718 | Coprológico | 27a2af0f-e201-4a1d-900a-cb27851d9577 |
| 2, 252 | Tiempo de protrombina (TP) | 43a1a45c-82f7-403a-a663-1ab7fc8b3732 |
| 3, 253 | Prueba de embarazo (BHCG) | 4f32f195-e4de-4282-8303-8ec8bafecec1 |
| 157, 251, 719 | Hemograma completo | 7c980fb6-5048-4905-a682-9d6e9feb55ed |
| 4, 158, 254, 720 | (texto libre) | NULL |

**Autochequeo**:
- Exactamente 10 filas con `catalogo_id`, exactamente esos ids y exactamente esos pares.
- Los ids 4, 158, 254 y 720 en NULL.
- **Ninguna otra fila** con `catalogo_id`.
- Si entre hoy y la aplicación se crean órdenes nuevas, el conteo cambia y la migración **aborta**. Es
  intencional: se re-mide y se decide.

### L.2 Rollback (`332_rollback.sql`)

Restaura el acceso de antes de la 332:
- Los grants de tabla completos de `authenticated`, **incluyendo** TRUNCATE, TRIGGER y REFERENCES,
  para volver exacto.
- El UPDATE de tabla en `examenes` y en `ordenes_examen`.
- Recrea `ordenes_medico_insert`, `examenes_medico_insert` y `examenes_medico_update` con su
  definición exacta de hoy. Hay que capturarla con `pg_get_expr` antes de aplicar.
- Recompone las tres policies ALL, si se partieron.
- DROP del trigger de congelamiento, del UNIQUE y de los grants por columna del catálogo (vuelve el
  UPDATE de tabla).

**Qué no restaura**:
- Las **filas creadas por la RPC**: son órdenes válidas, con `tipo` como snapshot, y el front viejo
  las lee igual.
- Los **datos del backfill**.

**Punto abierto M.1b**: el rollback **conserva** la columna `catalogo_id`, la FK y las dos RPCs.
- Son aditivas y no molestan al front viejo.
- Si se borraran, el front nuevo se rompería mientras el front viejo todavía no está desplegado.
- Borrarlos del todo sería un paso aparte, después de revertir el front.

---

## M. Riesgos y puntos abiertos (para Oscar)

1. **Orden de despliegue**. Con REVOKE en la misma migración, apenas se aplica, el front viejo
   (incluidos los clientes con el service worker cacheado) deja de poder crear órdenes, hasta que
   Vercel publica el front nuevo y la PWA se actualiza.
   - **Recomendación**: dos migraciones.
     - **332**, aditiva: columna, FK, backfill, RPCs, helper, UNIQUE y congelamiento por trigger.
       Nada de eso rompe al front viejo.
     - Deploy del front.
     - **333**, de cierre: REVOKE de INSERT, DROP de policies, grants por columna y split de ALL.
   - Es la misma idea que el flag de la mig 328, sin flag.
2. **`notificar_orden_lab` dentro de la RPC** (F). Recomiendo que sí, en un sub-bloque protegido.
3. **Texto libre que coincide con el catálogo activo** (EX017). Recomiendo rechazar: sin eso vuelve
   la ambigüedad que motivó P3. Lo malo es un rechazo más para el médico, mitigado si el front avisa
   antes de enviar.
4. **Texto libre duplicado dentro de la orden**. Recomiendo rechazarlo con EX014, igual que el
   catálogo duplicado.
5. **UNIQUE del catálogo**: con o sin acentos. Recomiendo `lower(btrim())`, sin `translate` (I).
6. **Renombre**: grants por columna o trigger por fila referenciada. Recomiendo grants por columna (I).
7. **Sacar el UPDATE de `ordenes_examen` y `examenes_medico_update`**. No los usa nadie; recomiendo
   sacarlos.
   - Aparte: `examenes_laboratorio_all` y `ordenes_lab_all` le permiten al laboratorio hacer DELETE
     de órdenes y exámenes, y ninguna pantalla lo usa. Recomiendo **no** tocarlo en esta migración y
     anotarlo como pendiente.
8. **TRUNCATE, TRIGGER y REFERENCES** de `authenticated` en las dos tablas. Recomiendo revocarlos en
   el mismo lote: PostgREST no los expone, pero la regla del 30-oct pide grants exactos de lo que se
   usa.
9. **Validar el laboratorio que elige el médico** (EX005). Hoy no se valida. Lo recomiendo: es el
   mismo universo que ya ofrece `laboratorios_para_medico`.
10. **Clínica**. Derivarla sin validar la relación paciente-clínica mantiene el comportamiento de hoy.
    Recomiendo no endurecer esto en esta migración.
11. **FK RESTRICT y el `ON DELETE CASCADE` de `examenes_catalogo.laboratorio_id`**. Borrar un
    laboratorio con exámenes ordenados de catálogo va a fallar: la cascada intenta borrar filas de
    catálogo referenciadas. Recomiendo aceptarlo, porque las empresas se desactivan y no se borran
    (mig 322). Hay que documentarlo.
12. **Documento y teléfono del paciente del walk-in**. Son inevitablemente texto del cliente, porque
    no hay `paciente_id`. En el médico, `paciente_documento` y `paciente_telefono` siguen en NULL como
    hoy. Se podría derivar `pacientes.telefono`; recomiendo no hacerlo, está fuera de alcance.
13. **`examenes.paciente_id` es `integer` y `pacientes.id` es `bigint`**. La RPC castea; los ids
    actuales entran de sobra. Recomiendo anotarlo y no cambiar el tipo acá.
14. **Topes**: 30 ítems, 200 caracteres de nombre, 2000 de instrucciones, 50 de documento y 30 de
    teléfono. Hay que confirmarlos.
15. **Backfill 10/4 fijo**. Si entra una orden nueva antes de aplicar, la migración aborta y se
    re-mide. Recomiendo mantenerlo así: es lo que pidió Oscar.
16. **Realtime**. Los INSERT hechos por la RPC siguen emitiendo `postgres_changes`, y la bandeja del
    laboratorio los recibe por su RLS de SELECT. No hay que cambiar nada, pero conviene una prueba en
    el navegador.
17. **Harness**. Las probes que hagan UPDATE como `authenticated` sobre columnas ahora congeladas
    pasarían de OK a 42501. Mi grep no encontró ninguna; el dry-run lo confirma.

---

## Veredicto

**Todavía no está lista para implementar**, por dos motivos:
1. **M.1**, el despliegue en una o dos migraciones, cambia el contenido de la 332: qué entra y qué
   queda para la 333.
2. **M.2, M.3, M.6 y M.7** cambian el cuerpo de la RPC, los errcodes y los grants.

Con esas cinco respuestas, la spec queda cerrada para implementar sin más recon. Todo lo demás
(gates, derivaciones, validación de ítems, errcodes, backfill, probes y front) está definido y medido
contra la base viva.
