# P4 — Spec: revisiones inmutables de notas clínicas y resultados (migs 334, 335, 336)

Estado: **solo diseño, v2** (26-sep-2026). Base medida contra prod (main `f597761`), solo SELECT
(`tmp/p4_recon/*.sql`, `tmp/p4_spec/q_defs.sql`, `tmp/p4_spec/q_v2*.sql`). Insumo: `tmp/p4_recon/REPORTE.md`.
Decisiones D1–D12 y respuestas R1–R6 de Oscar cerradas. Lo que la spec agrega por su cuenta va marcado **[spec]**.
Los cambios respecto de la v1 están al final, en **CAMBIOS v2**.

---

## 0. Hechos de partida (medidos)

- **`expediente_notas`**: 1 fila (nota 1013, cita 1354 en estado `en_curso`). Sin `updated_at`. Ninguna función escribe en ella: el front hace INSERT/UPDATE directo (`useConsultas.ts:69-80`, con `medico_id = user.id`). `authenticated` tiene todos los privilegios de tabla (`arwdDxtm`). Policies: `exp_insert_medico`, `exp_select_medico`, `exp_select_paciente`, `Admin clinica ve expediente de su clinica`, `exp_update_medico` (USING/CHECK `medico_id = auth.uid()`), `exp_superadmin_all` (ALL).
- **Tipos de las columnas que se cruzan** (v2):
  - `citas`: `id bigint`, `medico_id uuid`, `paciente_id bigint`, `estado text`.
  - `expediente_notas`: `id integer`, `cita_id integer`, `paciente_id integer NOT NULL`, `medico_id uuid NOT NULL`.
  - La nota 1013 cumple la integridad nota↔cita: mismo médico `09d243d5…` y mismo paciente 546.
  - 5 citas tienen `medico_id` NULL: 27, 28 y 29 agendadas, 52 y 53 confirmadas. Son de junio, ninguna tiene nota. 0 citas tienen `paciente_id` NULL.
- **IMC** (v2): el único trigger de `expediente_notas` es `trg_calcular_imc_expediente`, BEFORE INSERT OR UPDATE FOR EACH ROW, que llama a `calcular_imc_signos_vitales()` (md5 `1b9ad49a…`). Corre en **todo** INSERT/UPDATE y recalcula `imc := ROUND(peso_kg / (talla_cm/100)², 2)` **sólo si** `peso_kg` y `talla_cm` no son NULL y la talla es mayor que 0. Si no, deja el `imc` que venga.
  - Nota 1013: peso, talla e imc NULL, así que no recalcula y el valor no cambia.
  - En general puede diferir en filas escritas antes de que existiera el trigger, o si la fórmula cambia en el futuro.
- **`citas.estado` es `text` sin CHECK.** Estados vivos: agendada 6, cancelada 6, completada 1, confirmada 16, en_curso 4, en_espera 2, solicitada 2.
  - Una cita `completada` puede volver a otro estado por UPDATE directo (`citas_update_medico`, `citas_update_admin_clinica`, `Admin ve citas de su pais` ALL) o por `actualizar_estado_cita` (md5 `3ff69763…`), cuyo único chequeo de `completada` es la lista de valores válidos.
  - Trigger vigente: `trg_exigir_nota_al_completar` → `private.exigir_nota_al_completar()` (md5 `102adac580dfb08ed65158f065a98b3e`), que usa `private.cita_tiene_nota(bigint)` (md5 `6ea1318eddf06bb33db2545c9ab2233a`).
- **Gate de cuenta activa** (v2):
  - `private.exigir_empresa_activa()` (md5 `d62cc5a3…`, mig 326) sólo mira `cuentas_proveedor`: 42501 `Cuenta proveedora inactiva` o `Empresa proveedora no activa`. Para quien no es proveedor no hace nada. Hoy hay 0 médicos con cuenta de proveedor.
  - Para médicos, el gate de cuenta es `perfiles.activo` (mig 315), que se aplica a través de `private.tiene_rol()` → `private.rol_usuario()` (`… WHERE id = auth.uid() AND activo IS TRUE`). Un médico inactivo resuelve rol NULL y `tiene_rol(['medico'])` da false. Así gatean `emitir_receta` (PR002) y `crear_orden_examen_medico` (EX002). Hoy hay 0 médicos inactivos.
  - `medicos.activo` existe pero sólo lo usan el directorio y la búsqueda (migs 182–185, 299, 307): no es gate de cuenta.
- **`examenes`**: 20 filas; completado 7 (los 7 **liberados**), pendiente 8, recibida 5. `authenticated` = `rdm` (SELECT, DELETE, MAINTAIN) + UPDATE por columna en `estado`, `fecha_resultado`, `resultados`, `archivo_url`. El resultado lo escribe el front (`useLaboratorio.ts:157-162`); liberar/revertir lo tocan sólo en sus columnas.
- **`ordenes_examen`**: 7 filas; `authenticated` = `rdm`.
- **FK** `signos_vitales_consulta_id_fkey`: `FOREIGN KEY (consulta_id) REFERENCES expediente_notas(id) ON DELETE CASCADE` (0 filas ligadas).
- **Storage** `resultados-examenes`: 6 objetos. `resultados_scoped_update` permite sobrescribir; `resultados_scoped_delete` protege sólo objetos referenciados por `examenes.archivo_url` y `examen_adjuntos`. El front sube con `upsert: true` (`useLaboratorio.ts:140`).
- **Permiso** `resultados_cargar`: `laboratorio_clinico/admin` y `laboratorio_clinico/tecnico` (la UI lo usa en `LabOrdenesPage.tsx:34`).
- **Portal paciente**: no muestra notas (ningún hook de `src/webapp` lee `expediente_notas`). Los exámenes llegan por `rpc('paciente_examenes')` (`useWebAppExamenes.ts:21`, su único consumidor en `src/`, `supabase/functions/` y `api/`), que ya devuelve `en_revision`.
- **`paciente_examenes()` sin dependientes** (v2):
  - `pg_depend` con `refobjid` = la función devuelve 0 filas.
  - 0 vistas, 0 matviews y 0 policies la mencionan.
  - Las 3 funciones cuyo `prosrc` matchea `ILIKE '%paciente_examenes%'` (`notificar_orden_lab`, `liberar_examen_al_paciente`, `liberar_orden_al_paciente`) son falsos positivos: el `_` del ILIKE matchea la `/` de la URL `'/paciente/examenes'`. Ninguna la llama.
  - ACL actual: `{postgres=X, authenticated=X, service_role=X}` (anon y PUBLIC sin EXECUTE; P740 lo ejercita).
- **CRLF** (v2): el `prosrc` de `liberar_examen_al_paciente` tiene 27 `\r` y 27 `\n` (todas las líneas en CRLF). md5 exacto `7c980b20f713d0cf49e7235da30838e1`; md5 del mismo texto sin `\r`: `51d4bbfdef169a16271a49ea0d218cc2`. Los cuerpos de `liberar_orden_al_paciente`, `revertir_liberacion_examen` y `paciente_examenes` no tienen `\r`.
- **Nombres libres**: `expediente_notas_revisiones`, `examen_revisiones`, `examen_liberacion_eventos`, `corregir_nota_consulta`, `corregir_resultado_examen`, columnas `updated_at/updated_by/cerrada_at/corregida_at` en `expediente_notas`. **Prefijo `NT0` sin uso** (grep sql/ts/tsx/py). Próximos antes de P4: probe **P885**, mig **334**, errcode **EX023**.

---

## Mecanismo común: la "llave" de corrección

Los triggers de congelamiento bloquean **a todos** (también a `postgres` y a las funciones DEFINER), salvo que la transacción lleve una llave puesta **por la RPC de corrección** o por el trigger de cierre, con `set_config(..., true)` (local a la transacción) y atada al id de la fila:

- notas: `ezpay.nota_llave = 'corregir:<nota_id>'` o `'cerrar:<nota_id>'`; motivo en `ezpay.nota_motivo`.
- resultados: `ezpay.examen_llave = 'corregir:<examen_id>'`.

El cliente no puede fijar esas GUC: PostgREST sólo expone funciones de los esquemas publicados y `set_config` vive en `pg_catalog`. Cada RPC limpia su llave antes de devolver. **[spec]**

---

## MIG 334 — Notas (D1, D2, D3, D4, D9, D10 de `expediente_notas`)

### 334.1 Objetos nuevos

**Columnas en `expediente_notas`** (D3, más dos de control **[spec]**):
```
updated_at   timestamptz NOT NULL DEFAULT now()   -- backfill = created_at antes de crear triggers
updated_by   uuid NULL                             -- auth.uid() del último UPDATE (NULL = sistema)
cerrada_at   timestamptz NULL                      -- se fija al completar la cita; NO se borra si la cita vuelve atrás
corregida_at timestamptz NULL                      -- última corrección por RPC (marca "corregida", R2: solo el dato)
```

