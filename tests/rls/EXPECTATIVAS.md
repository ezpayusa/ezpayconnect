# Matriz de expectativas RLS — baseline ROJO → objetivo VERDE

Este documento define, **por rol y por tabla**, qué visibilidad es CORRECTA, y
registra el **estado actual (ROJO)** medido en la auditoría. `tests/rls/run.sh`
imprime los números reales; aquí se comparan contra lo esperado.

Convención:
- **Solo lo suyo** = solo filas donde el usuario es el médico tratante / el
  paciente dueño / el admin de esa clínica.
- **Todo** = acceso global legítimo (solo `super_admin`).
- **Nada** = no debe ver ninguna fila (0).
- 🔴 = hoy ve de más (fuga). 🟢 = hoy correcto. 🛠️ = hoy roto por deny‑all (no es fuga, es feature caída).

## Personas de prueba
| persona | origen del uid | notas |
|---|---|---|
| super_admin | `perfiles.rol='super_admin'` | acceso global |
| admin_clinica | `perfiles.rol='admin_clinica'` | solo su clínica (vía RPC definer) |
| gerente | `perfiles.rol='gerente'` | staff de clínica |
| medico | `perfiles.rol='medico'` | solo sus pacientes |
| soporte | `perfiles.rol='soporte'` | hoy sin políticas dedicadas |
| vendedor | `perfiles.rol='vendedor'` | comercial, sin PHI |
| cliente | `perfiles.rol='cliente'` | genérico |
| paciente | `pacientes.auth_user_id` | solo lo suyo |
| anon | sin JWT | casi nada |

## Tabla de objetivos (lo que DEBE ver cada rol)

| Tabla | super_admin | admin_clinica | medico | paciente | soporte/gerente/vendedor/cliente | anon |
|---|---|---|---|---|---|---|
| `citas` | Todo | Su clínica | Sus citas | Sus citas | Nada* | Nada |
| `historial_medico` | Todo | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `recetas` | Todo (su país) | Su clínica | Sus recetas | Sus recetas | Nada | Nada |
| `recetas_avanzadas` | Todo | Su clínica | Sus recetas | Sus recetas | Nada | Nada |
| `receta_items` | Todo | Su clínica | De sus recetas | De sus recetas | Nada | Nada |
| `dispensaciones` | Todo | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `examenes` | Todo | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `pacientes` | Todo (su país) | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `expediente_notas` | Todo | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `signos_vitales` | Todo | Su clínica | Sus pacientes | Lo suyo | Nada | Nada |
| `medicos` | Todo (CRUD) | Su clínica | Su propio perfil | Directorio* | Directorio* | Directorio* |
| `cuentas_bancarias_pais` | Todo | — | — | — | — | Nada |
| `invitaciones_clinica` | Todo | — | — | — | — | Nada |
| `invitaciones_medico` | Todo | — | — | — | — | Nada |

\* `citas`/`medicos` "Nada/Directorio": decisión de producto. Para `medicos` la
lectura puede ser un directorio acotado (sin PII como cédula/teléfono); la
escritura nunca debe ser anónima.

## Estado actual medido (BASELINE ROJO — auditoría 2026‑06‑13)

Hallazgos empíricos confirmados que `run.sh` debe reflejar HOY (antes de las fases):

| Hallazgo (hoy) | Esperado tras fix |
|---|---|
| 🔴 `medico` ve **todas** las `citas` (USING true) | solo las suyas |
| 🔴 `medico` ve **las 57 filas** de `historial_medico` (rol global) | solo sus pacientes |
| 🔴 cualquier `authenticated` ve **todos** los `receta_items` (USING true) | solo de sus recetas |
| 🔴 cualquier `medico` ve **todas** las `recetas_avanzadas` | solo las suyas |
| 🔴 `anon` puede leer `medicos` y `cuentas_bancarias_pais` | anon = Nada en bancarias |
| 🔴 `anon` puede leer/insertar `invitaciones_clinica/medico` (service_all a public) | anon = Nada |
| 🛠️ `expediente_notas` = **0 para todos** (RLS on, 0 políticas) → feature de notas SOAP rota | médico/paciente ven lo suyo |
| 🛠️ `signos_vitales` = INSERT denegado (sin política) → guardar signos roto | médico puede insertar lo suyo |
| 🟢 `recetas` (básica) y `examenes` ya están scoped correctamente | mantener (patrón de referencia) |

## Cómo se "ponen en verde" por fase
- **Fase 1** ✅ APLICADA: `anon`/usuarios ya no ven `invitaciones_*` (anon `invitaciones_clinica` 1→0; solo super_admin la ve vía `*_admin_all`) ni pueden insertar en `notificaciones`/`cuentas_proveedor`/`empresas_proveedoras` (P4/P5/P6 → BLOQUEADO). `push_subscriptions`/`notificaciones` siguen funcionando por-usuario (verificado).
- **Fase 2**: `historial_medico`, `recetas_avanzadas`, `receta_items`, `dispensaciones` pasan a "solo lo suyo"; `expediente_notas` y `signos_vitales` dejan de estar en deny‑all.
- **Fase 3**: `citas` pasa a "solo lo suyo / su clínica"; las RPC de citas revalidan al caller.
- **Fase 4**: `medicos` deja de ser escribible por anon; `cuentas_bancarias_pais` exige auth.
- **Fase 6**: roles administrativos alineados al catálogo; sin ramas muertas.

## Pruebas de ESCRITURA NEGATIVA (baseline ROJO)

Archivo: `tests/rls/probes_escritura.sql` (corre con `WITH_WRITES=1 bash tests/rls/run.sh`).
Todas terminan en **ROLLBACK**: nunca persisten, aunque la operación sea permitida.

| Probe | Qué intenta | Baseline | Objetivo | Fase | Estado |
|---|---|---|---|---|---|
| P1 `anon_insert_citas` | que `anon` inserte una cita | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | pendiente |
| P2 `medico_cancela_ajena_rpc` | médico cancela cita ajena vía `actualizar_estado_cita` | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | pendiente |
| P3 `medico_roba_cita_rpc` | médico se autoasigna cita ajena vía `asignar_medico_cita` | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | pendiente |
| P4 `anon_insert_notificaciones` | que `anon` inserte una notificación | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |
| P5 `anon_insert_cuentas_proveedor` | que `anon` cree una cuenta de proveedor | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |
| P6 `anon_insert_empresas_proveedoras` | que `anon` cree una empresa | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |

> P1/P2/P3 (citas) siguen en rojo a propósito hasta la Fase 3 (RLS scoped de
> `citas` + revalidación de autorización dentro de las RPC definer).
> P4/P5/P6 pasaron a VERDE en la **Fase 1** (cierre de los INSERT públicos).
> Nota verificada: la RLS WITH CHECK se evalúa ANTES que NOT NULL → cuando la
> RLS deniega sale 42501 aunque falte un NOT NULL (por eso el patrón "42501 vs
> otra constraint" sí distingue bien rojo/verde).

## Nota sobre los helpers (Fase 0)
- Viven en el esquema **`private`** (no expuesto a la Data API), con `EXECUTE`
  solo para `authenticated`.
- `private.clinicas_del_usuario()` (PLURAL) es la que usan las políticas de
  aislamiento, con `IN`/`ANY` → soporta staff/médicos multi-clínica.
- `private.clinica_del_usuario()` (SINGULAR) devuelve **una clínica arbitraria**
  (LIMIT 1) si el usuario pertenece a varias; es **solo para UI**, no para
  políticas.
