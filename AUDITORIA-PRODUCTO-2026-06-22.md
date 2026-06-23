# Auditoría de Producto + Seguridad — EzPayConnect
**Fecha:** 2026-06-22 · **Modo:** SOLO LECTURA (cero cambios/migraciones/commits) · **Salida:** este documento.

> Marco de referencia: auditoría de seguridad recién cerrada (push transaccional + hardening RLS, migs 067–136 en prod). **Ninguna recomendación de este doc relaja lo endurecido.** Todo hallazgo que requiera cambio se lista como recomendación para que Oscar lo evalúe **con el revisor primero** — nada se implementó.

> **Nota de método:** los invariantes (§0) se derivaron leyendo migs 067–136 + el harness. Cada panel se auditó contra ese rubro por subagente de solo-lectura. Los 3 hallazgos 🔴 críticos de Clínica fueron **verificados contra la BD viva** (consulta de solo lectura a `pg_proc`/`has_function_privilege`). El cruce de callers rotos del CIERRE FINAL (§4) se corrió con grep sobre todo `src/`.

---

## 0. Invariantes de seguridad derivados del repo

Derivados de `supabase/migrations/067…136` + `tests/rls/probes_escritura.sql`. **Pendiente de validación por Oscar antes de usarlos como vara.**

| # | Invariante | Evidencia | Probe |
|---|---|---|---|
| **I1** | RLS / gates **fail-closed**: todo predicado nullable envuelto en `COALESCE(...,false)`; aislamiento por `col = helper()` (NULL ⇒ 0 filas), nunca `IS NULL OR` que abra | `075:76-79` (comentario canónico), `078:28`, `085:100`, `093:22`, todas las RPC push 121–133 | P197/P208/P221/P360/P420 |
| **I2** | INSERT a tablas sensibles **solo vía RPC SECURITY DEFINER gateado**; `REVOKE INSERT` directo a anon/authenticated | `069:60-68`, `085:83`, `136:18-19,26-43` | P200/P267/P433/P434 |
| **I3** | Gate de actor atado a **`auth.uid()` derivado server-side**, no a params del caller; firmas RPC minimalistas (solo id) | `085:98`, firmas `122/126/128/131/133`, `131:130` | P360/P372/P406/P419 |
| **I4** | Aislamiento por **país fail-closed** (borde de tenant duro, sin grandfather; país estampado server-side, `NOT NULL`+FK RESTRICT) | `093/094/095/099/104/116`, `mi_pais()` DEFINER sp'' | P191-223/P224/P325 |
| **I5** | Aislamiento **cross-empresa / cross-tenant a nivel fila** (policies conjuntivas `AND empresa_id=mi_empresa()`, helper DEFINER para EXISTS en WITH CHECK) | `078:28-45`, `085:133`, `134:15-29`, `135:20-35` | P127/P137/P425/P428 |
| **I6** | Helpers DEFINER con **`search_path=''` + refs calificadas** (`public.`/`private.`) | `067:16-22`, hardening 105/107/110/118, push 121-133 | P261/P262/P365 |
| **I7** | **Buckets privados + signed URLs** (no público) | `074:27` (flip a privado de `resultados-examenes`/`comprobantes`) | (sin probe SQL directo — comportamiento de storage) |
| **I8** | Contenido de notificación **sin PHI cruda** (genérico; detalle tras `accion_url` interna; CHECK `accion_url ~ '^/...'` anti-phishing) | `121:21-25`, `125:33`, `127`, `130:25`, `133:11` | P144/P361/P382/P423 |
| **I9** | **Sin edges abiertas con service_role** sin chequeo de relación; confused-deputy cerrado (RPCs re-validan relación; edges viejas stub-410) | `069:31-53`, `131`, `136:13-15` | P414-P418/P431/P432 |
| **I10** | Anti-escalada de roles / RBAC techo per-empresa (no auto-otorgar, RPC escribe solo en empresa del editor, no-lockout) | `079/080/117` | P119/P332/P335/P342 |

**Patrones recurrentes:** COALESCE fail-closed · gate-antes-del-claim + flag idempotente (`UPDATE … WHERE … AND notificado IS NOT TRUE; IF NOT FOUND RETURN`) · trigger reset de flag en re-entrada de estado · firma uuid/bigint-only + contenido server-compuesto · helper DEFINER obligatorio para EXISTS en WITH CHECK · split de policy `ALL` dual-use → SELECT+UPDATE + column-grant · esquema `private` no expuesto a PostgREST.