**Tabla `public.expediente_notas_revisiones`** (append-only):
```
id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY
nota_id          integer NOT NULL REFERENCES public.expediente_notas(id) ON DELETE RESTRICT
paciente_id      integer NOT NULL      -- copia de la nota (para RLS)
medico_id        uuid    NOT NULL      -- autor de la nota (para RLS)
revision         integer NOT NULL      -- 1, 2, 3… por nota
tipo             text    NOT NULL CHECK (tipo IN ('edicion','correccion'))
motivo           text    NULL  CHECK (tipo = 'edicion' OR (motivo IS NOT NULL AND btrim(motivo) <> ''))
version_anterior jsonb   NOT NULL      -- to_jsonb(OLD) completo (todas las columnas, imc incluido)
editado_por      uuid    NULL          -- auth.uid(); NULL si fue el sistema
editado_at       timestamptz NOT NULL DEFAULT now()
UNIQUE (nota_id, revision)   -- su índice sirve también para nota_id
INDEX (paciente_id)          -- idx_exp_rev_paciente
```
- Índices: el UNIQUE `(nota_id, revision)` hace de índice para `nota_id` (es su columna inicial), así que no se crea uno aparte. El único índice extra es `idx_exp_rev_paciente (paciente_id)`.
- RLS **ENABLE + FORCE**.
- Policy única `exp_rev_select` FOR SELECT TO authenticated USING
  `(medico_id = auth.uid()) OR private.es_medico_de(paciente_id::bigint) OR private.medico_atiende_paciente(paciente_id::bigint) OR COALESCE(private.medico_es_de_mi_clinica(medico_id), false) OR private.tiene_rol(ARRAY['super_admin'])`
  (D2: autor, médicos tratantes, admin clínica, super_admin; el paciente no).
- Sin policies INSERT/UPDATE/DELETE: la escribe sólo el trigger (DEFINER, owner `postgres`, que ignora la RLS como `examen_adjuntos`).
- GRANTs: `REVOKE ALL ... FROM PUBLIC, anon, authenticated`; `GRANT SELECT TO authenticated`; `GRANT SELECT, INSERT, UPDATE, DELETE TO service_role` (regla del 30-oct). El append-only lo garantiza el trigger del punto 334.2.c, también para `service_role`.

### 334.2 Triggers y funciones nuevas (todas `SECURITY DEFINER`, `SET search_path = ''`, EXECUTE sólo `postgres` salvo la RPC)

**a) `private.expediente_notas_guardia()` — `trg_expediente_notas_guardia` BEFORE INSERT OR UPDATE ON expediente_notas FOR EACH ROW.**
Corre después de `trg_calcular_imc_expediente` (orden alfabético: `c` < `e`), así ve el IMC ya recalculado.

- **INSERT**, en este orden:
  1. **Integridad nota↔cita (C2)**: si `NEW.cita_id` no es NULL, se lee la cita (`SELECT c.medico_id, c.paciente_id, c.estado FROM public.citas c WHERE c.id = NEW.cita_id`). Si no existe, o `c.medico_id IS DISTINCT FROM NEW.medico_id`, o `c.paciente_id IS DISTINCT FROM NEW.paciente_id::bigint` → **NT010** `La nota no corresponde a la cita`. Aplica a todos, `postgres` incluido.
     - Una cita con `medico_id` NULL no admite nota (fail-closed). Hoy son las 5 de junio, sin notas; ver casos borde.
  2. `NEW.created_at := now()` (R5); `NEW.updated_at := NEW.created_at`; `NEW.updated_by := auth.uid()`.
  3. `NEW.corregida_at := NULL`.
  4. `NEW.cerrada_at := CASE WHEN NEW.cita_id IS NULL THEN now() WHEN c.estado = 'completada' THEN now() ELSE NULL END`.
     - Nota sin cita = cerrada desde el nacimiento (R1).
     - Nota sobre cita ya completada = cerrada desde el nacimiento (C1): el trigger de cierre es AFTER UPDATE de la cita y nunca la alcanzaría.
- **UPDATE**, en este orden:
  1. Si cambia `paciente_id`, `cita_id`, `medico_id` o `created_at` → **NT007** `La nota no permite cambiar paciente, cita, médico ni fecha de creación` (para todos, D3). Con eso la integridad del punto INSERT.1 se mantiene sin volver a chequearla.
  2. Si cambia `cerrada_at` y la llave no es `cerrar:<OLD.id>`, o cambia `corregida_at` y la llave no es `corregir:<OLD.id>` → **NT009** `Campo de control de la nota reservado al sistema`.
  3. Con la llave `cerrar:<OLD.id>` (el cierre), `NEW.imc := OLD.imc` y, si algo más que `cerrada_at` difiere de OLD → **NT009**. **[spec, C3]** El cierre sólo pone la fecha de cierre y no recalcula el IMC.
  4. Si `OLD.cerrada_at IS NOT NULL` y la llave no es `corregir:<OLD.id>` → **NT006** `La nota está cerrada: solo se puede corregir con motivo`.
  5. Si el contenido cambió → INSERT en `expediente_notas_revisiones` con:
     - `nota_id=OLD.id`, `paciente_id`, `medico_id`;
     - `revision = COALESCE(max(revision),0)+1`;
     - `tipo = CASE WHEN llave = 'corregir:'||OLD.id THEN 'correccion' ELSE 'edicion' END`;
     - `motivo = NULLIF(current_setting('ezpay.nota_motivo', true), '')` (sólo en corrección);
     - `version_anterior = to_jsonb(OLD)`, `editado_por = auth.uid()`.
     - "Contenido" = `to_jsonb(OLD) - ARRAY['updated_at','updated_by','cerrada_at','corregida_at','imc']`, comparado con el mismo recorte de NEW. **`imc` se excluye por ser derivado (C3)**: su recálculo no genera revisiones espurias. El valor previo queda igual en `version_anterior`, que guarda la fila completa.
  6. `NEW.updated_at := now()`; `NEW.updated_by := auth.uid()`.
  - Un UPDATE que sólo toca `cerrada_at` (el cierre) no genera revisión.

**b) `private.cerrar_nota_al_completar()` — `trg_cerrar_nota_al_completar` AFTER UPDATE OF estado ON citas FOR EACH ROW WHEN (NEW.estado = 'completada' AND OLD.estado IS DISTINCT FROM 'completada').**
1. `set_config('ezpay.nota_llave', 'cerrar:' || n.id, true)` para la nota de la cita (hay a lo sumo una por el UNIQUE `expediente_notas_una_por_cita`).
2. `UPDATE expediente_notas SET cerrada_at = now() WHERE cita_id = NEW.id AND cerrada_at IS NULL`.
3. `set_config('ezpay.nota_llave', '', true)`.
- **No toca** `private.exigir_nota_al_completar()` (PE001), que es BEFORE y sigue exigiendo la nota antes de completar.

**c) `private.revision_nota_inmutable()` — `trg_exp_rev_inmutable` BEFORE UPDATE OR DELETE ON expediente_notas_revisiones.**
- Siempre `RAISE` **NT008** `Las revisiones de la nota son inmutables`.
- Además `REVOKE TRUNCATE` (nadie salvo `postgres` lo tiene).

**d) RPC `public.corregir_nota_consulta(p_nota_id integer, p_motivo text, p_motivo_consulta text, p_subjetivo text, p_objetivo text, p_analisis text, p_plan text, p_diagnostico text) RETURNS jsonb`**
- `SECURITY DEFINER`, `SET search_path = ''`. EXECUTE sólo a `authenticated`; REVOKE de PUBLIC, anon y service_role (como las RPCs de la 332).
- Los 6 textos son la **versión nueva completa** de los campos SOAP y diagnóstico (el front manda los 6 siempre).
- Orden de gates (C5 v3): sesión → rol médico con cuenta activa → pertenencia. **Sin `exigir_empresa_activa`**: corregir una nota es una acción clínica, y su gate de cuenta es `perfiles.activo` (mig 315). El estado de una empresa proveedora no afecta las acciones clínicas de un médico que además tenga cuenta de proveedor (doble rol). `corregir_resultado_examen` sí conserva `exigir_empresa_activa`, porque esa es una acción del laboratorio.

1. `auth.uid()` NULL → **NT001** `No autorizado: inicie sesión`.
2. `NOT COALESCE(private.tiene_rol(ARRAY['medico']), false)` → **NT011** `No autorizado: solo un médico con cuenta activa puede corregir notas`. Es el gate de cuenta activa **del médico** (mig 315: `perfiles.activo IS TRUE`), con el mismo criterio que PR002 y EX002. Un usuario que es sólo proveedor también cae acá.
3. `SELECT … FOR UPDATE` de la nota. Si no existe o `medico_id <> auth.uid()` → **NT002** `No autorizado: solo el médico autor puede corregir la nota` (D2; mismo código para "no existe", así no se revela la existencia).
4. `cerrada_at IS NULL` → **NT003** `La nota todavía no está cerrada: guárdela normalmente`.
5. `v_motivo := btrim(p_motivo)`; vacío, NULL o de más de 500 caracteres → **NT004** `El motivo de la corrección es obligatorio (máximo 500 caracteres)`.
6. Si los 6 campos nuevos son `IS NOT DISTINCT FROM` los actuales → **NT005** `La corrección no cambia ningún campo de la nota`.
7. `set_config('ezpay.nota_llave','corregir:'||id,true)`; `set_config('ezpay.nota_motivo', v_motivo, true)`.
8. `UPDATE expediente_notas SET motivo_consulta, subjetivo, objetivo, analisis, plan, diagnostico = <nuevos>, corregida_at = now() WHERE id = p_nota_id` (el trigger guarda la revisión `correccion` con el motivo).
9. Limpia las dos llaves. Devuelve `{nota_id, revision, corregida_at}`.

### 334.3 Funciones existentes que se modifican
Ninguna. Se verifican intactas como precondición y en el autochequeo:

