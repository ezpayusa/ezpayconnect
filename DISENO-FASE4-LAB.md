# 🧪 DISEÑO — FASE 4 LAB: Gate "liberado al paciente"

> Fecha: 2026-07-16
> Estado: DB viva en prod · Frontend construido + validado en local, PENDIENTE DE DEPLOY (va con consolidación Vercel)
> Contexto de seguridad: schema_migrations en 047 → NUNCA `db push`; aplicar con `supabase db query --linked -f`; NUNCA `functions deploy` sin nombre.

---

## Objetivo

El resultado de un examen sube al bucket privado `resultados-examenes` y NO debe ser visible para el
paciente hasta que su médico lo **libere** explícitamente. Modelo **por-examen**; enforcement **REAL en RLS**
(no solo frontend); backfill en `false` (se libera en la prueba).

Además cierra el bug de storage que impedía al laboratorio subir el archivo.

---

## 1) Bug de storage (read-back) — CERRADO

**Síntoma:** el upload del laboratorio a `resultados-examenes` fallaba con *"new row violates RLS"*.

**Causa real:** `storage.upload()` inserta el objeto y lo **lee de vuelta** (read-back); ese read pasa por la
policy SELECT `resultados_scoped_select`, que exigía que un examen ya referenciara el objeto
(`examenes.archivo_url`) — referencia que se escribe DESPUÉS del upload → **dependencia circular**.
El bucket `comprobantes` no la tenía porque su SELECT incluye la rama "dueño del prefijo".

**Fix:** `ALTER POLICY resultados_scoped_select` sumando la rama dueño-del-prefijo, igual que
`comprobantes_scoped_select`:

```
split_part(name, '/', 1) = mi_empresa_proveedor()::text
```

Así el lab puede leer su propio prefijo y el read-back del upload pasa. No cambia acceso de
paciente/médico/clínica. **Archivo:** `supabase/fixes/fix_resultados_select_readback.sql`. Validado end-to-end
(lab sube → médico ve signed URL).

---

## 2) Esquema — columnas nuevas en `public.examenes`

Idempotente (`ADD COLUMN IF NOT EXISTS`):

| Columna | Tipo | Default | Uso |
|---------|------|---------|-----|
| `liberado_al_paciente` | `boolean NOT NULL` | `false` | Flag de liberación (backfill = false) |
| `fecha_liberacion` | `timestamptz` | — | Auditoría: cuándo se liberó |
| `liberado_por` | `uuid` | — | Auditoría: quién liberó (`auth.uid()`) |

**Archivo:** `supabase/fixes/fase4_01_liberacion_paciente_schema_policies.sql`.

---

## 3) Policies de enforcement (2)

### (a) `resultados_scoped_select` ON `storage.objects` — enforcement del ARCHIVO
La rama del paciente ahora exige liberación; las ramas médico / lab / clínica / super_admin quedan intactas
(el médico debe poder ver el archivo ANTES de liberar). También conserva la rama dueño-del-prefijo del fix #1.

```
(private.paciente_es_mio(e.paciente_id) AND e.liberado_al_paciente)
  OR (e.medico_id = auth.uid())
  OR private.medico_atiende_paciente(e.paciente_id)
  OR (e.clinica_id IS NOT NULL AND private.es_admin_clinica(e.clinica_id))
  OR (e.laboratorio_id = mi_empresa_proveedor())
  OR private.tiene_rol(ARRAY['super_admin'])
```

### (b) `"Paciente ve sus examenes"` ON `public.examenes` — enforcement de la FILA/TEXTO
El paciente ve el examen mientras NO esté completado; una vez completado, solo si fue liberado. La ventana
"completado + no liberado" queda oculta a nivel RLS (ni por API directa).

```
paciente_id IN (SELECT id FROM pacientes WHERE auth_user_id = auth.uid())
AND (liberado_al_paciente OR estado <> 'completado')
```

**Archivo:** `supabase/fixes/fase4_01_liberacion_paciente_schema_policies.sql`.

---

## 4) RPCs (3) — `SECURITY DEFINER`, `search_path = ''`

**Archivo:** `supabase/fixes/fase4_02_liberacion_paciente_rpcs.sql`. Todas `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO authenticated`.

