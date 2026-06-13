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
- **Fase 2** ✅ APLICADA (modelo POR CITA): `historial_medico`, `recetas_avanzadas`, `receta_items`, `dispensaciones` pasan a "cabecera O cita O autor" (lectura) y "cita" (escritura); `expediente_notas` y `signos_vitales` salen de deny‑all; super_admin gana acceso global a PHI (historial/examenes 0→59/4); `pacientes` suma lectura por cita (arregla "paciente fantasma"). Helper nuevo `private.medico_atiende_paciente`. Fixture P14: `tests/rls/fixtures/qa_paciente_recetas.sql`.
- **Fase 3** ✅ APLICADA: `citas` deja de ser 45 para todo autenticado (médico ve las suyas, paciente las suyas, admin_clinica su clínica, super_admin todas, anon 0). Políticas abiertas eliminadas; **INSERT solo vía RPC `crear_cita`** (revalida + fuerza estado por rol: paciente→'solicitada'). RPC `actualizar_estado_cita`/`asignar_medico_cita`/`crear_cita` revalidan al caller (integer→bigint). Triggers de historial → SECURITY DEFINER (cabo de Fase 2).
- **Fase 4**: `medicos` deja de ser escribible por anon; `cuentas_bancarias_pais` exige auth.
- **Fase 5** ✅ APLICADA (migración `074`): buckets `resultados-examenes` (PHI) y `comprobantes` (financiero) eran **públicos** → cualquiera con la URL accedía. Ahora son **privados** + RLS scoped en `storage.objects`. Lectura por objeto (resultado: paciente dueño / médico que ordenó o atiende / admin de la clínica / lab dueño / super_admin — match EXACTO del path, sin comodines LIKE; comprobante: empresa dueña por 1er segmento del path / super_admin). **Escritura** (antes abierta a cualquier authenticated → inyección/sobrescritura ajena) ahora scoped al folder propio (`split_part(name,'/',1)=mi_empresa_proveedor`). El frontend pasa de `getPublicUrl()` a `createSignedUrl()` (helper `src/lib/signedUrl.ts`), que **exige SELECT sobre el objeto** → no se firma sin derecho. 8 lectores migrados.
- **Fase 6**: roles administrativos alineados al catálogo; sin ramas muertas.

### Storage (Fase 5) — objetivos por bucket
| Bucket | super_admin | dueño (paciente/médico/lab/empresa) | ajeno authenticated | anon |
|---|---|---|---|---|
| `resultados-examenes` (PHI) | Todo | Su examen (lee+firma) | Nada | Nada |
| `comprobantes` (financiero) | Todo | Su empresa (lee+firma+sube) | Nada | Nada |

## Pruebas de ESCRITURA NEGATIVA (baseline ROJO)

Archivo: `tests/rls/probes_escritura.sql` (corre con `WITH_WRITES=1 bash tests/rls/run.sh`).
Todas terminan en **ROLLBACK**: nunca persisten, aunque la operación sea permitida.