| Función | md5 |
|---|---|
| `private.exigir_nota_al_completar()` | `102adac580dfb08ed65158f065a98b3e` |
| `private.cita_tiene_nota(bigint)` | `6ea1318eddf06bb33db2545c9ab2233a` |
| `calcular_imc_signos_vitales()` | `1b9ad49a5cd1464c54d9a211e5763532` |
| `contexto_ia_paciente(bigint)` | `1eaf84a3475dfdfc3845d68ce2406fbb` |
| `obtener_contexto_visita(bigint)` | `24c3825b9c8fc6d172f8963191025097` |
| `actualizar_estado_cita(bigint,text)` | `3ff6976362482995bd17cb2322bcc082` |
| `private.exigir_empresa_activa()` | `d62cc5a3c6edf0aaf48488e59a8d1e9b` |

Si alguno no coincide, la migración **aborta** antes de tocar nada.

### 334.4 Policies y grants que se dropean o revocan
- `DROP POLICY exp_superadmin_all` (texto actual: `FOR ALL TO authenticated USING private.tiene_rol(ARRAY['super_admin'::text]) WITH CHECK private.tiene_rol(ARRAY['super_admin'::text])`) → se crean `exp_superadmin_select`, `exp_superadmin_insert` y `exp_superadmin_update` con la misma expresión, **sin DELETE** (D9). En notas cerradas el UPDATE del super_admin igual cae en NT006.
- `exp_update_medico` se **mantiene** (edición libre de notas abiertas, D1); el trigger se encarga de lo cerrado y de lo congelado.
- FK: `ALTER TABLE signos_vitales DROP CONSTRAINT signos_vitales_consulta_id_fkey` y `ADD CONSTRAINT signos_vitales_consulta_id_fkey FOREIGN KEY (consulta_id) REFERENCES expediente_notas(id) ON DELETE RESTRICT` (D9; 0 filas ligadas, no hay que validar datos).
- `REVOKE DELETE, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON expediente_notas FROM authenticated, anon, PUBLIC` (D9, D10, R4).
- Queda: `authenticated` = SELECT, INSERT, UPDATE.

### 334.5 Backfill (sin revisiones, D12)
- Antes de crear los triggers:
  - `UPDATE expediente_notas SET updated_at = created_at`.
  - `UPDATE expediente_notas SET cerrada_at = now() WHERE cita_id IS NULL OR cita_id IN (SELECT id FROM citas WHERE estado = 'completada')` (hoy 0 filas: la nota 1013 es de una cita `en_curso`).
- Precondición: 0 notas que violen la integridad nota↔cita (hoy 0: la 1013 cumple). Si hay alguna, la migración aborta: el guardia sólo la chequea en el INSERT y una fila vieja mala quedaría congelada por NT007.
- El autochequeo exige que **no quede** ninguna nota con cita completada y `cerrada_at` NULL.

### 334.6 Autochequeo `MIG334 AUTOCHEQUEO FALLA`
- Las 4 columnas nuevas existen, con su tipo y nulabilidad.
- La tabla de revisiones existe, con RLS y FORCE, exactamente 1 policy (SELECT) y el DDL de arriba (FK `confdeltype='r'`, UNIQUE, CHECK).
- Grants exactos de la tabla nueva: authenticated `{SELECT}`, service_role `{SELECT,INSERT,UPDATE,DELETE}`, anon y PUBLIC nada.
- 4 triggers presentes y habilitados (`trg_expediente_notas_guardia`, `trg_cerrar_nota_al_completar`, `trg_exp_rev_inmutable`, más `trg_exigir_nota_al_completar` y `trg_calcular_imc_expediente` intactos).
- La RPC tiene firma única, es DEFINER, con `search_path=""`, y su EXECUTE es `{authenticated, postgres}`.
- Las 3 funciones privadas tienen EXECUTE `{postgres}`.
- Policies de `expediente_notas`: el conjunto exacto por nombre y comando (sin ALL, sin DELETE).
- Grants de `expediente_notas`: authenticated `{INSERT,SELECT,UPDATE}`, sin MAINTAIN/TRUNCATE/TRIGGER/REFERENCES/DELETE.
- FK de signos vitales con `confdeltype='r'`.
- Las 7 funciones del punto 334.3 con md5 igual.
- 0 notas con cita completada y `cerrada_at` NULL. 0 notas con integridad nota↔cita rota.

### 334.7 Rollback (`334_rollback.sql`)
Deshace:
- los 3 triggers, las 3 funciones privadas y la RPC;
- `DROP TABLE expediente_notas_revisiones`;
- `DROP COLUMN updated_at, updated_by, cerrada_at, corregida_at`;
- recrea `exp_superadmin_all` (texto exacto) y borra las 3 policies nuevas;
- FK de signos vitales de vuelta a CASCADE;
- `GRANT DELETE, TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON expediente_notas TO authenticated`.

**No restaura:** las revisiones acumuladas (se pierden con el DROP, que es el costo de volver atrás) ni el contenido de las notas corregidas (queda la última versión). Tiene su propio autochequeo contra el estado previo.

---

## MIG 335 — Resultados, storage y eventos de liberación (D5, D6, D7, D10 de `examenes`)

### 335.1 Objetos nuevos

**Tabla `public.examen_revisiones`** (append-only):
```
id                        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY
examen_id                 integer NOT NULL REFERENCES public.examenes(id) ON DELETE RESTRICT
laboratorio_id            uuid    NOT NULL                    -- copia para RLS
revision                  integer NOT NULL
resultados_anterior       text    NULL
archivo_url_anterior      text    NULL
fecha_resultado_anterior  date    NULL
liberado_al_corregir      boolean NOT NULL
motivo                    text    NOT NULL CHECK (btrim(motivo) <> '')
corregido_por             uuid    NOT NULL
corregido_at              timestamptz NOT NULL DEFAULT now()
UNIQUE (examen_id, revision)
INDEX (examen_id), INDEX (archivo_url_anterior)
```

**Tabla `public.examen_liberacion_eventos`** (append-only, D7):
```
id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY
examen_id    integer NOT NULL REFERENCES public.examenes(id) ON DELETE RESTRICT
evento       text    NOT NULL CHECK (evento IN ('liberado','revertido'))
via          text    NOT NULL CHECK (via IN ('examen','orden'))
orden_id     uuid    NULL
actor        uuid    NOT NULL
ocurrido_at  timestamptz NOT NULL DEFAULT now()
INDEX (examen_id)
```
- Las dos con RLS **ENABLE + FORCE**.
- Una policy SELECT cada una, TO authenticated USING `private.puede_ver_historial_examen(examen_id)` (helper nuevo). Lo ven lab dueño, médico del examen o tratante, admin clínica y super_admin; el paciente no (R3).
- Sin INSERT/UPDATE/DELETE.
- GRANTs: authenticated `SELECT`; service_role `SELECT, INSERT, UPDATE, DELETE`; anon y PUBLIC nada.
- Append-only por trigger (punto 335.2.d).

### 335.2 Funciones y triggers nuevos (DEFINER, `search_path = ''`)

**a) `private.puede_ver_historial_examen(integer) RETURNS boolean STABLE`** — EXECUTE a `authenticated` (lo evalúa la policy).
- Es `private.puede_ver_examen` **sin** la rama del paciente: médico del examen, médico tratante, admin de la clínica del examen, laboratorio dueño y super_admin (R3).
- `COALESCE(..., false)`.

**b) `private.examenes_resultado_congelado()` — `trg_examenes_resultado_congelado` BEFORE UPDATE OF resultados, archivo_url, fecha_resultado, estado ON examenes.**
1. Si `OLD.estado = 'completado'` y `NEW.estado IS DISTINCT FROM OLD.estado` → **EX032** `Un examen completado no puede volver a un estado anterior` (para todos, D5).
2. Si `OLD.estado = 'completado'` y cambia `resultados`, `archivo_url` o `fecha_resultado`, y `current_setting('ezpay.examen_llave', true)` no es `'corregir:'||OLD.id` → **EX031** `El resultado de un examen completado solo se corrige con motivo`.
- No toca las columnas de liberación: liberar y revertir no disparan este trigger.

**c) `private.path_resultado_referenciado(text) RETURNS boolean STABLE`** — EXECUTE a `authenticated` (lo usa la policy de storage).
- `true` si el path aparece en:
  - `examen_adjuntos.storage_path`;
  - `examenes.archivo_url`, con la normalización actual `COALESCE(NULLIF(split_part(x,'/resultados-examenes/',2),''), x)`;
  - `examen_revisiones.archivo_url_anterior`, normalizado igual.
- Es DEFINER para que la policy no dependa de que el caller pueda leer `examen_revisiones` (lección de la mig 284).

**d) `private.historial_examen_inmutable()`** — triggers `trg_examen_rev_inmutable` y `trg_examen_lib_inmutable`, BEFORE UPDATE OR DELETE, en las dos tablas nuevas.
- Siempre **EX033** `Las revisiones y eventos de exámenes son inmutables`.