**Caveats del rubro:** I7 está establecido por migración (`074:27`) pero **sin probe SQL directo** (solo se verifica que payloads no filtren URLs/tokens). I6 tuvo una excepción histórica (`laboratorios_para_medico` nació en `search_path='public'`, endurecida en 105).

---

## 1. Tabla resumen por módulo

| Módulo | OK (destacado) | 🔴 RIESGO | 🟡 A REVISAR | Incompletos/dead |
|---|---|---|---|---|
| **Admin EzPay** | RPCs campaña/empresa/pago gateados; comprobantes signed | 4 | ~8 (policies por confirmar) | ~10 |
| **Proveedores** | guard fail-closed; notifs/roles/chat por RPC; comprobantes signed | 4 áreas (I2 sistémico, I7×2, I5, I4) | 2 | 5 (1 crash) |
| **Laboratorios** | `notificar_resultado_examen` hardened (mig 130, sin PHI); aislamiento lab↔lab | 1 bug abierto + 1 (I2 examenes) | 1 | 4 |
| **Farmacias** | despacho por RPC gateado per-ítem; edges stub-410 no invocadas; token seguro | 1 (I2 inventario) | 1 (FarmaciasPage legacy) | 3 |
| **Clínica / Empresas afines** | afín blindado (083/084); citas/notif por RPC gateado | **3 críticos (verificados live)** + 2 | 1 | 2 |
| **CIERRE FINAL (cruce §4)** | 0 callers rotos | 0 | 0 | — |

> "Empresas afines" **no es un panel propio**: es un *tipo* de empresa proveedora (`empresas_proveedoras.tipo='empresa_afin'`, rol estrella `gerente`) dentro de `/proveedor/*`, blindado por migs 083/084. El grueso de este módulo es el **panel Clínica** (`/clinica/*`).

> **Naturaleza de los hallazgos I2 "escritura directa":** varios paneles escriben tablas sensibles con `.insert()/.update()` directo confiando en RLS por empresa/rol, en vez de pasar por RPC DEFINER. Esto **no necesariamente es brecha** si la RLS es fail-closed — pero es la mayor desviación literal de I2 y conviene que Oscar+revisor decidan, tabla por tabla, si se acepta (RLS suficiente) o se migra a RPC (como ya se hizo con notificaciones). No se asume nada.

---

## 2. Detalle por módulo

### 2.1 Admin EzPay (`src/pages/admin-ezpay/`, `src/hooks/admin/`)

**Guard:** `AdminRoute` (`App.tsx:174-197`) + `useAdminAuth` admite solo `rol==='super_admin'` (los granulares admin_pais/finanzas nunca existieron).

**🔴 RIESGO**
- **R1 [seguridad, I2/I5] — `.update()` directo a `notificaciones` sin gate de propietario en cliente.** `useNotificacionesAdmin.ts:75-78` (marcarLeida), `:94-99` (enProceso), `:117-129` (completada + **archivar por `evento_id` cross-usuario**), `:156-162` (todasLeidas). Depende 100% de la policy `notificaciones_update_super_admin` (mig 136). *Esto se censó y se preservó deliberadamente en el CIERRE FINAL* (el split mantuvo UPDATE super_admin justamente por `marcarCompletada`). **Conforme al marco actual**, pero el `marcarCompletada` archivando filas de otros usuarios queda como superficie a vigilar.
- **R2 [seguridad+integridad, I2/I4] — INSERT directo a `campanas_publicitarias` saltando el RPC.** `PagosProveedoresPage.tsx:121-135` inserta la campaña directo (+`:86-96` `planes_visitador_contratados`, +`:137-140` update solicitud) en vez de `aprobar_solicitud_campana` (RPC DEFINER que re-valida país y es atómico). Protegido por RLS super_admin (P57/P58) ⇒ no es agujero a terceros, pero **rompe atomicidad y la re-validación país** (campaña huérfana si falla el 2º update).
- **R3 [seguridad, I2/I8] — `useVentas.registrarVenta` → edge `notificar-admin` por `fetch`, contenido compuesto en cliente.** `hooks/admin/useVentas.ts:162-181` (incluye `medico_id` en texto). Patrón "helper edge que crea notificación con texto del caller" que mig 131 reemplazó por RPCs. Usa token de usuario (no service_role). A confirmar si la edge valida rol/sanitiza o es remanente pre-131.
- **R4 [seguridad, I3] — auditoría con auth anon → actor falsificable.** `hooks/useAuditoria.ts:4,54` usa `ANON_KEY` hardcodeada (además aparenta truncada/placeholder) como `Authorization` al POST `registrar-auditoria`; el actor viaja en el payload del cliente. Si la edge confía en el payload, el actor del log es spoofeable. **Mina la confiabilidad de toda la auditoría.**