| Probe | Qué intenta | Baseline | Objetivo | Fase | Estado |
|---|---|---|---|---|---|
| P1 `anon_insert_citas` | que `anon` inserte una cita | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | ✅ **VERDE** (42501) |
| P2 `medico_cancela_ajena_rpc` | médico cancela cita ajena vía `actualizar_estado_cita` | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | ✅ **VERDE** (RPC revalida) |
| P3 `medico_roba_cita_rpc` | médico se autoasigna cita ajena vía `asignar_medico_cita` | 🔴 PERMITIDO | BLOQUEADO | Fase 3 | ✅ **VERDE** (RPC revalida) |
| P15 `medico_ve_citas_ajenas` | médico ve citas de otros médicos | 🔴 PERMITIDO (45) | BLOQUEADO (0) | Fase 3 | ✅ **VERDE** (0) |
| P16 `paciente_ve_citas_ajenas` | paciente ve citas de otros pacientes | 🔴 PERMITIDO (45) | BLOQUEADO (0) | Fase 3 | ✅ **VERDE** (0) |
| P17 `paciente_no_crea_agendada` | paciente crea su cita ya 'agendada' | 🔴 PERMITIDO | 'solicitada' forzada | Fase 3 | ✅ **VERDE** (solicitada) |
| P4 `anon_insert_notificaciones` | que `anon` inserte una notificación | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |
| P5 `anon_insert_cuentas_proveedor` | que `anon` cree una cuenta de proveedor | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |
| P6 `anon_insert_empresas_proveedoras` | que `anon` cree una empresa | 🔴 PERMITIDO | BLOQUEADO | Fase 1 | ✅ **VERDE** (42501) |
| P7 `medico_ve_historial_sin_cita` | médico ve historial de paciente sin cita/cabecera | 🔴 PERMITIDO (51) | BLOQUEADO (0) | Fase 2 | ✅ **VERDE** (0) |
| P8 `medico_ve_recetas_adv_sin_cita` | médico ve recetas avanzadas ajenas | 🔴 PERMITIDO (1) | BLOQUEADO (0) | Fase 2 | ✅ **VERDE** (0) |
| P11 `medico_ve_expediente_sin_cita` | médico ve notas de expediente ajenas | 🟢 BLOQUEADO | BLOQUEADO (0) | Fase 2 | ✅ guard |
| P9 `medico_inserta_expediente_propio` | médico inserta su nota (paciente que atiende) | 🛠️ BLOQUEADO (roto) | OK | Fase 2 | ✅ **VERDE** (OK) |
| P10 `medico_inserta_signos_propio` | médico inserta signos (paciente que atiende) | 🛠️ BLOQUEADO (roto) | OK | Fase 2 | ✅ **VERDE** (OK) |
| P12 `medico_inserta_historial_ajeno` | médico inserta historial para paciente sin cita | 🔴 PERMITIDO | BLOQUEADO | Fase 2 | ✅ **VERDE** (42501) |
| P13 `medico_inserta_expediente_ajeno` | médico inserta nota para paciente sin cita | 🟢 BLOQUEADO | BLOQUEADO | Fase 2 | ✅ guard (42501) |
| P14 `paciente_ve_sus_receta_items` | paciente ve los items de SUS recetas (no ajenos) | ⚪ N/A | >0 propios / 0 ajenos | Fase 2 | ✅ **VERDE** (2/0) |
| P18 `authn_asocia_medico_clinica` | authenticated asocia médico a clínica ajena | 🔴 PERMITIDO | BLOQUEADO | Intermedio | ✅ **VERDE** (42501) |
| P19 `medico_miembro_no_es_admin` | gate de staff: médico miembro ≠ admin | 🟢 BLOQUEADO | BLOQUEADO | Intermedio | ✅ guard |
| P20 `anon_escribe_medicos` | anon inserta/escribe en medicos | 🔴 PERMITIDO | BLOQUEADO | Fase 4 | ✅ **VERDE** (42501) |
| P21 `authn_escribe_medicamentos` | authenticated común escribe medicamentos | 🔴 PERMITIDO | BLOQUEADO | Fase 4 | ✅ **VERDE** (42501) |
| P22 `authn_escribe_farmacias` | authenticated común escribe farmacias | 🔴 PERMITIDO | BLOQUEADO | Fase 4 | ✅ **VERDE** (42501) |
| P23 `anon_lee_cuentas_bancarias` | anon lee cuentas_bancarias_pais | 🔴 PERMITIDO (1) | BLOQUEADO (0) | Fase 4 | ✅ **VERDE** (0) |
| P25 `anon_lee_pii_medicos` | anon lee cédula/PII de medicos | 🔴 PERMITIDO (3) | sin acceso a columna | Fase 4 | ✅ **VERDE** (42501) |
| P24 `proveedor_ve_cuenta_su_pais` | (positivo) proveedor ve la cuenta de su país | 🟢 OK (1) | OK (≥1) | Fase 4 | ✅ **VERDE** (1) |
| P26 `anon_lee_resultado_examen` | anon lee un resultado de examen (PHI) | 🔴 PERMITIDO (1) | BLOQUEADO (0) | Fase 5 | ✅ **VERDE** (0) |
| P27 `medico_ajeno_lee_resultado` | médico que no ordenó/atiende lee el resultado | 🔴 PERMITIDO (1) | BLOQUEADO (0) | Fase 5 | ✅ **VERDE** (0) |
| P28 `paciente_dueno_lee_resultado` | (positivo) paciente dueño firma su resultado | 🟢 OK (1) | OK (≥1) | Fase 5 | ✅ **VERDE** (1) |
| P29 `medico_orden_lee_resultado` | (positivo) médico que ordenó firma el resultado | 🟢 OK (1) | OK (≥1) | Fase 5 | ✅ **VERDE** (1) |
| P30 `anon_lee_comprobante` | anon lee un comprobante (financiero) | 🟢 BLOQUEADO (0) | BLOQUEADO (0) | Fase 5 | ✅ guard (0) |
| P31 `proveedor_ajeno_lee_comprobante` | proveedor de OTRA empresa lee el comprobante | 🔴 PERMITIDO (1) | BLOQUEADO (0) | Fase 5 | ✅ **VERDE** (0) |
| P32 `proveedor_dueno_lee_comprobante` | (positivo) proveedor dueño firma su comprobante | 🟢 OK (1) | OK (≥1) | Fase 5 | ✅ **VERDE** (1) |
| P33 `proveedor_ajeno_escribe_comprob` | proveedor sube/sobrescribe en folder de otra empresa | 🔴 PERMITIDO | BLOQUEADO | Fase 5 | ✅ **VERDE** (42501) |
| P34 `proveedor_dueno_escribe_comprob` | (positivo) proveedor sube a SU folder | 🟢 OK | OK | Fase 5 | ✅ **VERDE** (OK) |
| P35 `ajeno_escribe_resultado_lab` | un ajeno sube un resultado en el folder de otro lab | 🔴 PERMITIDO | BLOQUEADO | Fase 5 | ✅ **VERDE** (42501) |
| P36 `lab_dueno_escribe_resultado` | (positivo) el lab sube a SU folder (upload legítimo) | 🟢 OK | OK | Fase 5 | ✅ **VERDE** (OK) |
| P37 `anon_broadcast_promo` | anon dispara broadcast masivo a TODOS los pacientes | 🔴 PERMITIDO | BLOQUEADO | Definer | ✅ **VERDE** (42501) |
| P38 `medico_broadcast_promo` | médico común (no super_admin) dispara broadcast | 🔴 PERMITIDO | BLOQUEADO | Definer | ✅ **VERDE** (P0001) |
| P39 `superadmin_broadcast_promo` | (positivo) super_admin sí dispara el broadcast | 🟢 OK (14) | OK (>0) | Definer | ✅ **VERDE** (14) |
| P40 `medico_ajeno_notifica_paciente` | médico sin cita con el paciente lo notifica | 🔴 PERMITIDO | BLOQUEADO | Definer | ✅ **VERDE** (P0001) |
| P41 `medico_atiende_notifica_paciente` | (positivo) el médico que lo atiende notifica | 🟢 OK | OK | Definer | ✅ **VERDE** (OK) |
| P42 `ajeno_notifica_laboratorio` | un ajeno (no ordenó, no es el lab) notifica al lab | 🔴 PERMITIDO | BLOQUEADO | Definer | ✅ **VERDE** (P0001)† |
| P43 `medico_orden_notifica_lab` | (positivo) el médico que ordenó notifica al lab | 🟢 OK | OK | Definer | ✅ **VERDE** (OK) |
| P44 `ajeno_administra_visita` | un ajeno administra (aprueba/rechaza) visita ajena | 🔴 PERMITIDO | BLOQUEADO | Definer | ✅ **VERDE** (P0001)† |
| P45 `proveedor_visita_administra` | (positivo) miembro de la empresa proveedora la administra | 🟢 OK | OK | Definer | ✅ **VERDE** (OK) |
| P46 `staff_clinica_notifica_paciente` | (positivo) staff de clínica con cita del paciente lo notifica | 🟢 OK | OK | Definer | ✅ **VERDE** (OK) |