**e) `private.notificar_resultado_corregido(integer) RETURNS void`** — EXECUTE sólo `postgres`, la llama la RPC.
- **Nueva, no se reusa `notificar_resultado_examen`**: su gate exige que el caller sea el laboratorio, su texto dice "listo" y no notifica al paciente.
- Sin PHI (P412/P413): ni tipo, ni resultado, ni nombre.
  - Médico (si `medico_id` no es NULL): `notificaciones` con `tipo='examen_resultado'`, título `Resultado de examen corregido`, mensaje `El laboratorio corrigió un resultado de examen que ya estaba liberado.` y `accion_url` con la misma regla que `notificar_resultado_examen` (`/medico/pacientes/<id>/detalle`, o `/medico/citas` si no hay paciente). `metadata {examen_id, paciente_id, corregido: true}`. Push con `private.push_notificar('notificaciones', id)`.
  - Paciente (si `paciente_id` no es NULL): `notificaciones_pacientes` con `tipo='examen'`, título `Resultado de examen corregido`, mensaje `Se corrigió un resultado de examen que ya podías ver. Revísalo en tu portal.` y `accion_url '/paciente/examenes'`. Push igual.

**f) RPC `public.corregir_resultado_examen(p_examen_id integer, p_motivo text, p_resultados text, p_archivo_path text DEFAULT NULL) RETURNS jsonb`**
- EXECUTE sólo a `authenticated`.
1. `auth.uid()` NULL → **EX023** `No autorizado: inicie sesión`.
2. `PERFORM private.exigir_empresa_activa()` (42501 si la cuenta o la empresa no están activas).
3. `SELECT … FOR UPDATE` del examen; si no existe o `laboratorio_id IS DISTINCT FROM mi_empresa_proveedor()` → **EX024** `No autorizado: el examen no es de su laboratorio`.
4. `NOT COALESCE(private.tiene_permiso('resultados_cargar'), false)` → **EX025** `No autorizado: no tiene permiso para cargar resultados`.
5. `estado <> 'completado'` → **EX026** `El examen no está completado: cargue el resultado normalmente`.
6. Motivo vacío o de más de 500 → **EX027** `El motivo de la corrección es obligatorio (máximo 500 caracteres)`.
7. `v_res := NULLIF(btrim(p_resultados), '')`; `v_path := NULLIF(btrim(p_archivo_path), '')`.
   - Si `v_path` no es NULL y no empieza con `<laboratorio_id>/`, o es igual a `archivo_url`, o `private.path_resultado_referenciado(v_path)` → **EX029** `El archivo corregido debe ser un archivo nuevo de su laboratorio`.
   - Si no existe en `storage.objects` (bucket `resultados-examenes`) → **EX030** `El archivo corregido no existe en el almacenamiento`.
8. `v_arch := COALESCE(v_path, archivo_url)`. Si `v_res` y `v_arch` son NULL → **EX034** `El resultado corregido no puede quedar vacío`. Si ninguno cambia respecto de lo vigente → **EX028** `La corrección no cambia el resultado`.
9. INSERT en `examen_revisiones` con los valores **anteriores**, `revision = max+1`, `liberado_al_corregir = liberado_al_paciente`, `motivo` y `corregido_por = auth.uid()`.
10. `set_config('ezpay.examen_llave','corregir:'||id,true)`; `UPDATE examenes SET resultados = v_res, archivo_url = v_arch`. **`fecha_resultado` no cambia (R6)**: la fecha de la corrección queda en `examen_revisiones.corregido_at`. Limpia la llave.
11. Si estaba liberado: `BEGIN PERFORM private.notificar_resultado_corregido(id); EXCEPTION WHEN OTHERS THEN RAISE WARNING … END;` (best-effort, como la 332).
12. Devuelve `{examen_id, revision, notificado}`.

### 335.3 Funciones existentes que se modifican (precondición md5, aborta si no coincide)
| Función | md5 actual | Cambio |
|---|---|---|
| `liberar_examen_al_paciente(integer)` | `7c980b20f713d0cf49e7235da30838e1` (prosrc en CRLF, 27 `\r`) | Tras el UPDATE: `INSERT examen_liberacion_eventos (examen_id, 'liberado', 'examen', NULL, auth.uid())`. En el no-op `ya_liberado` no hay evento. El resto queda igual. El cuerpo nuevo va en LF. |
| `liberar_orden_al_paciente(uuid)` | `96a54d314911a439af77e426ebe46611` | El CTE `upd` devuelve `e.id`; INSERT de un evento `'liberado','orden',p_orden_id` por fila liberada. |
| `revertir_liberacion_examen(integer)` | `4a7f4912f3330543d2d7a47b2a06fbc6` | Tras el UPDATE: evento `'revertido','examen'`. En el no-op, nada. |
| `paciente_examenes()` | `a14ea485045b28883d81a0dd9fe7cd83` | **DROP + CREATE** (cambia el `RETURNS TABLE`). Ver el detalle abajo. |

Detalle de `paciente_examenes()`:
- Se agrega la columna final `corregido boolean` = `liberado_al_paciente AND EXISTS (examen_revisiones del examen)`. El resto de las columnas y el `CASE` de ocultamiento quedan idénticos.
- El DROP es seguro: 0 dependientes en `pg_depend`, vistas, matviews, policies o cuerpos de funciones (medido, §0). El único consumidor es `useWebAppExamenes.ts:21`.
- Tras el CREATE, `REVOKE ALL ON FUNCTION public.paciente_examenes() FROM PUBLIC, anon` explícito: una función nueva nace con EXECUTE a PUBLIC y con los default privileges de Supabase. Después `GRANT EXECUTE … TO authenticated, service_role`. La ACL queda idéntica a la actual (`postgres`, `authenticated`, `service_role`); lo verifican el autochequeo y P740 (anon → 42501).

Intactas, verificadas por md5: `notificar_resultado_examen` `33a7a110…`, `notificar_orden_lab` `59fafc85…`, `private.puede_ver_examen` `2b815087…`, `registrar_examen_adjunto` `245fb666…`, `contexto_ia_paciente` `1eaf84a3…`, `private.examenes_congelar_identidad` `f0ff903d…`, `crear_orden_examen_medico` `79a99458…` y `crear_orden_examen_walkin` `434d1223…`.

### 335.4 Policies y grants que se dropean o revocan
- `DROP POLICY resultados_scoped_update ON storage.objects`. Texto actual: FOR UPDATE TO authenticated, USING y CHECK `bucket_id = 'resultados-examenes' AND (split_part(name,'/',1) = mi_empresa_proveedor()::text OR private.tiene_rol(ARRAY['super_admin']))`.
- `resultados_scoped_delete`: DROP y CREATE. USING = `bucket_id = 'resultados-examenes' AND (split_part(name,'/',1) = mi_empresa_proveedor()::text OR private.tiene_rol(ARRAY['super_admin'])) AND NOT private.path_resultado_referenciado(name)`. Texto actual: el mismo prefijo más `NOT EXISTS (examen_adjuntos …) AND NOT EXISTS (examenes …)` inline.
- `REVOKE MAINTAIN ON examenes FROM authenticated, anon, PUBLIC` (D10). TRUNCATE, TRIGGER y REFERENCES ya los sacó la 333; se revocan igual, de forma explícita.
- Los grants por columna de la 332 no se tocan.

### 335.5 Autochequeo `MIG335 AUTOCHEQUEO FALLA`
- Tablas nuevas: DDL, RLS y FORCE, 1 policy SELECT, grants exactos, FKs `r`.
- Triggers presentes: `trg_examenes_resultado_congelado`, `trg_examen_rev_inmutable`, `trg_examen_lib_inmutable` y `trg_examenes_congelar_identidad` intacto.
- Funciones nuevas: DEFINER, `search_path=""` y EXECUTE exacto.
- Las 3 funciones modificadas tienen un md5 distinto del previo y contienen `examen_liberacion_eventos`.
- `paciente_examenes()`: firma única, `RETURNS` con `corregido`, `proacl` = `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}` exacto (anon y PUBLIC sin EXECUTE).
- Las 8 funciones intactas con md5 igual.
- En storage: no existe `resultados_scoped_update`; `resultados_scoped_delete` usa el helper.
- `examenes`: authenticated sin MAINTAIN; grants por columna iguales a los de la 332.

### 335.6 Rollback (`335_rollback.sql`)
Deshace:
- vuelve a crear las 4 funciones con su cuerpo previo exacto, capturado con `pg_get_functiondef` antes de aplicar (`tmp/p4_spec/q_defs.json`) y verificado por md5;
- borra los triggers, las funciones nuevas y las 2 tablas;
- recrea `resultados_scoped_update` y `resultados_scoped_delete` con su texto original;
- `GRANT MAINTAIN ON examenes TO authenticated`.

**Restauración con CRLF de `liberar_examen_al_paciente` (C6).** El archivo de rollback se queda en **LF**, como todo el repo. No se usa un archivo con CRLF adentro del cuerpo porque git/autocrlf o un editor lo normalizarían sin aviso, y tampoco un `E'…\r\n…'` de 27 líneas, que no se puede revisar. El mecanismo:
1. El cuerpo previo va en el archivo como literal dollar-quoted en LF, dentro de un `DO`: `v_body := $body$…$body$;`.
2. Precondición: `md5(v_body) = '51d4bbfdef169a16271a49ea0d218cc2'` (el md5 del `prosrc` original sin `\r`, medido). Si no coincide → `RAISE EXCEPTION 'ROLLBACK335: cuerpo LF de liberar_examen_al_paciente alterado'`.
3. `EXECUTE format('CREATE OR REPLACE FUNCTION public.liberar_examen_al_paciente(<firma exacta>) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO %L AS %L', '', replace(v_body, E'\n', E'\r\n'))`. Cabecera = la de `pg_get_functiondef` PRE, con los mismos nombres de parámetros, volatilidad y `proconfig`.
   - El `replace` es la inversa exacta porque en el original cada `\n` va precedido de `\r` (27 y 27) y no hay `\r` sueltos.