**🟡 A REVISAR**
- Escrituras directas conformes **solo si** la RLS por tabla es fail-closed a super_admin: `perfiles` (UsuariosAdminPage insert:97/update:120,153/delete:139), `usuario_roles` (AsignacionRolesPage:69,89), `planes_asignaciones` (useVentas:145), `configuracion_pais`, `cuentas_bancarias_pais`, `planes_configuracion`, `planes_publicidad_config`, `empresas_proveedoras`, `solicitudes_campana`, `pagos_proveedor`. Confirmado por probe solo `campanas_publicitarias` (P57/P58). **Recomendación: correr probes negativos (no-super_admin INSERT/UPDATE/DELETE) para el resto.**
- `UsuariosAdminPage.insert(perfiles)` con `id: crypto.randomUUID()` (`:97-106`): crea perfil **sin** `auth.users` (huérfano sin login). Contrasta con la edge `crear-empleado`. ¿Bug o intencional?
- Aislamiento por país: el super_admin global ve todo (consistente con rol único). Si hubiera `admin_pais` futuro, todas las lecturas/escrituras globales violarían I4.

**Incompletos / dead code:** `ReportesPage` depende de 3 edges (`reportes-resumen/detalle`, `exportar-csv`) no enlazada en Sidebar → candidata a stub (`alert()` `:159`, refs hardcodeadas `:22`). `ReportesEzPayPageV2` con `console.log` debug `:108-110` y bloque debug en UI `:234-237`. **Triple versión de reportes**: `ReportesEzPayPage` = operativa (directo a `transacciones`); V2 = edge no verificable; `ReportesPage` (ruteada 3×) = stub como reporte admin. `AdminEzPayPage` con datos mock (`:243-251` actividad, `:275-276` `Math.random()`). Tasas hardcodeadas: PaisesPage `:100-105,113`, FinanzasPage `:110`. URLs registro hardcodeadas (InvitacionesMedicos/Clinicas `:116/:117`). `useMetricasCampanaAdmin:108` `usuarios_unicos:0`. `useAdminAuth` ~25 `console.log`.

---

### 2.2 Proveedores (`src/proveedor/`)

**Guard:** `ProveedorPrivateRoute.tsx:15` (sesión + `cuentas_proveedor` activa). 7 roles en `permisos.ts`; cada página admin verifica `puede(...)` (gating UI correcto). Notifs/roles/chat **por RPC DEFINER gateado** (`notificar_visita_propuesta/_resultado/_campana_enviada/_chat_interno`, `cambiar_rol_proveedor`, `invitar_miembro_proveedor`).

**🔴 RIESGO**
- **R5 [seguridad, I2 sistémico] — escrituras directas a tablas sensibles (no por RPC), actor/estado fijados por cliente.** `visitas_agendadas` INSERT `useVisitasAgendadas.ts:183`, UPDATE `:290,343,455,476` (cliente fija estado/`propuesta_por`/`aprobada_por`); `planes_asignaciones.visitas_usadas` editado desde cliente `:226,303,353` (bolsa manipulable + races); `solicitudes_campana` `useSolicitudesCampana.ts:65,137,153` y `PagoCheckoutPage.tsx:49-51` (cliente fija `estado:'enviada', monto_pagado`); `pagos_proveedor` INSERT `usePagosProveedor.ts:80-92`; `productos_empresa` `:65,119,177,194`; `ubicaciones_medico_proveedor` `useUbicacionesMedico.ts:64,77,104`; `equipos_visitadores` `EquiposPage.tsx:49`; `empresas_proveedoras`/`cuentas_proveedor` `useProveedorAuth.ts:146,166`. *El archivo sin commit `134_hardening_insert_visitas_cuenta_empresa.sql` indica que este frente está en curso.*
- **R6 [seguridad, I7] — buckets PÚBLICOS con contenido sensible.** `evidencias-visitas` público (`014_…:54`, nunca flipeado): fotos de check-in en consultorios subidas con `getPublicUrl` (`useVisitasAgendadas.ts:438`) y servidas como `<img>` directo (`ProveedorReporteVisitasPage.tsx:183-186`) → accesibles por URL sin auth. `campanas` público (`011_…:8`) — aceptable si el banner es público por diseño (sin PHI; confirmar). `productos` público — probablemente intencional (catálogo). `comprobantes` **OK** (privado+signed), defecto menor: la subida aún llama `getPublicUrl` `usePagosProveedor.ts:76` y guarda esa URL muerta (rescatada por `extractPath`).
- **R7 [seguridad, I5] — aislamiento cross-empresa depende solo del `.eq('empresa_id', empresa.id)` del cliente.** Ubicuo (`useProductosEmpresa.ts:19`, `useSolicitudesCampana.ts:19`, `usePagosProveedor.ts:31`). Casos sin `empresa_id` en el query (100% RLS): `VisitadorDetallePage.tsx:48-59`, `ProductoFormPage.tsx:41-45`, `PublicidadCampanaFormPage.tsx:60-64`. Confirmar RLS fail-closed.
- **R8 [funcionalidad, I4] — `PublicidadPlanesPage.tsx:10` llama `usePlanesPublicidad()` sin paisId** → muestra precio base, no localizado (`:67`). No es fuga; rompe monetización por país en esa pantalla (el form sí lo hace bien).