† P42/P44 destaparon un **fail-open trivaluado**: `mi_empresa_proveedor()` es NULL para
no-proveedores, así que `false OR (NULL = empresa) OR …` = NULL y `IF NOT NULL` salta el
RAISE (autoriza). Corregido envolviendo la comparación en `COALESCE(… , false)`. Los probes
NEGATIVOS lo cazaron antes del commit.

| P47 `superadmin_ve_admin_gated` | super_admin ve recurso admin-gated (cuentas_proveedor) | 🟢 OK | OK | Fase 6 | ✅ **VERDE** (no regresión) |
| P48 `rol_fuera_catalogo_rechazado` | asignar `perfiles.rol='admin'` (fuera del catálogo) | 🔴 PERMITIDO | BLOQUEADO | Fase 6 | ✅ **VERDE** (FK 23503) |
| P49 `rol_valido_asignado` | asignar `rol='gerente'` (válido) | 🟢 OK | OK | Fase 6 | ✅ **VERDE** (OK) |
| P50 `superadmin_edita_farmacia` | super_admin edita farmacia_medicamentos (remap) | 🔴 REGRESIÓN (42501) | OK | Fase 6 | ✅ **VERDE** (RLS permite) |
| P51 `medico_no_edita_farmacia` | un no-super edita farmacia_medicamentos | 🟢 BLOQUEADO | BLOQUEADO | Fase 6 | ✅ guard (42501) |
| P52 `superadmin_crea_reporte` | super_admin crea reportes_guardados (remap) | 🔴 REGRESIÓN (42501) | OK | Fase 6 | ✅ **VERDE** (RLS permite) |
| P53 `medico_no_crea_reporte` | un no-super crea reportes_guardados | 🟢 BLOQUEADO | BLOQUEADO | Fase 6 | ✅ guard (42501) |
| P54 `superadmin_ve_reportes` | super_admin ve reportes_guardados | 🟢 OK | OK | Fase 6 | ✅ **VERDE** (OK) |

**Verificación HTTP (fuera del harness SQL)** de `crear-staff-clinica` tras la Fase 6:
no-admin (medico.qa) → **403**; admin_clinica (clinica.qa) → **200**, crea staff con
`perfiles.rol='gerente'` **y** membresía `medico_clinicas` de su clínica (acceso RLS real).
Bug encontrado y corregido: la función no creaba la fila en `medicos` (FK de
`medico_clinicas`) → la asociación fallaba en silencio y el staff quedaba sin acceso de clínica.

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