4. Autochequeo del rollback: `md5(prosrc) = '7c980b20f713d0cf49e7235da30838e1'` **exacto**, más `proacl`, `prosecdef` y `proconfig` iguales al snapshot PRE. Las otras 3 funciones vuelven con su md5 exacto (`96a54d31…`, `4a7f4912…`, `a14ea485…`), sin `\r`.

**No restaura:** las revisiones y eventos acumulados (se pierden) ni los resultados corregidos (queda la última versión). Autochequeo propio.

---

## MIG 336 — Cierre del DELETE directo (D8)

### 336.1 Policies y grants que se dropean o revocan
- `DROP POLICY examenes_laboratorio_delete` (FOR DELETE TO public USING `laboratorio_id = mi_empresa_proveedor()`).
- `DROP POLICY examenes_medico_delete` (FOR DELETE TO authenticated USING `medico_id = auth.uid()`).
- `DROP POLICY examenes_superadmin_delete` (FOR DELETE TO authenticated USING `private.tiene_rol(ARRAY['super_admin'])`).
- `DROP POLICY ordenes_lab_delete` (FOR DELETE TO public USING `laboratorio_id = mi_empresa_proveedor()`).
- `DROP POLICY ordenes_medico_delete` (FOR DELETE TO authenticated USING `medico_id = auth.uid()`).
- `REVOKE DELETE ON examenes, ordenes_examen FROM authenticated, anon, PUBLIC`.
- `REVOKE MAINTAIN ON ordenes_examen FROM authenticated, anon, PUBLIC` (R4).
- Quedan: `examenes` = SELECT + UPDATE por columna; `ordenes_examen` = SELECT.

### 336.2 Autochequeo `MIG336 AUTOCHEQUEO FALLA`
- 0 policies DELETE o ALL en las dos tablas.
- `has_table_privilege` DELETE y MAINTAIN false para authenticated y anon en las dos tablas; 0 entradas PUBLIC.
- Grants por columna de `examenes` intactos.
- Las RPCs de la 332 y las 3 de liberación con md5 igual al post-335.

### 336.3 Rollback
Recrea las 5 policies con su texto exacto y `GRANT DELETE ON examenes, ordenes_examen TO authenticated; GRANT MAINTAIN ON ordenes_examen TO authenticated`.

---

## Front (sin escribir código)

| Archivo:línea | Cambio |
|---|---|
| `src/hooks/useConsultas.ts:55-84` | `crearOActualizarConsulta` sigue igual para notas abiertas. El payload manda `cita_id`/`paciente_id` de la cita y `medico_id = user.id`: sobre una cita propia cumple NT010, y en el UPDATE no cambia nada congelado (NT007). Agregar `corregirNota(notaId, soap, motivo)` → `rpc('corregir_nota_consulta', …)`. Los errores NT y 42501 se muestran con `error.message` tal cual (mismo patrón que `mensajeErrorOrden`). |
| `src/hooks/useConsultas.ts:38-53` | `fetchConsultaPorCita` ya trae `select('*')`: incluye `cerrada_at` y `corregida_at`. Ajustar el tipo `ExpedienteNota` (`src/types`). |
| `src/pages/ConsultaPage.tsx:276-286` | Guardar `cerrada_at` y `corregida_at` de la nota cargada. |
| `src/pages/ConsultaPage.tsx:420` | **Solo si `cerrada_at` está presente** (C4: la base decide, no `cita.estado`), el botón pasa a **"Corregir nota"** y abre un modal con motivo obligatorio que llama a `corregirNota` (D4). Si no, "Guardar" como hoy. Si el estado de la pantalla quedó viejo y un "Guardar" choca con NT006, se muestra el mensaje y se recarga la nota. |
| `src/pages/ConsultaPage.tsx:326-329` | "Finalizar" no cambia: guarda con la nota todavía abierta y después completa la cita (PE001 pasa y el cierre pone `cerrada_at`). |
| `src/pages/PacienteDetallePage.tsx:201` (lista de notas) | Marca **"corregida"** si hay `corregida_at`, y acción "Ver historial" que lee `expediente_notas_revisiones` (la RLS limita a autor, tratantes, admin clínica y super_admin). |
| `src/laboratorio/hooks/useLaboratorio.ts:140` | `upsert: true` → **`upsert: false`** (D6). Va solo, en el paso 2 del orden. |
| `src/laboratorio/hooks/useLaboratorio.ts:151-176` | `subirResultado` sin cambios para los no completados. Agregar `corregirResultado(examenId, resultados, archivo?, motivo)`: si hay archivo, lo sube con `subirArchivo` (path nuevo con timestamp) y llama a `rpc('corregir_resultado_examen', …)`. EX y 42501 se muestran tal cual. |
| `src/laboratorio/pages/LabOrdenesPage.tsx:168-170` | Con `completado` y `puedeCargar` (`:34`), además de "Ver" aparece **"Corregir"** (D5). |
| `src/laboratorio/pages/LabOrdenesPage.tsx:198-231` | En modo corrección el textarea es editable, con campo de motivo obligatorio y botón "Enviar corrección". En modo "Ver" sigue de solo lectura. |
| `src/webapp/hooks/useWebAppExamenes.ts:23-34` | Mapear `corregido` desde `paciente_examenes`. |
| `src/webapp/pages/WebAppExamenes.tsx:58-61` | Badge **"corregido"** al lado del estado. Tipo `ExamenPaciente` en `src/webapp/types/webapp.types.ts`. |
| Portal paciente: notas | **Sin pantalla** (R2): solo el dato `corregida_at`. Mostrar notas al paciente queda en backlog. |

---

## Probes (desde P885)

Todas usan el molde de P866–P884: impersonación por `request.jwt.claims`, causa por SQLSTATE y SQLERRM exactos, sin filas creadas en los negativos, snapshot md5 de las tablas tocadas y restauración verificada. Para las notas se usan citas y notas **sembradas** por la probe (no la 1013).

**Patrón obligatorio: subtransacción descartable [spec, v2].** Las revisiones y los eventos son inmutables (NT008/EX033 también para `postgres`) y tienen FK RESTRICT hacia la nota o el examen. Una probe que genera una revisión o un evento **no puede limpiar con DELETE**: el DELETE de la revisión cae en NT008/EX033, y el de la nota o el examen padre en 23503. Por eso:
- toda acción que genere revisiones o eventos corre dentro de un sub-bloque `BEGIN … EXCEPTION WHEN SQLSTATE 'P0999' THEN … END`;
- el sub-bloque mide, guarda el veredicto en variables y termina con `RAISE EXCEPTION USING ERRCODE = 'P0999'` (centinela);
- el handler deshace la subtransacción completa (revisiones, eventos, notificaciones, cambios de fila), y fuera del bloque se verifica que el snapshot volvió a PRE.

No se agrega ninguna "llave de purga" a los triggers de inmutabilidad.

**334 (notas):**
| Probe | Qué prueba |
|---|---|
| P885 | Nota abierta: el médico edita → OK. 1 revisión `edicion` con `version_anterior` = la fila previa. `updated_by` = médico. |
| P886 | Congelados: UPDATE de `paciente_id`, `cita_id`, `medico_id` o `created_at` → NT007, como médico y como `postgres`. El INSERT con `created_at` en el pasado queda en `now()`. |
| P887 | Cierre: la cita pasa a `completada` → `cerrada_at` puesto y 0 revisiones nuevas. La cita vuelve a `en_curso` → `cerrada_at` se mantiene. UPDATE directo → NT006. |
| P888 | UPDATE directo sobre nota cerrada → NT006 para el autor, para super_admin y para `postgres` sin llave. |
| P889 | `corregir_nota_consulta` positivo: contenido nuevo, `corregida_at` puesto, 1 revisión `correccion` con motivo. |
| P890 | Rechazos por causa: NT001 sin sesión, NT002 otro médico / nota inexistente, NT003 nota abierta, NT004 motivo vacío / 501 caracteres, NT005 sin cambios. |
| P891 | Revisiones inmutables: UPDATE/DELETE como authenticated → 42501; como `postgres` → NT008. `cerrada_at` o `corregida_at` puestos por el cliente → NT009. |
| P892 | Visibilidad de revisiones: autor, médico tratante, admin clínica y super_admin ven; paciente y médico ajeno ven 0. |
| P893 | DELETE de nota: super_admin y autor → 42501 (sin grant). Como `postgres`, una nota con `signos_vitales` ligado → 23503 (RESTRICT). |
| P894 | Nota sin cita: INSERT con `cita_id` NULL → nace con `cerrada_at`; UPDATE directo → NT006; corrección por RPC OK. |
| P895 | PE001 intacto: completar sin nota → PE001; guardar + completar (flujo "Finalizar") → OK y nota cerrada. |
| P896 | Catálogo 334: todo lo del autochequeo 334.6 (tabla, grants, RLS, policies, triggers, funciones, FK, md5 intactos). |
| **P908** | **(C1)** INSERT de nota sobre una cita sembrada ya `completada` (el médico de la cita) → la nota nace con `cerrada_at`; UPDATE directo → NT006; corrección por RPC OK. Control: sobre una cita `en_curso` nace con `cerrada_at` NULL. |
| **P909** | **(C2)** El médico B inserta una nota en la cita del médico A → NT010 y 0 filas nuevas. También NT010: `paciente_id` distinto del de la cita (como médico A y como `postgres`), cita inexistente, y cita con `medico_id` NULL. Control: el médico A en su cita → OK. |
| **P910** | **(C5 v3)** Gate de cuenta en `corregir_nota_consulta`. **NT011** sin cambios para: autor con `perfiles.activo=false`, usuario que es sólo proveedor (sin rol médico), admin clínica y paciente. **Doble rol** (médico A activo que además es proveedor) corrige: (a1) con cuenta de proveedor inactiva → revisión 1; (a2) con cuenta activa en empresa no activa → revisión 2. En los dos estados, un control confirma que `exigir_empresa_activa` lo habría rechazado (42501). No se aísla del fixture PASIGN. Restaura perfil, cuentas y empresas, y verifica. |
| **P911** | **(C3)** IMC: nota sembrada con peso y talla, cuyo `imc` guardado difiere de la fórmula (escrito como `postgres` antes del trigger guardia, simulando una fila legacy). El cierre de la cita → 0 revisiones e `imc` igual al guardado. Una edición abierta que sólo cambia `subjetivo` → 1 revisión. |