**🟡 A REVISAR:** `notificar-email` + `buildHtml*` (`notificaciones.ts`) incluyen nombre de médico/fecha/notas en el cuerpo del **email** (no notif in-app) — confirmar si cuenta como PHI bajo I8. `isEditor` (`useProveedorAuth.ts:184`) excluye al `gerente` afín que sí tiene `empresa.editar` → no puede editar perfil.

**Incompletos / bugs:**
- **CRASH [funcionalidad] — `toast` no importado.** `PublicidadCampanasPage.tsx:135` usa `toast?.error?.(...)` sin `import` de sonner → `ReferenceError` al pulsar "Pagar y enviar" sin precio de plan.
- **Ruta 404 — "Editar campaña."** `PublicidadCampanasPage.tsx:148` enlaza `/publicidad/campanas/:id/editar`, ruta inexistente en `App.tsx:334-337` (solo `/nueva`). El form ya implementa modo edición (`PublicidadCampanaFormPage.tsx:57-90`) pero es inalcanzable.
- Tailwind `bg-[164a70]` sin `#` (`PublicidadCampanasPage.tsx:57`). Imports muertos `AdminVisitadoresPage.tsx:1,11`. `crearProductosMasivo` no setea `pais_id` (`useProductosEmpresa.ts:105`).

**Verificación de pistas conocidas (lo que el código realmente muestra):**
- "Ver detalle en blanco" en visita-aprobar: **REFUTADO** — es chevron expand/colapsar con detalle inline (`AdminAprobarVisitasPage.tsx:105-196`).
- Botón Rechazar deshabilitado: **REFUTADO** (`:177` solo `disabled={saving}`). *Matiz:* el campo comentario solo aparece dentro de "Modificar", así que Rechazar directo manda `comentario` vacío (`:47`) → no se captura motivo de rechazo.
- `accion_url` de visita: **CONFIRMADO** — email de propuesta enlaza `/proveedor/visitador/admin-aprobar` (`notificaciones.ts:47`) pero la ruta real es `/proveedor/visitador/aprobar` (`App.tsx:328`). Link a ruta inexistente. (Las notifs in-app van por RPC, no por este helper.)
- Visitador cancela → admin no avisado: **CONFIRMADO** — `cancelarVisita` (`useVisitasAgendadas.ts:269-313`) hace el UPDATE pero no emite ninguna notificación al admin/supervisor. Cancelación silenciosa.

---

### 2.3 Laboratorios Clínicos (`src/laboratorio/`)

**Guard:** `LaboratorioPrivateRoute.tsx:22` (`empresa.tipo==='laboratorio_clinico'`). Sin edges service_role en el panel (I9 OK).