| Firma | Qué hace |
|-------|----------|
| `liberar_examen_al_paciente(p_examen_id integer) → jsonb` | Valida autoridad del médico (medico_id / medico_atiende_paciente / admin_clinica / super_admin), exige `estado = 'completado'`, setea flags (`liberado_al_paciente=true`, `fecha_liberacion=now()`, `liberado_por=auth.uid()`) y avisa al paciente (in-app + push). Idempotente: si ya liberado devuelve `{ya_liberado:true}`. |
| `liberar_orden_al_paciente(p_orden_id uuid) → jsonb` | Bulk: libera los completados-no-liberados de la orden que el caller pueda liberar (mismo gate de autoridad), y emite **UNA sola** notificación al paciente. Devuelve `{liberados:N}`. |
| `paciente_examenes() → TABLE(...)` | Vista del paciente enmascarada: bypassa RLS pero SOLO devuelve exámenes del caller. Para completado-no-liberado: `estado → 'en_proceso'` y `resultados/archivo_url/notas/fecha_resultado` en NULL; expone flag `en_revision`. Join a `perfiles.id = medico_id` para `medico_nombre`. |

---

## 5) Split de notificación — `notificar_resultado_examen(p_examen_id integer)`

Antes avisaba al paciente al subir el resultado. Ahora **al subir avisa SOLO al médico**
(`notificaciones`, tipo `examen_resultado`, → `/medico/citas`); el aviso al paciente se movió a las RPCs de
liberación (A/B). Verificado: `pg_get_functiondef` ya no contiene `notificaciones_pacientes`.

---

## 6) Frontend (por archivo)

| Archivo | Cambio |
|---------|--------|
| `src/pages/PacienteDetallePage.tsx` (lado médico, tab Exámenes) | Select suma `liberado_al_paciente, fecha_liberacion`; handlers `liberarExamen(id)` y `liberarTodosListos()`; botón bulk **"Liberar resultados listos"** en el header; por-examen botón **"Liberar al paciente"** o badge verde **"Liberado · fecha"** (`CheckCircle2`). Imports `toast` (sonner) + `CheckCircle2`. |
| `src/webapp/hooks/useWebAppExamenes.ts` | `fetchExamenes` cambia del select directo a `supabase.rpc('paciente_examenes')`; mapea `en_revision`; se eliminó el join a `perfiles` y el special-case `42P01`. |
| `src/webapp/pages/WebAppExamenes.tsx` | Import `Clock`; aviso ámbar **"Resultado en revisión por tu médico…"** cuando `ex.en_revision` (antes del bloque de resultados). |
| `src/webapp/types/webapp.types.ts` | `interface ExamenPaciente` + `en_revision?: boolean`. |

**Typecheck:** `npx tsc --noEmit -p tsconfig.app.json` → **88 (baseline), sin regresión.**

---

## HALLAZGOS FRENTE 2 — en diagnóstico (recon Codex hecho)

1. **Flujo de estados permite saltar `en_proceso`** (`recibida → completado` directo); el estado `'revision'` del enum está sin uso. **Veredicto:** a definir (producto/flujo).
2. **Por-examen vs por-orden — cosmético.** El param `ordenId` en realidad es `examenes.id`; el toast "Orden actualizada" es engañoso. **Veredicto:** rename cosmético, sin impacto funcional.
3. **BUG FECHAS — confirmado en vivo.** `WebAppExamenes` usa `new Date(iso)` (parseo UTC → muestra día −1, p.ej. "14 julio" para 2026-07-15) y `useLaboratorio` setea `fecha_resultado` con `toISOString().slice(0,10)` (UTC). Ya existe `src/lib/fecha.ts` (`parseFechaLocal` / `hoyISO`) que lo evita. **Veredicto:** fix = usar el helper existente.
4. **`archivo_url` pisado con NULL — FALSO POSITIVO.** El spread condicional lo evita. **Veredicto:** sin acción.
5. **Examen `id=1` con `archivo_url` público en bucket privado** (data vieja, 1 fila). **Veredicto:** normalizar a path con `-f`.
6. **`estado='completado'` sin archivo.** El texto de resultado es obligatorio, el archivo opcional. **Veredicto:** decisión de producto pendiente.
