# Remediación de seguridad RLS — Progreso

**Rama:** `seguridad/rls-remediacion` (NO mergear a `main` hasta terminar y validar).
**Entorno de trabajo:** proyecto Supabase remoto linkeado (datos FICTICIOS = "staging").
Las migraciones se aplican manualmente con `npx supabase db query --linked -f <archivo>`
(este proyecto NO usa el ledger de migraciones del CLI; el orden lo da el número de archivo).
**Punto de retome:** este archivo. Siguiente = **Fase 3 / Bloque A (citas + RPC)**.

---

## Fases completadas

### ✅ Fase 0 — Fundación (commit "seguridad: Fase 0 …")
Aplicada al remoto y verificada (sin drift). NO toca políticas de negocio.

**Incluyó:**
- `supabase/migrations/067_fase0_helpers_autorizacion.sql`
  - Esquema dedicado **`private`** (NO expuesto a la Data API). `USAGE` solo `authenticated`.
  - Helpers `SECURITY DEFINER`, `STABLE`, `SET search_path = ''` y relaciones calificadas
    (`public.*`, `auth.uid()`): `rol_usuario()`, `tiene_rol(text[])`,
    `clinicas_del_usuario()` (PLURAL, para políticas), `clinica_del_usuario()` (SINGULAR, solo UI),
    `es_admin_clinica(uuid)`, `es_medico_de(bigint|text)`, `paciente_es_mio(bigint|text)`.
  - `EXECUTE` revocado de `PUBLIC`/anon, concedido solo a `authenticated`.
- `supabase/migrations/068_fase0_roles_catalogo.sql`
  - Tabla `roles_catalogo` (fuente única de verdad) con los 7 roles reales de `perfiles.rol`:
    `super_admin, admin_clinica, gerente, medico, soporte, vendedor, cliente`.
  - RLS: lectura authenticated, escritura solo super_admin (`private.tiene_rol`).
  - **NO** aplica FK/CHECK sobre `perfiles.rol` todavía (eso es Fase 6).
- `tests/rls/` — harness de verificación:
  - `run.sh` (visibilidad de lectura por rol; `WITH_WRITES=1` añade escritura negativa),
    `probes_escritura.sql`, `EXPECTATIVAS.md`, `README.md`.

**Verificación manual PENDIENTE:** confirmar en Dashboard → Project Settings → API →
**Exposed schemas** que `private` NO esté listado (debe ser solo `public, graphql_public`).

---

### ✅ Fase 1 — Bloque C (service_all → service_role + cerrar INSERT abiertos)
Aplicada al remoto y verificada (commit de Fase 1). Migración:
`supabase/migrations/069_fase1_service_role_y_cerrar_inserts.sql`.

**Qué hizo:**
- Reasignó 5 políticas `service_all` de `{public}` → `service_role`:
  `invitaciones_clinica`, `invitaciones_medico`, `medico_clinicas`,
  `push_subscriptions`, `recordatorios`.
- Cerró 4 INSERT `WITH CHECK(true)` abiertos a `{public}`:
  `notificaciones` (x2), `cuentas_proveedor`, `empresas_proveedoras`.

**Verificación ANTES (frontend + DB):** medico_clinicas/recordatorios sin uso
directo; invitaciones solo `.select` admin; push_subscriptions cubierto por
políticas por-usuario; inserts legítimos por RPC definer owner=postgres
(rolbypassrls=true). Las 4 políticas de INSERT eran `{public}` `WITH CHECK true`
(ninguna era flujo authenticated legítimo).

**Resultado (rojo→verde, medido):**
- Lectura `invitaciones_clinica`: `anon` y no-admin **1 → 0** (solo super_admin la ve).
- Escritura P4/P5/P6 (anon insert notificaciones/cuentas/empresas): **PERMITIDO → BLOQUEADO (42501)**.
- `notificaciones` por-usuario: el usuario ve sus propias + broadcasts (23 = 20+3) ✓.
- `push_subscriptions` por-usuario: insertar la suya OK; con `user_id` ajeno → BLOQUEADO 42501 ✓.
- P1/P2/P3 (citas) siguen ROJAS (corresponden a la Fase 3).

**Nota (no es de esta fase):** tras la Fase 1, **solo `super_admin` ve las
invitaciones** (vía `*_admin_all`). Si más adelante un `admin_clinica` debe
gestionar las invitaciones de SU clínica, será una política aparte (scoped por
`private.clinicas_del_usuario()`), no un retorno a `{public}`.

**Aprendizaje verificado:** en este Postgres la **RLS WITH CHECK se evalúa ANTES
que NOT NULL** en un INSERT (cuando la RLS deniega → 42501 aunque falte un
NOT NULL). Por eso el patrón de probes "42501 vs otra constraint" distingue bien
rojo/verde.