**🔴 RIESGO / BUG ABIERTO**
- **R9 [seguridad+bug, I7] — subida de resultados (PHI) falla con "new row violates row-level security policy" + guarda URL pública en bucket privado.** `useLaboratorio.ts:133-141` (`subirArchivo`): `:139` usa `getPublicUrl` sobre `resultados-examenes` **privado** (mig 074) → guarda URL pública inútil en `examenes.archivo_url` (los lectores la toleran vía `extractPath` `signedUrl.ts:7`, "funciona por accidente"). El **error RLS** del INSERT/UPDATE en storage: el path `${labId}/...` con `labId=empresa.id` es estructuralmente idéntico al de `comprobantes` (que sí funciona) y la policy `resultados_scoped_insert` (`074:73-81`) matchea cuando `mi_empresa_proveedor()` no es NULL. **Causa probable (a verificar, no fix): (a)** `mi_empresa_proveedor()` devuelve NULL para la cuenta de prueba (cuenta sin fila activa en `cuentas_proveedor`, o se probó como super_admin) → fail-closed → viola RLS; **(b)** policy 074 no aplicada en ese entorno. → **Verificar:** `pg_policies` de `storage.objects` + `select mi_empresa_proveedor()` autenticado como la cuenta que falla. **Sin opción de borrar archivo:** confirmado, DELETE en el bucket está denegado por diseño (`074:135`) y no hay RPC/UI.
- **R10 [seguridad, I2] — escrituras directas a `examenes`/`ordenes_examen` (PHI).** `useLaboratorio.ts:126` (cambiarEstado), `:149` (subirResultado UPDATE), `:220,243` (walk-in INSERT). Permitido por la policy `examenes_laboratorio_all` (`062:106-109`, FOR ALL por `laboratorio_id=mi_empresa_proveedor()`). Desviación literal de I2 (confía en RLS por empresa, no RPC).

**✅ OK destacado:** `notificar_resultado_examen` **vigente = mig 130** (no la 062 vieja con PHI): DEFINER sp'', gate fail-closed, cuerpo **genérico sin tipo/nombre** (I8 OK). Aislamiento cross-lab por `.eq('laboratorio_id')` + `notificar_orden_lab` (124) deniega multi-lab fail-closed. Lectura de adjuntos por signed URL (`LabOrdenesPage.tsx:182`).

**Incompletos:** `LabDashboard.tsx:14-16` filtra por `o.estado` que **no existe** en `OrdenAgrupada` → 3 conteos siempre 0. `getPublicUrl` en bucket privado (`:139`). Sin borrar/reemplazar adjunto (objetos huérfanos al re-subir). Param `tipo` muerto en `subirResultado` (`:143`). `notificar_laboratorio` (mig `062:268-280`) **sin gate de actor** — sin callers en el panel-lab; posible dead/legacy (¿callers en médico/clínica?).

---

### 2.4 Farmacias (`src/farmacia/`)

**✅ Núcleo (Inc.4/Frente B) sólido:** toda dispensación por RPC DEFINER gateado — `registrar_dispensacion` (`085:155`), `registrar_dispensacion_dirigida` + walk-in (`090`): validan `auth.uid()` (I3), `tiene_permiso('recetas_dispensar')`, `mi_empresa_proveedor()`, y filtran `receta_items` por `f.empresa_id=v_emp` **por ítem** + un-solo-uso (I5). `REVOKE INSERT,UPDATE,DELETE ON dispensaciones` aplicado (`085:83`); front nunca inserta directo (I2 OK). Edges viejas stub-410 **no invocadas** (I9 OK); `DispensarRecetaPage.tsx` 100% estático (cierra leak de token en URL); token walk-in tratado como secreto (`EscanearQRModal.tsx:25,98`). CSV por `cargar_catalogo_farmacia` gateado (`087:33-39`); reportes k-anónimos por RPC. **Sin storage en el panel** (I7 no aplica).