**335 (resultados):**
| Probe | Qué prueba |
|---|---|
| P897 | Resultado congelado: lab dueño y super_admin UPDATE de `resultados`/`archivo_url`/`fecha_resultado` de un completado → EX031. `estado` hacia atrás → EX032 (también como `postgres`). Control: los no completados se siguen editando. |
| P898 | `corregir_resultado_examen` positivo sobre completado **no liberado**: revisión con los valores previos, `fecha_resultado` igual y 0 notificaciones. |
| P899 | Positivo sobre **liberado** con archivo nuevo: path nuevo vigente, revisión con el archivo viejo, 1 notificación al médico y 1 al paciente con texto exacto y sin tipo, resultado ni nombre. |
| P900 | Rechazos: EX023, EX024 (lab ajeno y médico), EX025 (recepción), EX026, EX027, EX028, EX029 (carpeta ajena / mismo path / ya referenciado), EX030, EX034 y 42501 (cuenta inactiva). |
| P901 | Revisiones y eventos inmutables: 42501 como authenticated; EX033 como `postgres`. |
| P902 | Eventos de liberación: liberar → 1 `liberado`; `ya_liberado` → 0; revertir → 1 `revertido`; liberar orden con N → N eventos `via='orden'`. |
| P903 | Storage: UPDATE (sobrescribir) de un objeto del lab → denegado. DELETE de un objeto referenciado por `examen_revisiones` → 0 filas. DELETE de uno no referenciado → OK. |
| P904 | `paciente_examenes`: `corregido` sólo después de corregir un liberado; `en_revision` igual que hoy. El paciente no ve `examen_revisiones` ni los eventos (0 filas). |
| P905 | Catálogo 335: autochequeo 335.5. |

**336 (DELETE):**
| Probe | Qué prueba |
|---|---|
| P906 | DELETE directo de `examenes` y de `ordenes_examen` como lab, médico y super_admin → 42501 sin filas. |
| P907 | Catálogo 336: sin policies ni grants DELETE/MAINTAIN; `postgres` sigue pudiendo borrar (fixtures sin historia). |

### Fixtures y probes existentes que cambian (C8)

Barrido de `tests/rls/probes_escritura.sql` (26.588 líneas, `tmp/p4_spec/c8_scan.py` → `c8_scan.txt`). Buscó cuatro cosas:
- INSERT en `expediente_notas` con `created_at` explícito;
- UPDATE de `paciente_id`/`cita_id`/`medico_id` de notas;
- UPDATE de `resultados`/`archivo_url`/`fecha_resultado`/`estado` sobre `examenes` completados;
- además, lo que choca con los otros cambios de P4: md5 de las funciones modificadas, grants/policies DELETE, y DELETE de exámenes con eventos.

El harness termina en `ROLLBACK` (línea 26588), pero cada probe verifica su restauración dentro de la transacción.

| Línea | Probe / fixture | Qué hace hoy | Con P4 | Ajuste (siempre restaurando) |
|---|---|---|---|---|
| — | — | INSERT en `expediente_notas` con `created_at` explícito | **0 casos** | — |
| — | — | UPDATE de `paciente_id`/`cita_id`/`medico_id` de notas | **0 casos**: el harness no hace ningún UPDATE ni DELETE de `expediente_notas` | — |
| 6965 | Setup de P412/P413 | UPDATE `resultados='PHISENTINEL_EVT4'` (+ `laboratorio_id`, `paciente_nombre`) sobre `lx_ex` | `lx_ex` = **examen 250, `completado` y liberado** (medido: la orden `e994fee0…` tiene 250–254, todos completados y liberados) → **EX031** con la 335 | Poner el sentinel con la llave, como hace la RPC: `set_config('ezpay.examen_llave','corregir:'||lx_ex,true)` en el mismo bloque y limpiarla al salir. Así no se cambia el examen elegido ni las probes P373–P377 que comparten `lx_ex`. Hoy el sentinel no se restaura dentro del harness (lo deshace el `ROLLBACK` final). Si se agrega una restauración, también va con la llave. |
| 24188–24300 | P874 (332, congelamiento) | Siembra `completado` (24188); lab UPDATE → `en_proceso` + resultados (24248); `postgres` → `completado` (24256); `liberar` (24271) y `revertir` (24282); DELETE del examen sembrado (24303) | 24248 → **EX032**; 24271/24282 generan 2 eventos y el DELETE de 24303 → **23503** (RESTRICT) | Sembrar como `en_proceso` (el control del lab corre sobre un no completado). Pasarlo a `completado` como `postgres` después del control. Liberar y revertir dentro de una **subtransacción descartable**. El DELETE de 24303 queda igual porque el examen ya no tiene eventos. |
| 24643 | P878 (332, "las 9 funciones previas sin cambios") | md5 exacto de 9 funciones: `liberar_examen_al_paciente` `7c980b20`, `liberar_orden_al_paciente` `96a54d31`, `revertir_liberacion_examen` `4a7f4912`, `paciente_examenes` `a14ea485` + 5 intactas | Las 4 primeras cambian con la 335 → **ROJO** | Actualizar esos 4 md5 a los post-335 (se miden en el dry-run A y se fijan en el mismo commit que la 335). Las otras 5 siguen igual. |
| 25330 / 25333 | P884 (333, catálogo) | Lista exacta de policies de `examenes` y de `ordenes_examen`, que incluye las 5 `*_delete` | Con la 336 → **ROJO** | Sacar las 5 policies DELETE de las listas esperadas (commit de la 336). |
| 25344 / 25347 | P884 | `has_table_privilege(authenticated)` en `examenes` = `DELETE,SELECT` y en `ordenes_examen` = `DELETE,SELECT` | Con la 336 → **ROJO** | Esperado = `SELECT` en las dos (commit de la 336). |
| 24936–25138 | P881 (333, DELETE por rol) | Lab, médico y super_admin borran `examenes`/`ordenes_examen` (esperado OK) | Con la 336 → 42501 | **Invertir**: esperado 42501 y 0 filas (commit de la 336). El resto de P881 (SELECT/UPDATE por rol) sobre exámenes `pendiente`/`en_proceso` no cambia. |
| 18867–19034 | P790–P795 (revertir liberación) | Siembra 4 exámenes `completado` liberados por INSERT; `revertir` (18942–19034) | El INSERT no dispara el congelamiento (es BEFORE UPDATE). Revertir escribe eventos. No hay DELETE de esos exámenes (los limpia el ROLLBACK final) | **Sin ajuste.** Si en el futuro se agrega una limpieza con DELETE, tiene que usar la subtransacción descartable. |
| 17193 / 17201 | P743 | `liberar` sobre un examen ajeno como anon y como authenticated sin relación (esperado: falla) | Sin evento, porque falla antes del UPDATE | **Sin ajuste.** |
| 19123 / 19127 | P796 (notificar resultado) | INSERT de 2 exámenes `completado` | Sólo INSERT; no los actualiza | **Sin ajuste.** |
| 11216 | Fixture de P511 | INSERT de un examen `completado` sin lab | Sólo INSERT | **Sin ajuste.** |
| 437 / 470 / 4772 | P9, P13, P269 | INSERT de nota sin `cita_id` | Nace cerrada (R1); no se la actualiza después; no hay NT010 porque no hay cita | **Sin ajuste.** Los veredictos miden si el INSERT pasa, y eso no cambia. |
| 15550–15631 | P678–P682 (PE001) | Nota en `v_con`, del mismo médico y paciente de la cita (cumple NT010); `v_con` → `completada` (15612); `v_ya` nace `completada` y se vuelve a completar (15631) | El cierre pone `cerrada_at` en la nota de `v_con`. En `v_ya` el WHEN del trigger no dispara (`completada`→`completada`) | **Sin ajuste.** |
| 16861 | P730 | Restaura el estado de una cita FO (sin nota) | No hay nota que cerrar | **Sin ajuste.** |
| 17091 | P740 | Anon → 42501 sobre `paciente_examenes()` | Tras el DROP + CREATE tiene que seguir dando 42501 | **Sin ajuste; es la guarda** del REVOKE explícito de la 335. |
| 6146–6211 | P373–P377 | UPDATE de `laboratorio_id`/`paciente_id`/`medico_id` de `lx_ex` | Esas columnas no están en el trigger de la 335 | **Sin ajuste.** |

