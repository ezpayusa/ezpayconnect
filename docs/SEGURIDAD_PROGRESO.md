# Remediación de seguridad RLS — Progreso

**Rama:** `seguridad/rls-remediacion` (NO mergear a `main` hasta terminar y validar).
**Entorno de trabajo:** proyecto Supabase remoto linkeado (datos FICTICIOS = "staging").
Las migraciones se aplican manualmente con `npx supabase db query --linked -f <archivo>`
(este proyecto NO usa el ledger de migraciones del CLI; el orden lo da el número de archivo).
**Punto de retome:** este archivo. Siguiente = **Fase 1 / Bloque C**.

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

## PRÓXIMO PASO — Fase 1 / Bloque C (cero rotura esperada)
Reasignar a `service_role` las políticas `service_all` que hoy están a `{public}`:
`invitaciones_clinica_service_all`, `invitaciones_medico_service_all`,
`Service role all medico_clinicas`, `Service role all push subscriptions`,
`recordatorios_service_all`. Y cerrar los INSERT `WITH CHECK(true)` de
`notificaciones`, `cuentas_proveedor`, `empresas_proveedoras`.
Verificado en auditoría que TODO el acceso legítimo va por edge functions (service_role) o
RPC `SECURITY DEFINER` → no rompe el frontend.

**Verificación esperada tras Fase 1:** en `run.sh`, `anon` debe pasar a ver
`invitaciones_clinica = 0` (hoy 1). El resto del baseline igual hasta sus fases.

### Recordatorio de proceso (reglas del usuario)
- Una fase a la vez, en orden. Generar migración + listar cambios de frontend, aplicar en
  staging, correr tests, y **esperar confirmación** antes de la siguiente fase.
- Toda función `SECURITY DEFINER` que MUTA debe revalidar al caller internamente.
- No mergear a `main` ni desplegar hasta cerrar y validar todo.