**🔴 RIESGO**
- **R11 — ❌ FALSO POSITIVO (corrección 2026-06-23, verificado en BD viva + probes red-first).** El hallazgo original leyó **mig 078** (versión superseded). La policy VIVA `farm_med_tenant_all` **SÍ gatea la escritura** por `COALESCE(private.tiene_permiso('inventario_editar'),false)` en **USING y WITH CHECK** — añadido en **mig 079** (`:97`), reforzado en **mig 114** (`:52,58`). Probes en vivo: cajero (sin `inventario_editar`, `sucursal_id=NULL`) → INSERT/UPDATE/DELETE **DENEGADOS** (42501 / 0 filas); SELECT del cajero PASA (vía `farm_med_propia_empresa`); admin (con permiso) escribe OK. El comentario `086:65` `[inventario_editar + empresa]` es **CORRECTO**, no drift. No hay gap ni fix pendiente. (Residual menor aparte: `anon` tiene grants de tabla INSERT/UPDATE/DELETE inertes bajo RLS → REVOKE defensa-en-profundidad, en evaluación.) **Hallazgo original conservado abajo para trazabilidad:**
  - ~~[seguridad, I2/permiso-fila] — escrituras de inventario directas sin gate `inventario_editar` server-side.~~ `FarmaciaInventarioPage.tsx:62-63,72,81-84`: `.from('farmacia_medicamentos').insert/update()` directo. ~~La RLS `farm_med_tenant_all` (`078:35`) es `FOR ALL` y solo verifica **pertenencia a la empresa**, **no** `inventario_editar`~~ (← leyó mig 078, superseded). La UI oculta los controles a roles sin permiso (`:36,105`). ~~El comentario `086:65` afirma una gate de permiso que el SQL no impone (drift).~~ El path CSV sí la exige.

**🟡 A REVISAR**
- `src/pages/FarmaciasPage.tsx` (`/farmacias`, editor de catálogo super_admin médico, **fuera** del portal tenant): INSERT/UPDATE/DELETE directos a `farmacias`/`farmacia_medicamentos` sin filtro de empresa en cliente (`:132-135,172-176,248-252`), depende 100% de la RLS `editar_medicamentos`. Comparte tabla con el inventario tenant. Confirmar que esa policy exige super_admin.

**Incompletos:** `useRecetasEntrantes.ts:53-57` (`detalle`) cableado sin consumidor (dead). `/farmacia/pagos` monta `ProveedorPagosPage` genérico (¿stub?); menú "Pagos" gateado por `finanzas_reportes` (`FarmaciaLayout.tsx:20`, proxy raro). Link de invitación a `/proveedor/registro-visitador` (`FarmaciaPersonalPage.tsx:82`, naming no especializado; el RPC fija empresa+rol → no es brecha).

---

### 2.5 Clínica / Empresas afines (`src/clinica/`, afín en `/proveedor/*`)

**Afín:** blindado por migs 083/084 (barrera producto↔médico vía `private.empresa_es_afin`, anti-auto-aprobación de publicidad, alta/invitación data-driven, puerta lateral legada cerrada). **OK.**

**Clínica — 🔴 RIESGO CRÍTICO (verificado contra BD viva 2026-06-22):**
- **R12 [seguridad, I3/I5/I8] — `obtener_citas_clinica(uuid)` SIN autorización + `EXECUTE` a `anon` Y `authenticated`.** `039_fix_clinica_id_uuid.sql:263-313` (definición vigente, nunca redefinida). `SECURITY DEFINER`, `tiene_gate=false` (no verifica que el caller pertenezca a la clínica), filtra solo `c.clinica_id=p_clinica_id`. Devuelve **PII de pacientes** (nombre, apellido, teléfono, email, `auth_user_id`). **Cualquier usuario — incluso sin autenticar (anon) — puede enumerar las citas de cualquier clínica** pasando otro `clinica_id`. Consumido en `useClinicaCitas.ts:86`. **Verificado live:** `exec_anon=true, exec_auth=true, tiene_gate=false`.
- **R13 [seguridad, I5] — `obtener_medicos_clinica(uuid)` sin gate.** `039:211-225`. `exec_auth=true, tiene_gate=false` (verificado live). Enumera médicos de cualquier clínica.
- **R14 [seguridad, I3] — `obtener_clinica_usuario(uuid)` acepta UUID arbitrario.** `039:318-342`. `SECURITY DEFINER` sin `p_user_id=auth.uid()`. Descubre a qué clínica pertenece cualquier usuario. Es base de `mi_clinica_id()`/`clinicas_del_usuario()` (esos lo llaman con `auth.uid()`, pero el RPC queda invocable directo con cualquier UUID). Usado en `useClinicaAuth.ts:54`, `useClinicaCitas.ts:32`.

> **Contexto:** R12-R14 son agujeros **pre-existentes (mig 039)** que el endurecimiento push-tx (067-136) **no cubrió** — están fuera de su alcance. `obtener_personal_clinica` (mig 082) sí recibió el patrón `clinicas_del_usuario()` + `REVOKE`; las tres de citas/médicos/usuario quedaron sin blindar. **Corregirlas es trabajo NUEVO (no relaja nada del marco); requiere Oscar+revisor.**