Probes que el barrido nombra y no cambian: P26–P29, P33, P35, P36 (storage: leen o INSERTan objetos nuevos, no sobrescriben), P783–P789 (adjuntos: INSERT de objetos con `ON CONFLICT DO NOTHING`), y P866–P873, P875–P877, P879, P880, P882, P883 (cierran con `DELETE` de exámenes sembrados que no tienen eventos ni revisiones).

---

## Dry-run y orden de aplicación

**Dry-run por migración** (mismo procedimiento que la 332 y la 333):
1. Snapshot PRE: funciones, policies, grants de tabla y columna, triggers, conteos y md5 de filas.
2. La migración sola en `BEGIN … ROLLBACK`: el autochequeo pasa.
3. Harness A (migración inyectada + ajustes de fixtures de C8 de esa migración) en VERDE: 959 + N filas, 11 rojas de deuda, las nuevas OK, FX19 OK.
4. Harness B (migración + rollback): solo las probes que dependen de la migración en ROJO, y todas restauran.
5. Migración + rollback + snapshot dentro de una transacción = PRE, byte a byte. Para la 335 incluye `md5(prosrc)` de `liberar_examen_al_paciente` = `7c980b20…` (C6).
6. Guard 155 y P800 en PASA.

**Orden de aplicación** (C7: hoy no hay usuarios reales, así que no hay que esperar a que se actualice la PWA):
1. **334** → verificación independiente → commit → **front de notas** (Corregir nota, historial, marca).
2. **Front `upsert:false` solo** → **deploy a producción en Vercel** → verificación en prod, **antes de la 335**, de que la carga de un resultado nuevo funciona: lab QA, examen no completado, archivo nuevo, estado `completado` y archivo visible. Sin esa verificación en verde no se aplica la 335.
3. **335** → verificación → commit → **front de corrección de resultados y marca del paciente**.
4. **336** → verificación → commit (el front no borra, no hace falta deploy).

---

## Casos borde (resueltos o abiertos)

| Caso | Resolución |
|---|---|
| Nota con `cita_id` NULL | **Cerrada desde el INSERT** (R1): sin cita no hay evento de cierre, y el front no crea notas sin cita (`ConsultaPage.tsx:303` siempre manda `cita.id`). Hoy hay 0 notas sin cita. |
| Nota creada sobre una cita ya `completada` | **Cerrada desde el INSERT** (C1): el trigger de cierre es AFTER UPDATE de la cita y no la vería. P908. |
| Nota que no corresponde a su cita | **NT010** en el INSERT (C2), para todos. En el UPDATE, NT007 impide mover paciente, cita o médico. P909. |
| Cita con `medico_id` NULL | No admite nota (NT010, fail-closed). Son 5 citas de junio (27, 28, 29, 52 y 53) sin notas. El front siempre manda `medico_id = user.id`, así que ningún médico podría escribirla coherentemente. Si un flujo futuro asigna el médico al atender, primero actualiza `citas.medico_id`. |
| Cita que vuelve de `completada` a otro estado | **Existe hoy** (text sin CHECK, UPDATE directo y `actualizar_estado_cita`). Se resuelve con `cerrada_at` **pegajoso**: una vez cerrada, la nota no se reabre aunque la cita cambie. |
| IMC recalculado en cada UPDATE | Excluido de la comparación de "contenido cambió", y congelado en el cierre (C3). P911. |
| "Finalizar" = guardar y completar | No choca: el guardado ocurre con la nota abierta (revisión `edicion`), y después el cambio a `completada` pasa PE001 y el trigger AFTER cierra la nota. |
| PE001 y `cita_tiene_nota` | No se tocan (md5 verificado); P895 los ejercita. |
| Notificación de "resultado corregido" | Función privada **nueva** (`notificar_resultado_corregido`), llamada por la RPC en un sub-bloque protegido; sin PHI; sólo si ya estaba liberado. |
| Corrección con archivo nuevo | Path nuevo obligatorio (EX029), el objeto tiene que existir (EX030), y el archivo viejo queda referenciado por `examen_revisiones.archivo_url_anterior`, así que storage no lo deja borrar. |
| Lectores | `contexto_ia_paciente`, `obtener_contexto_visita` y `paciente_examenes` leen la fila vigente; ninguno lee las tablas de revisiones. `paciente_examenes` sólo agrega el booleano. |
| RESTRICT en `signos_vitales.consulta_id` | 0 filas ligadas en prod. Ningún fixture del harness usa `consulta_id` ni borra notas. Sin impacto previsto; P893 lo ejercita. |
| FK RESTRICT de revisiones/eventos hacia `examenes` y notas | Un paciente, una orden o una nota con historia ya no se pueden borrar (23503). Es coherente con la inmutabilidad y afecta el backlog D11. En el harness se resuelve con la subtransacción descartable. |

---

## Errcodes de P4 (C9)

| Código | Mensaje exacto | Dónde |
|---|---|---|
| NT001 | `No autorizado: inicie sesión` | `corregir_nota_consulta` |
| NT002 | `No autorizado: solo el médico autor puede corregir la nota` | `corregir_nota_consulta` (no existe o no es el autor) |
| NT003 | `La nota todavía no está cerrada: guárdela normalmente` | `corregir_nota_consulta` |
| NT004 | `El motivo de la corrección es obligatorio (máximo 500 caracteres)` | `corregir_nota_consulta` |
| NT005 | `La corrección no cambia ningún campo de la nota` | `corregir_nota_consulta` |
| NT006 | `La nota está cerrada: solo se puede corregir con motivo` | trigger guardia (UPDATE) |
| NT007 | `La nota no permite cambiar paciente, cita, médico ni fecha de creación` | trigger guardia (UPDATE) |
| NT008 | `Las revisiones de la nota son inmutables` | trigger de `expediente_notas_revisiones` |
| NT009 | `Campo de control de la nota reservado al sistema` | trigger guardia (UPDATE) |
| NT010 | `La nota no corresponde a la cita` | trigger guardia (INSERT) |
| NT011 | `No autorizado: solo un médico con cuenta activa puede corregir notas` | `corregir_nota_consulta` |
| EX023 | `No autorizado: inicie sesión` | `corregir_resultado_examen` |
| EX024 | `No autorizado: el examen no es de su laboratorio` | `corregir_resultado_examen` |
| EX025 | `No autorizado: no tiene permiso para cargar resultados` | `corregir_resultado_examen` |
| EX026 | `El examen no está completado: cargue el resultado normalmente` | `corregir_resultado_examen` |
| EX027 | `El motivo de la corrección es obligatorio (máximo 500 caracteres)` | `corregir_resultado_examen` |
| EX028 | `La corrección no cambia el resultado` | `corregir_resultado_examen` |
| EX029 | `El archivo corregido debe ser un archivo nuevo de su laboratorio` | `corregir_resultado_examen` |
| EX030 | `El archivo corregido no existe en el almacenamiento` | `corregir_resultado_examen` |
| EX031 | `El resultado de un examen completado solo se corrige con motivo` | trigger `trg_examenes_resultado_congelado` |
| EX032 | `Un examen completado no puede volver a un estado anterior` | trigger `trg_examenes_resultado_congelado` |
| EX033 | `Las revisiones y eventos de exámenes son inmutables` | triggers de `examen_revisiones` / `examen_liberacion_eventos` |
| EX034 | `El resultado corregido no puede quedar vacío` | `corregir_resultado_examen` |
| 42501 | mensajes de `private.exigir_empresa_activa()` (sin errcode propio) | sólo `corregir_resultado_examen` (C5 v3: no en notas) |

**Próximos libres después de P4:** probe **P912**, migración **337**, errcode **NT012** (notas), **EX035** (exámenes). Los demás prefijos no cambian: PA035, PR011, SV004, PE005, PC027 reservado a la familia PC.

---

## PREGUNTAS PARA OSCAR

Las 6 de la v1 están respondidas (R1–R6, ver CAMBIOS v2). No quedan preguntas abiertas que la spec no pueda resolver sola. Dos puntos de v2 quedan decididos por la spec y a la vista, por si Oscar quiere cambiarlos:
- **NT011** es un errcode nuevo (el pedido de C9 decía NT001–NT010). Separa "no es médico o su cuenta está inactiva" de "no es el autor", igual que PR002/EX002 frente a su chequeo de pertenencia.
- **Subtransacción descartable** en lugar de una llave de purga para los fixtures (ver Probes).

## RIESGOS