### ✅ Fase 2 — Bloque B (PHI clínico, modelo POR CITA)
Aplicada al remoto y verificada. Migración:
`supabase/migrations/070_fase2_rls_phi_clinico.sql`.

**Modelo decidido:** acceso al PHI por relación de tratamiento:
- **LECTURA**: cabecera (`es_medico_de`) **O** por cita (`medico_atiende_paciente`) **O** autor (`medico_id=auth.uid()`).
- **ESCRITURA**: solo por cita (`medico_id=auth.uid() AND medico_atiende_paciente`).
Motivo: 39/45 citas son cruzadas; solo-cita le quitaba lectura al médico de cabecera y solo-cabecera dejaba "paciente fantasma".

**Qué hizo:**
- Helper nuevo `private.medico_atiende_paciente(bigint|text)` (search_path='').
- Reescribió RLS de `historial_medico`, `recetas_avanzadas`, `receta_items` (por receta padre), `dispensaciones`.
- Reparó deny-all: políticas de `expediente_notas` (5) y el INSERT de `signos_vitales` (+ hook `useConsultas.guardarSignosVitales` ahora inyecta `medico_id`).
- Eliminó los INSERT anónimos de historial; rama `super_admin` global en todas (incl. `examenes`).
- `pacientes`: política aditiva de lectura por cita (arregla "paciente fantasma"; las demás se mantienen).

**Resultado (rojo→verde, medido):**
- P7 médico ve historial sin cita: 51 → **0**. P8 recetas_adv: 1 → **0**.
- P9/P10 (insertar expediente/signos propios): roto → **OK**.
- P12 (insertar historial a paciente sin cita): PERMITIDO → **BLOQUEADO (42501)**. P11/P13 guards (0/42501).
- P14 (paciente ve sus receta_items): **2 propios / 0 ajenos** (fixture `tests/rls/fixtures/qa_paciente_recetas.sql`).
- Lectura: super_admin ahora ve historial(59)/examenes(4) (antes 0); paciente ve solo lo suyo; médico solo lo de sus pacientes (cita/cabecera); anon 0.

**Notas:**
- `historial_medico`/`recetas_avanzadas`/`dispensaciones` usan `paciente_id`/`medico_id` TEXT → overloads TEXT + `::text`; `expediente_notas`/`signos_vitales` INTEGER → `paciente_id::bigint`.
- Triggers `trg_historial_cita`/`trg_historial_receta` auto-registran historial al crear cita/receta (por eso el fixture sumó +2 historial; benigno).
- `admin_clinica` aún ve 0 en PHI (su acceso clínico por clínica es una política aparte, futura).
- `run.sh` resuelve la persona `paciente` con `LIMIT 1` no determinista; el check autoritativo del paciente es P14 (determinista).

## Baseline ROJO capturado (estado ANTES de remediar)

Medido con la fundación ya aplicada (las políticas de negocio aún sin tocar).

### Lectura (`bash tests/rls/run.sh`)
| Tabla | Hallazgo | |
|---|---|---|
| `citas` = **45** para TODO autenticado (incl. paciente/cliente/vendedor/soporte) | fuga total `citas_select_all USING(true)` | 🔴 |
| `historial_medico` = **57** para `medico` | médico ve todo el historial (cross-tenant) | 🔴 |
| `recetas_avanzadas` = **2** para `medico` (con 0 propias) | fuga cross-tenant | 🔴 |
| `receta_items` = **13** para TODO autenticado | `USING(true)` global | 🔴 |
| `medicos` = **8** incluso para **anon** | directorio + CRUD abierto a anon | 🔴 |
| `cuentas_bancarias_pais` = **1** incluso para **anon** | datos bancarios sin login | 🔴 |
| `invitaciones_clinica` = **1** incluso para **anon** | tokens legibles por anon (`service_all` a public) | 🔴 |
| `expediente_notas` = **0** para todos (incl. super_admin) | deny-all → feature SOAP rota | 🛠️ |
| `signos_vitales` = **0** (vacía, sin INSERT) | guardar signos roto | 🛠️ |
| `recetas` (super_admin 12 / medico 0) y `pacientes` (medico 1 / paciente 1) | scoping correcto | 🟢 |
| `anon`: citas/historial/receta_items = **0** | sin política SELECT anon (bien) | 🟢 |