**🔴 otros RIESGO**
- **R15 [seguridad, I3] — `actualizar_clinica` gate por pertenencia, no por rol.** `044:8-39` autoriza a cualquier `medico_clinicas.medico_id=auth.uid()` → un médico común edita nombre/dirección/tel/email de la clínica. `ClinicaConfiguracionPage.tsx:34`.

**🟡 A REVISAR**
- **R16 [funcionalidad/I1] — `clinicas` SELECT solo super_admin** (`076:46-48`); `useClinicaAuth.ts:64` hace `.from('clinicas').select().eq('id')` → para `admin_clinica` devolvería 0 filas ("No se encontró clínica"). Confirmar con QA si admin_clinica realmente ve su clínica (puede haber otra policy no detectada) o si falta una.
- R17 [seguridad, defensa-en-profundidad] — `ClinicaInvitarLaboratorioPage.tsx:28` `.select()` sin `.eq('clinica_id')`; mitigado por RLS `inv_lab_clinica_all`.

**✅ OK:** `obtener_personal_clinica` (082, gateado+REVOKE); `actualizar_estado_cita`/`asignar_medico_cita` (071, `es_admin_clinica`); `notificar_cita_paciente` (122, DEFINER sp'', gate actor, sin PHI); `crear-staff-clinica` (edge valida rol+pertenencia antes de service_role, I9 OK); RLS `disponibilidad_medico`/`citas`/`recetas`/`pacientes` con aislamiento cross-clínica real.

**Incompletos:** `useClinicaCitas.ts:195-211` firma muerta (`_pacienteAuthId`,`_medicoNombre`). `ClinicaInvitarStaffPage.tsx:56-63` muestra **contraseña temporal en toast** si Resend falla. `disponibilidad_medico` exige rol `admin_clinica` exacto (058) → `gerente`/staff no gestiona horarios (¿intencional?).

---

## 3. Recomendaciones priorizadas

> Ninguna se implementa aquí. `[etiqueta]` + nota de si toca el marco endurecido.

### P0 — Seguridad crítica (exposición a terceros, verificada)
1. **[seguridad] R12 — `obtener_citas_clinica` abierto a `anon`+`authenticated` sin gate, filtra PII de pacientes cross-clínica.** `mig 039:263`. Trabajo NUEVO (no relaja nada): aplicar patrón `clinicas_del_usuario()` + `REVOKE EXECUTE FROM PUBLIC, anon` como en `obtener_personal_clinica` (082). **Evaluar con revisor.**
2. **[seguridad] R13 — `obtener_medicos_clinica` sin gate.** `mig 039:211`. Mismo patrón. NUEVO.
3. **[seguridad] R14 — `obtener_clinica_usuario` acepta UUID arbitrario.** `mig 039:318`. Exigir `p_user_id=auth.uid()` (salvo super_admin) o ignorar el param. NUEVO.

### P1 — Seguridad alta
4. **[seguridad] R4 — auditoría con `ANON_KEY` → actor falsificable.** `useAuditoria.ts:4,54`. Verificar si la edge ata el actor al JWT; usar token de sesión. NUEVO (no toca push-tx).
5. **[seguridad] R15 — `actualizar_clinica` editable por cualquier miembro.** `mig 044:20`. Endurecer a admin_clinica/gerente/super_admin. NUEVO.
6. **[seguridad] R11 — ❌ FALSO POSITIVO (corrección 2026-06-23).** La policy viva `farm_med_tenant_all` ya gatea escritura por `inventario_editar` (USING+WITH CHECK, mig 079/114); probado en vivo (cajero DENEGADO, SELECT/admin OK). Sin fix pendiente. Ver detalle en §2.4. (El original asumía `078:35`, superseded.)
7. **[seguridad] R6/R9 — buckets/PHI: `evidencias-visitas` público; resultados-examen con `getPublicUrl` en bucket privado.** Evaluar privatizar `evidencias-visitas`+signed (I7) y guardar **path** (no URL pública) en lab. NUEVO. *El bug de subida de resultados (R9) necesita primero el diagnóstico de entorno/cuenta antes de cualquier cambio.*