- **`upsert:true` en el bundle viejo:** Supabase exige la policy UPDATE para un `upload` con `upsert:true` aunque el objeto no exista. Si la 335 dropea `resultados_scoped_update` con el front viejo en producción, **las cargas de resultados fallan**. Lo mitiga el paso 2 (deploy + verificación en prod antes de la 335). Sin usuarios reales, no hay caché de PWA de terceros que esperar; un navegador de QA con el bundle viejo se resuelve recargando.
- **Los congelamientos aplican también a `postgres`:** fixtures que escriban resultados de completados o reviertan estados fallan. Están listados en C8 (setup P412/P413 en 6965 y P874). FX19 y el dry-run A lo confirman.
- **Historia inmutable + RESTRICT en el harness:** una probe nueva que genere revisiones o eventos y limpie con DELETE rompe su restauración (NT008/EX033/23503). La regla de la subtransacción descartable tiene que quedar escrita en el encabezado de la sección de probes P4 del harness.
- **La llave por GUC:** es segura mientras ningún cliente pueda ejecutar `set_config`. Una función nueva que la ponga mal abriría el congelamiento, así que las probes P888 y P897 prueban el UPDATE sin llave como `postgres`. El setup de P412/P413 usa la llave a propósito, dentro del harness y como `postgres`.
- **Rollback de la 335 y CRLF:** si el cuerpo LF del rollback se edita, la precondición `51d4bbfd…` aborta antes de tocar nada. Si el `replace` no reproduce el original, el autochequeo `7c980b20…` falla y la transacción no se confirma.
- **FK RESTRICT de revisiones y eventos:** bloquea el borrado en cascada de pacientes, órdenes y notas con historia. Hoy nadie borra (D8, D11), pero un super_admin que intente borrar un paciente va a recibir 23503.
- **Los 7 exámenes completados quedan congelados en el acto;** su corrección exige el front nuevo (paso 3).
- **Rollbacks con pérdida:** volver atrás la 334 o la 335 borra las revisiones y eventos acumulados. Conviene aplicar cada rollback sólo recién después de aplicar, o exportar antes esas tablas.
- **`paciente_examenes` se recrea (DROP + CREATE):** si los grants no quedan exactos, el portal del paciente pierde los exámenes o anon gana EXECUTE. Lo cubren el autochequeo (proacl exacto), P740 y P904.

---

## CAMBIOS v2

**Respuestas de Oscar incorporadas**
- **R1:** la nota sin cita nace cerrada. Queda como decisión en 334.2.a y en casos borde (sale de PREGUNTAS).
- **R2:** sólo el dato `corregida_at`, sin pantalla de notas para el paciente. Front: "Sin pantalla (backlog)".
- **R3:** el historial de resultados y eventos lo ven lab dueño, médico del examen o tratante, admin clínica y super_admin; el paciente no. Se sacó el [spec].
- **R4:** `REVOKE DELETE` en `expediente_notas` (334.4, unificado con TRUNCATE/TRIGGER/REFERENCES/MAINTAIN) y `REVOKE MAINTAIN` en `ordenes_examen` (336.1) pasan a ser parte firme. El autochequeo 336 y P907 ahora cubren MAINTAIN, y el rollback 336 lo re-otorga.
- **R5:** `created_at := now()` en el INSERT. Se sacó el [spec].
- **R6:** `fecha_resultado` no cambia en la corrección. Se sacó el [spec] y se anotó dónde queda la fecha de corrección.

**Correcciones de revisión**
- **C1:** en el INSERT, el guardia cierra la nota si la cita ya está `completada` (paso INSERT.4). Nueva probe **P908**.
- **C2:** integridad nota↔cita en el INSERT, con **NT010** `La nota no corresponde a la cita` para todos (paso INSERT.1).
  - Columnas confirmadas: `citas.medico_id uuid`, `citas.paciente_id bigint`, contra `expediente_notas.paciente_id integer`; se compara con cast.
  - La nota 1013 cumple.
  - Nuevos: precondición de backfill, chequeo en el autochequeo 334, fila en casos borde (5 citas con `medico_id` NULL, fail-closed) y probe **P909**.
- **C3:** resultado de la medición en §0. El `imc` se excluye de la comparación de contenido y el cierre lo congela (`NEW.imc := OLD.imc`; cualquier otro cambio con la llave `cerrar` → NT009). Nueva probe **P911**.
- **C4:** Front: "Corregir nota" depende **solo** de `cerrada_at`, no de `cita.estado`. Si el estado de la pantalla quedó viejo, NT006 dispara una recarga.
- **C5:** `corregir_nota_consulta` agrega `PERFORM private.exigir_empresa_activa()` (42501, gate de la 326, igual que `corregir_resultado_examen`) y separa el rol en un paso propio. Ese paso es el gate de cuenta activa del médico (`tiene_rol(['medico'])` → `perfiles.activo IS TRUE`, mig 315).
  - Errcode nuevo **NT011**. NT002 queda sólo para "no existe o no es el autor".
  - `exigir_empresa_activa` (`d62cc5a3…`) se agregó a las precondiciones md5 de la 334.
  - Nueva probe **P910**.
- **C6:** 335.6 especifica la restauración con CRLF: cuerpo en LF en el archivo, precondición `md5 = 51d4bbfd…`, `EXECUTE` con `replace(E'\n', E'\r\n')` y autochequeo exacto `md5(prosrc) = 7c980b20…`. El paso 5 del dry-run lo incluye.
- **C7:** el orden de aplicación saca la espera de la PWA. El paso 2 es deploy a producción en Vercel más verificación en prod de una carga de resultado nuevo, antes de la 335. El riesgo se reescribió.
- **C8:** nueva subsección "Fixtures y probes existentes que cambian", con línea, efecto y ajuste de cada uno. Hallazgos que no estaban en la v1:
  - `lx_ex` es el examen 250, completado y liberado: el setup de 6965 cae seguro.
  - P874 genera eventos y después borra su examen (23503).
  - P878 fija md5 de 4 funciones que cambia la 335.
  - P884 fija policies y grants DELETE que cambia la 336.
  - P740 queda como guarda del REVOKE de `paciente_examenes`.
  - Se agregó el **patrón de subtransacción descartable** para probes que generan historia inmutable.
- **C9:** nueva sección "Errcodes de P4" con NT001–NT011 y EX023–EX034 y sus mensajes exactos. Próximos libres: **P912**, **337**, **NT012**, **EX035**.
- **C10:** confirmado que `paciente_examenes()` no tiene dependientes (pg_depend, vistas, matviews, policies y cuerpos: 0 reales; 3 falsos positivos del `_` de ILIKE). El único consumidor es `useWebAppExamenes.ts:21`. Se agregó el `REVOKE … FROM PUBLIC, anon` explícito tras el CREATE y el proacl exacto en el autochequeo.
- **Otros ajustes menores:** §0 amplía los hechos medidos (tipos, IMC, gate de cuenta, CRLF, dependencias). Las precondiciones md5 de 334.3 pasan a tabla. Las intactas de la 335 suman `notificar_orden_lab` y `contexto_ia_paciente` (las cubre P878).

---

## CAMBIOS v3 (26-sep-2026, tras el dry-run de la 334)

- **C5 revisado (opción A de Oscar):** `corregir_nota_consulta` ya **no** llama a `exigir_empresa_activa`. Corregir una nota es una acción clínica, y su gate de cuenta es sólo `tiene_rol(['medico'])` (`perfiles.activo`, mig 315, NT011). El estado de una empresa proveedora no afecta las acciones clínicas del médico.
  - **Por qué:** en el dry-run, el médico A (doble rol: médico y cajero de una empresa `pendiente`, por el fixture PASIGN) recibía 42501 `Empresa proveedora no activa` al corregir su propia nota. Lo mismo le pasaría en producción a cualquier médico con cuenta de proveedor en una empresa suspendida o pendiente.
  - `exigir_empresa_activa` sigue en las precondiciones y el autochequeo md5 de la 334 (no se toca: la usa la 335 en `corregir_resultado_examen`).
  - Tabla de errcodes: el 42501 queda sólo para `corregir_resultado_examen`.
- **P910 dividido:**
  - NT011 sin cambios para perfil inactivo, **usuario sólo proveedor** (sin rol médico), admin clínica y paciente.
  - **Doble rol corrige:** (a1) médico activo con cuenta de proveedor inactiva → revisión 1; (a2) con cuenta activa en empresa no activa → revisión 2. En cada estado un control confirma que `exigir_empresa_activa` lo habría rechazado (42501).
  - Las probes del médico A **no** se aíslan del fixture PASIGN: pasan con el doble rol real.
- **P891:** el alias de tabla `r` chocaba con la variable `r record` (55000 `record "r" is not assigned yet`); pasa a `rv`.
- **§334.1, índices (tras la verificación independiente en prod):** la v2 pedía `INDEX (nota_id)`, pero la 334 aplicada no lo crea: el UNIQUE `(nota_id, revision)` ya sirve de índice para `nota_id`. Sólo se crea `idx_exp_rev_paciente`. La spec se ajusta a lo aplicado; la migración no cambia.
- **Migración 334:** fix de la línea 415 (`contype::text`, 42725 en el autochequeo) y quitada la llamada a `exigir_empresa_activa` en la RPC (comentario, COMMENT ON FUNCTION y encabezado (g) actualizados).
- **Backlog nuevo (familia 8, harness):**
  - Los fixtures PASIGN (l. ~7943), PBUZ y PQR eligen "auth users libres" (sin fila en `cuentas_proveedor`) ordenados por id, sin excluir usuarios con perfil. El tercero es el médico A (`09d243d5`), que queda como cajero activo de una empresa `pendiente` hasta el ROLLBACK final. El admin clínica también puede quedar alcanzado. Deberían sembrar usuarios propios o excluir los que tienen rol.
  - P14 (`paciente_ve_sus_receta_items`) alterna entre "ve 9" y "ve 13 propios" en corridas sin migración de por medio (330, 331, 332, 333 y la base de la 334): el conteo no es determinista.
  - `VA_FX_fixture_validacion` elige una "ficha real de GT" distinta casi en cada corrida (QA-TJ-A, QA-TJ-B, QA-TJ-C, QA-ASE-02, QA-SUP-OFF-647, desde la 330). Siempre sale OK: elige la fila sin un orden determinista.
  - `P825_invariante_visibilidad_cuentas` alterna entre "admin ve 5, visitador_medico ve 1" y "admin ve 3, cajero ve 1" (desde la 330). Siempre sale OK: el actor que elige no es determinista.