### Escritura (`WITH_WRITES=1 bash tests/rls/run.sh`) — ROLLBACK, no persiste
| Probe | Veredicto HOY | |
|---|---|---|
| P1 `anon_insert_citas` | `PERMITIDO por RLS (falló otra constraint 23502)` — la RLS NO bloquea al anon | 🔴 |
| P2 `medico_cancela_ajena_rpc` | `PERMITIDO (canceló cita ajena)` vía `actualizar_estado_cita` (definer, sin revalidar) | 🔴 |
| P3 `medico_roba_cita_rpc` | `PERMITIDO (se autoasignó cita ajena)` vía `asignar_medico_cita` (definer, sin revalidar) | 🔴 |

`ROLLBACK` verificado: nº de citas canceladas `3 → 3` antes/después (nada persistió).

---

## Decisiones tomadas
- **Helpers en esquema `private`** (no `public` para que no sean RPC vía Data API; no `auth`
  que lo gestiona Supabase). `EXECUTE` solo `authenticated`.
- **Catálogo como TABLA** (`roles_catalogo`), no enum (más flexible; el frontend puede leerlo).
- **`search_path = ''` + relaciones calificadas** en todas las helpers `SECURITY DEFINER`,
  para cerrar el vector de *pg_temp shadowing* (un authenticated creando tablas temporales que
  sombreen `perfiles`/`pacientes` y escale a super_admin).
- **Probes con verificación de EFECTO REAL** (rol elevado relee la fila): PERMITIDO solo si la
  mutación ocurrió; BLOQUEADO si lanzó error O si no hubo efecto. Captura DOS citas ajenas
  distintas para que P2 (cancela) no contamine a P3.

## Pendientes anotados para fases posteriores
- **Tipos `integer` vs `bigint` (Fase 3):** `citas.id` es `bigint`, pero las RPC
  `actualizar_estado_cita`/`asignar_medico_cita`/`crear_cita`/`cancelar_cita_paciente` toman
  `p_cita_id integer`. Funciona por valores chicos; alinear al endurecer las RPC.
- **Tipos `TEXT` en PHI (Fase 2):** `historial_medico`, `recetas_avanzadas`, `dispensaciones`
  guardan `paciente_id`/`medico_id` como TEXT → usar `::text` / los overloads TEXT de los helpers.
- **Rama `super_admin` faltante:** super_admin ve **0** en `historial_medico` y `examenes`
  (la política solo contempla `rol IN ('admin','medico')`, y `admin` ni siquiera existe). Hay que
  darle acceso legítimo al endurecer esas tablas (Fase 2).
- **`admin_clinica`/`gerente` sin política propia:** hoy ven 0 pacientes/recetas (dependían de la
  política permisiva). Cubrir con scoping por clínica (`private.clinicas_del_usuario`) en Fases 2/3.
- **Roles fantasma en ~25 políticas** (`admin`, `admin_pais`, `ezpay_admin`, `admin_finanzas`,
  `admin_publicidad`, `admin_ventas`, `farmaceutico`): alinear al catálogo + CHECK anti fail-open (Fase 6).

---

## PRÓXIMO PASO — Fase 3 / Bloque A (citas + RPC van juntos)
- Eliminar las 3 políticas abiertas de `citas` (SELECT `USING(true)`, INSERT anon/auth abiertos).
- Agregar SELECT/INSERT scoped: paciente dueño, médico dueño, admin_clinica por
  `clinica_id`/`private.clinicas_del_usuario()`, super_admin.
- **Endurecer las RPC SECURITY DEFINER** `actualizar_estado_cita`,
  `asignar_medico_cita`, `crear_cita` (toman `p_cita_id integer`) para REVALIDAR
  al caller (hoy P2/P3 prueban que un médico cancela/roba citas ajenas).
- Migrar `src/pages/CitasPage.tsx` y `src/hooks/useCitas.ts` (legacy) a las RPC
  scoped (`obtener_citas_clinica`, `crear_cita`). La clínica ya usa RPC definer.
- Barrer TODAS las funciones SECURITY DEFINER del proyecto y confirmar que
  revaliden autorización; reportar las que no.

**Verificación esperada tras Fase 3:** P1 (anon insert citas) → BLOQUEADO;
P2/P3 (médico cancela/roba cita ajena vía RPC) → BLOQUEADO; en `run.sh`, `citas`
deja de ser 45 para todo autenticado (cada rol ve solo lo suyo / su clínica).

### Recordatorio de proceso (reglas del usuario)
- Una fase a la vez, en orden. Generar migración + listar cambios de frontend, aplicar en
  staging, correr tests, y **esperar confirmación** antes de la siguiente fase.
- Toda función `SECURITY DEFINER` que MUTA debe revalidar al caller internamente.
- No mergear a `main` ni desplegar hasta cerrar y validar todo.