### P2 — Seguridad media / decisión de arquitectura
8. **[seguridad] R5/R7/R10 — escrituras directas a tablas sensibles (visitas/pagos/campañas/productos/examenes) confiando en RLS.** Decisión Oscar+revisor: ¿RLS suficiente o migrar a RPC DEFINER (como notificaciones)? El frente ya está abierto (`134_…sql` sin commit). **No relaja nada; es completar I2.**
9. **[seguridad] R2 — Admin publica campaña por INSERT directo en vez de `aprobar_solicitud_campana`.** `PagosProveedoresPage.tsx:121`. Atomicidad + país. NUEVO.
10. **[seguridad] R3 — edge `notificar-admin` con contenido del cliente.** `useVentas.ts:162`. Confirmar si valida/sanitiza o migrar a RPC. NUEVO.
11. **[seguridad] verificar policies (R1 + A-REVISAR Admin):** correr probes negativos no-super_admin para `perfiles`, `usuario_roles`, `planes_asignaciones`, `configuracion_pais`, `cuentas_bancarias_pais`, `planes_publicidad_config`, `notificaciones`. Cierra la duda de "directo pero ¿RLS fail-closed?".

### P3 — Funcionalidad (bugs que rompen flujo)
12. **[funcionalidad] crash `toast` no importado** — `PublicidadCampanasPage.tsx:135`.
13. **[funcionalidad] "Editar campaña" → 404** (ruta faltante) — `PublicidadCampanasPage.tsx:148` / `App.tsx:334`.
14. **[funcionalidad] `accion_url` de email de visita a ruta inexistente** — `notificaciones.ts:47` (`admin-aprobar` vs `aprobar`).
15. **[funcionalidad] visitador cancela → admin no recibe aviso** — `useVisitasAgendadas.ts:269`.
16. **[funcionalidad] dashboard lab: conteos siempre 0** — `LabDashboard.tsx:14`.
17. **[funcionalidad] motivo de rechazo no capturable desde botón Rechazar** — `AdminAprobarVisitasPage.tsx:47,148`.
18. **[funcionalidad] R16 — admin_clinica quizá no ve su clínica** (`clinicas` SELECT solo super_admin) — verificar QA.
19. **[funcionalidad] R8 — publicidad sin precio localizado por país** — `PublicidadPlanesPage.tsx:10`.

### P4 — Limpieza / dead code
20. **[limpieza]** Triple reportes admin (retirar `ReportesPage`/V2 si las edges no existen); mocks en `AdminEzPayPage`; `console.log` debug (`useAdminAuth`, ReportesV2).
21. **[limpieza]** `notificar_laboratorio` sin gate y sin callers (¿eliminar? — análogo a `notificar_paciente`/`notificar_laboratorio` del CIERRE FINAL). **Toca el área endurecida → revisor.**
22. **[limpieza]** firmas/params muertos (`useClinicaCitas.ts:195`, lab `subirResultado tipo`, `useRecetasEntrantes detalle`), imports muertos, tasas hardcodeadas, contraseña-en-toast (`ClinicaInvitarStaffPage.tsx:56`).

### Preguntas abiertas para Oscar (no faltantes confirmados)
- ¿`admin_pais` en roadmap? (cambiaría I4 en todo el panel admin).
- ¿`UsuariosAdminPage` debe crear login o son perfiles fantasma?
- ¿`gerente` afín debe editar perfil de empresa? ¿`gerente`/staff clínica gestionar horarios?
- ¿`/farmacia/pagos`, `/farmacia/notificaciones`, `FarmaciasPage` legacy: funcionales o stubs a retirar?
- ¿Se quiere borrar/reemplazar resultados de examen (hoy DELETE denegado por diseño)?

---

## 4. Cruce con el CIERRE FINAL (Paso 3)

Grep sobre todo `src/` (invoke/rpc/fetch reales, excluyendo comentarios): **0 callers rotos.**

| Símbolo retirado | Callers vivos |
|---|---|
| edge `enviar-push` (stub-410) | 0 ✓ |
| edge `enviar-notificacion` (stub-410) | 0 ✓ |
| RPC `notificar_paciente` (EXECUTE revocado) | 0 ✓ |
| RPC `notificar_laboratorio` (dropeado) | 0 ✓ |
| helper `crearNotificacion` (borrado) | 0 ✓ |
| helper `crearNotificacionInApp` (borrado) | 0 ✓ |

Las únicas coincidencias residuales son **comentarios descriptivos** ("Reemplaza … enviar-notificacion + enviar-push"). El CIERRE FINAL no dejó ningún módulo con caller roto.

---

*Fin del documento. Nada de lo aquí listado se ha implementado; cada recomendación requiere evaluación de Oscar + revisor antes de cualquier cambio.*
