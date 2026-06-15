# Propuesta de diseño — Paneles "Empresas Afines" y "Farmacias"

> **Estado:** DISEÑO APROBADO — D1–D4 resueltas (§4). **Inc.0 ✅ HECHO** (migración `077`, harness
> P1–P64 verde, en `seguridad/rls-remediacion`). Inc.1+ pendientes, irán en rama de paneles aparte.
> Todo el modelo de datos es **aditivo** sobre la empresa proveedora existente.

---

## 0. Premisa

Los dos paneles **no son entidades nuevas**: son dos valores más de `empresas_proveedoras.tipo`
(`empresa_afin`, `farmacia`), que **ya existen en datos** (1 fila c/u). Reutilizan `cuentas_proveedor`,
`useProveedorAuth`, el sistema de roles `rol_en_empresa` y los helpers `mi_empresa_proveedor()` /
`mi_rol_proveedor()`. El portal de **laboratorio clínico** (`/laboratorio/*`) es la plantilla probada:
mismo auth, portal separado, routing por `tipo`.

---

## PASO 1 · Inventario de lo existente

### 1.1 Modelo de empresa proveedora (núcleo reutilizable)
| Tabla | Rol en el modelo | Notas |
|---|---|---|
| `empresas_proveedoras` | la empresa (tenant). `tipo` discrimina el portal | `tipo`: `laboratorio_clinico`, `laboratorio_farmaceutico`, `farmacia`, `empresa_afin`. **`tipo`/`estado` son TEXTO LIBRE, sin CHECK** (fail-open latente). `pais_id` presente. |
| `cuentas_proveedor` | usuario de la empresa | `empresa_id`, `rol_en_empresa`, `activo`, `pais_id`, `equipo_id`. `id = auth.uid()`. |
| Roles (`rol_en_empresa`) | RBAC por empresa | Catálogo en `src/proveedor/lib/permisos.ts`: `admin, supervisor, visitador_medico, catalogo, marketing, finanzas, lectura` (+ legacy `editor/viewer`). **No hay catálogo de roles en BD** (solo en TS). |
| Helpers | `mi_empresa_proveedor()`, `mi_rol_proveedor()`, `supervisa_cuenta_proveedor()` | SQL `id=auth.uid() AND activo`. Son la base del scoping por empresa. |

### 1.2 Frontend (arquitectura multi-portal)
- **Portal proveedor** `/proveedor/*`: `ProveedorLayout` (sidebar filtrado por `puede(permiso)`), `ProveedorPrivateRoute`, secciones: dashboard, **visitadores/equipos/rutas/ubicaciones**, productos, publicidad, pagos, personal-roles, mensajes, notificaciones, perfil.
- **Portal lab** `/laboratorio/*`: portal separado que **reusa `useProveedorAuth`**; `LaboratorioPrivateRoute` exige `empresa.tipo==='laboratorio_clinico'`; `ProveedorLogin`/`LabLogin` **enrutan por `tipo`**.
- **Registro**: `ProveedorRegistro.tsx` ofrece los 4 `tipo` (incluidos `farmacia`/`empresa_afin`) → RPC `registrar_proveedor(p_tipo)`.
- **Ya hay scaffolding parcial** para los dos tipos: iconos/labels en `EmpresasProveedorasPage`, páginas admin de planes `PlanesFarmaciaConfigPage` / `PlanesEmpresasAfinesConfigPage`, rutas en `App.tsx`. **Falta el portal/tenant en sí.**

### 1.3 Flujo de publicidad (hoy)
1. Proveedor solicita: `PublicidadCampanaFormPage` → escribe `solicitudes_campana` (estados borrador→enviada→en_revision→aprobada→publicada; lleva `plan_publicidad_id`, `monto_pagado`, `comprobante_pago_url`, `notas_admin`).
2. Super_admin aprueba: `SolicitudesCampanaPage` → inserta en `campanas_publicitarias` (`activa=true`).
3. Audiencia ve: `BannerPublicidadGlobal` (webapp + dashboard médico) lee `campanas_publicitarias` activas, filtra por `pais_id`, registra `campana_metricas`.

### 1.4 Farmacias (hoy = catálogo de super_admin, NO tenant)
- `farmacias` (**id `integer`**, sin `empresa_id`) y `farmacia_medicamentos` (`farmacia_id integer`). Gestión: `FarmaciasPage` (super_admin). Lectura pública para la búsqueda de disponibilidad del médico (`BuscarMedicamentosPage`, empareja por nombre contra `farmacia_medicamentos` + `productos_empresa`).
- **No existe portal de farmacia ni membresía**: las farmacias no tienen `cuentas_proveedor` ni vínculo a `empresas_proveedoras`.

### 1.5 ⚠️ Estado de seguridad del esquema transaccional (la pregunta clave)
**Parcialmente asegurado.** Lo que sí pasó por el endurecimiento del panel proveedor (migración 050) está scopeado; lo adyacente NO:

| Tabla | Estado | Política efectiva |
|---|---|---|
| `pagos_proveedor` | ✅ **ASEGURADO** | INSERT/SELECT `empresa_id = mi_empresa_proveedor()` + rol ∈ (admin/editor/finanzas/marketing/supervisor); super_admin ALL. |
| `productos_empresa` | ✅ **ASEGURADO** | ALL `empresa_id=mi_empresa_proveedor()` + rol (admin/editor/catalogo); SELECT propio + médico-activo + super_admin. |
| `solicitudes_campana` | ✅ **ASEGURADO** | INSERT/UPDATE `empresa_id ∈ mis empresas` + rol (admin/editor); SELECT propio; super_admin ALL. |
| `planes_visitador_contratados` | ✅ **ASEGURADO** | SELECT empresa propia; super_admin ALL (sin ALL abierto). |
| `planes_asignaciones` | 🔴 **HUECO** | Tiene `[ALL] auth.role()='authenticated'` → **cualquier autenticado lee/escribe TODAS** las asignaciones (la SELECT scoped queda anulada por la permisiva). |
| `campanas_publicitarias` | 🔴 **HUECO** | INSERT `CHECK auth.uid() IS NOT NULL`; UPDATE/DELETE `USING auth.uid() IS NOT NULL` → **cualquier autenticado publica/edita/borra anuncios**. (La lectura de audiencia sí está bien: `activa AND fecha_fin>=hoy AND pais_id propio`.) |
| `campana_metricas` | 🟡 menor | INSERT cualquier autenticado (tracking, spoofeable); SELECT solo super_admin → **la empresa NO ve métricas de SUS campañas** (gap funcional, no de seguridad). |
| `farmacia_medicamentos` / `farmacias` | 🟡 catálogo | `Allow anon read USING true` → lectura mundial; escritura solo super_admin. Aceptable como catálogo, pero **sin scoping de tenant** (no hay write por farmacia). |

**Conclusión:** `pagos_proveedor` y el catálogo de productos/solicitudes están bien y se pueden clonar tal cual. **`planes_asignaciones` y `campanas_publicitarias` son huecos**: si clonamos el flujo sin más, replicamos el hueco. La propuesta los cierra **antes** de enchufar dinero real.

---

## PASO 2 · Diseño propuesto (datos + autorización), sin código

### 2.1 Modelo de datos (todo ADITIVO)

| Cambio | Tipo | Motivo |
|---|---|---|
| **CHECK/catálogo de `tipo`** en `empresas_proveedoras` (y `estado`) | aditivo | Cierra el fail-open de texto libre (mismo patrón que `roles_catalogo`+FK de Fase 6). Restringe `tipo ∈ {laboratorio_clinico, laboratorio_farmaceutico, farmacia, empresa_afin}`. Pre-vuelo: los 4 valores actuales ya son válidos. |
| **`farmacias.empresa_id uuid NULL` → FK `empresas_proveedoras(id)`** | aditivo | Convierte cada farmacia-catálogo en tenant: la liga a una empresa `tipo='farmacia'`. Nullable para no romper las filas catálogo existentes; se puebla al onboarding. |
| **Reusar `productos_empresa` para Afines** | sin cambio de tabla | Ya scopeado por empresa. Campos pharma (`principio_activo`, `requiere_receta`) quedan opcionales para afines. *(Ver decisión D1.)* |
| **Reusar `pagos_proveedor` / `solicitudes_campana` / `campanas_publicitarias`** | sin cambio | El flujo transaccional y de publicidad es idéntico por `empresa_id`. |
| **(Opcional) `planes_*_contratados` para farmacia/afín** | aditivo, futuro | Si su suscripción necesita registro propio, clonar el patrón **asegurado** de `planes_visitador_contratados` (NO el de `planes_asignaciones`). |

**No se reestructura** ninguna tabla con políticas vigentes; solo se añaden columnas nullable, constraints y políticas nuevas que coexisten.

### 2.2 Cierre de los huecos antes de clonar (parte del diseño)
- **`campanas_publicitarias`**: quitar el INSERT/UPDATE/DELETE abierto. La publicación pasa a una **RPC `SECURITY DEFINER` `aprobar_solicitud_campana(p_solicitud_id)`** que: revalida `private.tiene_rol(['super_admin'])` (con `COALESCE(...,false)`), valida que la solicitud esté en estado pagado/en_revision, inserta la campaña y marca la solicitud `publicada`. `REVOKE` de anon/authenticated sobre el INSERT directo. La lectura de audiencia se mantiene igual.
- **`planes_asignaciones`**: eliminar la política `[ALL] authenticated` y dejar SELECT scoped por empresa + escritura solo vía RPC/super_admin (igual que `planes_visitador_contratados`). Esto es prerequisito para que farmacia/afín contraten planes sin exponer los de otros.
- **`campana_metricas`** (menor): añadir SELECT para que la empresa vea métricas de SUS campañas (`campana_id ∈ campañas de mi empresa`), sin tocar el INSERT de tracking.

### 2.3 Autorización por panel (RLS + helpers + RPCs)
**Principios (heredados de la remediación):** toda política nueva scopea `empresa_id = mi_empresa_proveedor()`; toda RPC que MUTA es `SECURITY DEFINER` + `search_path=''` + **revalida el caller** + `COALESCE(predicado, false)` en cualquier comparación que pueda dar NULL (lección del fail-open trivaluado de la pasada definer).

- **Empresas Afines** — reusa roles `admin, catalogo, marketing, finanzas, lectura` (NO visitador/supervisor). Políticas reutilizadas tal cual: `productos_empresa`, `pagos_proveedor` (ya cierran por `mi_empresa_proveedor()`+rol), `solicitudes_campana`. No requiere RPCs nuevas salvo la de aprobación de campaña (compartida).
- **Farmacias** — reusa roles `admin, catalogo` (inventario), `finanzas`, `lectura`. Nuevas políticas **scoped por la farmacia de la empresa**:
  - `farmacia_medicamentos`: añadir `ALL` con `USING/CHECK (farmacia_id IN (SELECT id FROM farmacias WHERE empresa_id = mi_empresa_proveedor()))` + rol (admin/catalogo). **Mantener** la lectura pública existente (la búsqueda de disponibilidad del médico no se rompe).
  - `farmacias`: añadir UPDATE de su propia fila (`empresa_id = mi_empresa_proveedor()`), manteniendo el catálogo super_admin.
  - RPC `onboarding`: ligar una `farmacias` (nueva o existente) a la empresa al registrarse (SECURITY DEFINER, revalida que el caller sea admin de esa empresa).

### 2.4 Flujo de publicidad (reglas)
1. Empresa (afín/farmacia, rol admin/marketing) crea **solicitud** → `solicitudes_campana` (ya scopeado). Sube comprobante a `comprobantes` (bucket privado, ya scopeado en Fase 5).
2. Super_admin aprueba/rechaza vía RPC `aprobar_solicitud_campana` (2.2).
3. Solo estado **`publicada`/`activa`** se vuelve visible: la audiencia (clínicas/pacientes/médicos) lee `campanas_publicitarias` **únicamente** por `activa AND fecha_fin>=hoy AND pais_id propio` (ya implementado).
4. **Separación contenido vs datos del plan**: el **anuncio** (`campanas_publicitarias`: título, imagen, link, segmentación) es lo único público; los **datos del plan/pago** (`solicitudes_campana`: monto, comprobante, estado, notas_admin) quedan privados (proveedor dueño + super_admin). Segmentación por país ya soportada (`pais_id`, `edad`, `genero`, `condicion_filtro`).

### 2.5 Flujo de transacciones (ficticio por ahora, scopeado por empresa)
- Reusar `pagos_proveedor` tal cual (ya asegurado): la empresa crea su pago con comprobante, super_admin verifica. Funciona idéntico para afín/farmacia con solo darles `cuentas_proveedor`.
- Si necesitan registro de plan contratado, clonar el patrón **asegurado** (`planes_visitador_contratados`: SELECT empresa propia + super_admin ALL), **nunca** el de `planes_asignaciones`.

### 2.6 Diferencias por panel
| | Empresas Afines | Farmacias |
|---|---|---|
| Naturaleza | Panel de proveedor **con menos secciones** | Catálogo super_admin → **tenant con membresía** |
| Portal | Opción A (recomendada): **mismo `/proveedor/*`**, ocultando visitadores/equipos/rutas por `tipo`+`puede()`. Opción B: portal dedicado `/afin/*` (como lab). | Portal dedicado **`/farmacia/*`** (patrón lab): `FarmaciaLogin/Registro/Guard` que enruta por `tipo='farmacia'`. |
| Secciones | dashboard, **productos**, publicidad, pagos, personal-roles, perfil, mensajes | dashboard, **inventario** (`farmacia_medicamentos` scoped), pagos, publicidad (opcional), personal, perfil |
| Datos nuevos | ninguno (reusa `productos_empresa`) | `farmacias.empresa_id` (vínculo tenant) |
| Roles | admin, catalogo, marketing, finanzas, lectura | admin, catalogo, finanzas, lectura |

---

## 3. Riesgos al añadir el tipo + mitigaciones
1. **Routing por `tipo`**: hoy `ProveedorLogin` solo separa lab vs proveedor. Si no se añade el ruteo+guard para `farmacia` (y afín si va a portal propio), esos usuarios caen en `/proveedor/*` y **ven secciones de visitador**. → Mitigar: guard análogo a `LaboratorioPrivateRoute` por `tipo`, + gating de nav por `tipo`.
2. **`tipo`/`estado` sin CHECK** (fail-open de datos, misma clase que cerramos en Fase 6). → Mitigar: CHECK/catálogo (2.1) con pre-vuelo (los 4 valores ya son válidos).
3. **Clonar huecos** `planes_asignaciones` / `campanas_publicitarias`: a más empresas en el flujo, más exposición. → Mitigar: cerrarlos (2.2) **antes** del onboarding.
4. **`productos_empresa` compartido** lab-farmacéutico ↔ afín: la política "Médico ve productos activos" + el match por nombre en `RecetaModal` haría que **productos de afines aparezcan en la búsqueda de medicamentos** del médico. → **Mitigado (D1):** único lector afectado = `useBusquedaMedicamentos` (2 queries que ya traen `empresa.tipo`); se filtra a tipos farmacéuticos en front **y** en servidor. Resto de lectores son del dueño o super_admin (no mezclan).
5. **`farmacia_medicamentos` lectura pública** + `farmacia_id integer` no ligado a empresa: al volverla tenant, las nuevas políticas de escritura no deben romper la lectura de `BuscarMedicamentosPage`. → Mitigar: políticas de escritura **aditivas** (scoped) dejando intacta la SELECT pública.
6. **`get_auth_user_rol()`** (usado por políticas admin) lee `perfiles.rol` sin `search_path=''` endurecido. No es hueco (en USING un NULL deniega), pero conviene migrarlo a `private.tiene_rol` por consistencia. → Mitigar: nota de limpieza, no bloqueante.

---

## 4. Decisiones de producto — RESUELTAS (2026-06-13)
- **D1 ✅ Reusar `productos_empresa` + filtrar (verificando TODOS los lectores).** Auditoría de lectores hecha:
  | Lector | Tipo | ¿Filtro por tipo? |
  |---|---|---|
  | `src/hooks/useBusquedaMedicamentos.ts` (2 queries, l.77 y l.164) | búsqueda de disponibilidad del **médico** | **SÍ — único punto de contaminación.** Ya hace `select('*, empresa:empresa_id(nombre_empresa, tipo)')` → filtrar para excluir `empresa_afin` (mostrar solo tipos farmacéuticos). Cambio mínimo en 2 líneas + defensa en BD. |
  | `src/proveedor/hooks/useProductosEmpresa.ts` (list/insert/update/delete) | gestión del **dueño** | No — scopeado por `mi_empresa_proveedor()`. |
  | `src/proveedor/hooks/useProveedorStats.ts` (l.40), `ProductoFormPage.tsx` (l.42) | stats/form del **dueño** | No — propia empresa. |
  | `src/pages/admin-ezpay/EmpresasProveedorasPage.tsx` (l.80, `count`) | conteo **super_admin** por empresa | No — por empresa, sin mezcla. |
  → Conclusión: **un solo lector** (`useBusquedaMedicamentos`) necesita el filtro; el resto es dueño o super_admin. Refuerzo en BD: el filtro de tipo se replica en la política/consulta del lado servidor para no depender solo del front.
- **D2 ✅ Mismo `/proveedor/*` gateado por `tipo` + scoping RLS por tipo.** Afines vive en el portal proveedor; las secciones de visitador/equipos/rutas/ubicaciones se ocultan por `tipo` (+`puede()`) y, además, las políticas RLS de esas tablas se acotan para que un `empresa_afin` no acceda aunque fuerce la URL/API (defensa en profundidad, no solo UI).
- **D3 ✅ Convivencia catálogo + tenant, con promoción aprobada por super_admin.** Las `farmacias` actuales siguen como catálogo; una farmacia se vuelve tenant cuando el **super_admin aprueba** su promoción (liga la fila `farmacias` a una `empresas_proveedoras` tipo='farmacia' vía `farmacias.empresa_id`). Autorregistro queda como solicitud que el super_admin aprueba (no auto-tenant).
- **D4 ✅ Incremento 0 con probes** (cerrar `planes_asignaciones` y `campanas_publicitarias` ANTES de onboarding).

---

## 5. Plan de construcción por incrementos (aprobado — D1–D4 resueltas)
Cada incremento con su migración + probes (rojo→verde) y el patrón de siempre (mostrar → OK → aplicar staging → harness → commit). Los probes siguen la numeración del harness existente (P1–P54 → P55…).

- **Incremento 0 — Cerrar huecos + blindar `tipo` (D4). ✅ HECHO** (migración `077`, commit `4266216`).
  - `campanas_publicitarias`: INSERT/UPDATE/DELETE abiertos eliminados → escritura solo super_admin; publicación canónica vía RPC `aprobar_solicitud_campana` (SECURITY DEFINER, `search_path=''`, revalida `super_admin` con `COALESCE`; copia `pais_id`). `SolicitudesCampanaPage` migrada al RPC. Lectura de audiencia intacta.
  - `planes_asignaciones`: eliminado `[ALL] authenticated` → `asig_scoped_all` (USING: super_admin / empresa propia / médico dueño). **WITH CHECK separado por tipo de fila** (filas excluyentes verificadas): médico solo su fila sin `empresa_id`, proveedor solo su fila sin `medico_id` → sin forja cruzada.
  - CHECK de `empresas_proveedoras.tipo` al catálogo válido (pre-vuelo: 0 filas inválidas).
  - **Probes P55–P64 verdes** (ajeno NO lee/escribe asignaciones ni campañas; tipo inválido y forja de empresa → BLOQUEADO; proveedor/médico gestionan lo suyo y super_admin publica vía RPC → OK). Suite completa **P1–P64 sin regresión**.
- **Incremento 1 — Farmacia tenant (D3 convivencia + promoción super_admin).**
  - `farmacias.empresa_id` (FK nullable) + RPC `promover_farmacia_a_tenant(p_farmacia_id, p_empresa_id)` (SECURITY DEFINER, solo super_admin) + políticas scoped de `farmacia_medicamentos` (write por `farmacia_id ∈ farmacias de mi_empresa_proveedor()`), **manteniendo** la SELECT pública.
  - **Probes:** farmacia tenant A NO ve/edita inventario de B → BLOQUEADO; admin de A SÍ → OK; médico sigue leyendo disponibilidad (lectura pública intacta) → OK; no-super_admin NO promueve → BLOQUEADO.
- **Incremento 2 — Portal Farmacia `/farmacia/*`** + `FarmaciaLogin/Registro` + guard por `tipo='farmacia'` (patrón `LaboratorioPrivateRoute`) + secciones (dashboard, inventario, pagos, perfil, personal). *(Frontend; sin probes SQL nuevos salvo regresión.)*
  - **DEUDA pendiente de Inc.1 → resolver en Inc.2:** granularidad por **rol interno** de la empresa-farmacia. Hoy (Inc.1) el scoping del tenant es por **membresía de empresa** (`mi_empresa_proveedor`) → *cualquier* miembro activo edita farmacia/inventario. Falta acotar a los roles que correspondan vía `mi_rol_proveedor()` (p.ej. solo `admin`/`catalogo` editan; `lectura` no), igual que `productos_empresa`. Añadir probe: un miembro con rol `lectura` NO edita inventario.
- **Incremento 3 — Empresas Afines (D1+D2).**
  - **D1:** filtrar `useBusquedaMedicamentos` (2 queries) para excluir `empresa_afin` + refuerzo en servidor. Probes: producto de `empresa_afin` NO aparece en la búsqueda de disponibilidad del médico; producto de `laboratorio_farmaceutico` SÍ.
  - **D2:** ocultar visitadores/equipos/rutas/ubicaciones en `/proveedor/*` cuando `tipo='empresa_afin'` **y** acotar esas políticas RLS por tipo. Probes: `empresa_afin` NO accede a visitas/equipos/ubicaciones por API → BLOQUEADO; sí gestiona productos/publicidad/pagos → OK.
- **Incremento 4 — Publicidad para ambos**: usar la RPC de aprobación del Inc.0 + SELECT de `campana_metricas` para que la empresa vea métricas de SUS campañas. Probes: empresa ve métricas propias / no ajenas; audiencia solo ve campañas `activa` de su país.

> **Inc.0 ✅ aplicado en `seguridad/rls-remediacion`** (viaja con el deploy de seguridad). Inc.1+ (construcción de paneles) irá en **rama aparte** desde la base actual cuando se arranque.

---

## 6. Inc.3 — Empresas Afines · DISEÑO (sin código; FASE DE DISEÑO)
Reusa el modelo de empresa proveedora. `empresa_afin` ya es `tipo` válido (datos: 1 empresa, 1 cuenta, 0 productos, 0 roles-seed). **Aislamiento base ya existe:** `mi_empresa_proveedor()` aísla por empresa en `productos_empresa`/`pagos_proveedor`/`solicitudes_campana` → un afín no ve datos de otra empresa (afín/lab/farmacia) sin trabajo extra. Lo "por tipo" solo hace falta donde hay lecturas CROSS-tipo (médico) o gating de secciones.

### 6.1 Gateo `/proveedor/*` por tipo (UI) + RLS por tipo (barrera real)
- **UI (rutina):** ocultar visitadores/equipos/rutas/ubicaciones cuando `empresa.tipo='empresa_afin'`; mostrar dashboard, productos, publicidad, pagos, personal-roles, perfil (reusar `ProveedorLayout`+`puede()`). El guard de UI NO es la barrera.
- **RLS (SEGURIDAD):** auditar que las tablas/RPC de visitador (`visitas_agendadas`, `equipos_visitadores`, `ubicaciones_medico_proveedor`, `planes_visitador_contratados`) **nieguen** a un afín (un afín no tiene filas ahí → da vacío; el probe confirma 0/BLOQUEADO, no fuga).

### 6.2 Catálogo de productos (D1) — reusar `productos_empresa` + filtro por tipo
- Afín gestiona SUS productos (ya scopeado por empresa+rol), sin cambios de tabla.
- **Servidor (SEGURIDAD):** la política `"Médico ve productos activos"` hoy es `USING (estado='activo')` (sin tipo) → los productos de afín aparecerían en la búsqueda de disponibilidad del médico. Cambiar a `estado='activo' AND empresa NO es 'empresa_afin'`. Paquete de revisión.
- **Cliente (rutina):** `useBusquedaMedicamentos` (2 queries) excluye afines (defensa en profundidad).
- **Storefront del afín:** lectura nueva scopeada a los productos activos de ESE afín (no abre `productos_empresa` global).

### 6.3 "Comprar" — RESUELTO: (a) el afín COMPRA PUBLICIDAD a EzPay (NO marketplace)
**Decisión confirmada:** el afín paga a EzPay por **publicidad de sus productos**, que se muestra dentro del software en los **paneles de clínica y paciente**. NO hay compra comprador→afín (sin marketplace, sin tabla de pedidos, se descarta Inc.3.C).
- **Reusa el flujo de publicidad existente:** afín crea `solicitudes_campana` → super_admin aprueba vía `aprobar_solicitud_campana` (Inc.0) → `campanas_publicitarias` (`activa`) → audiencia (`BannerPublicidadGlobal` en webapp/paciente + dashboard de clínica/médico). Pago vía `pagos_proveedor` (asegurado). **Sin tablas nuevas.**
- **Productos del afín** = catálogo en `productos_empresa` (lo que anuncia). Se siembran productos ficticios para pruebas.
- **Nuance de permiso (SEGURIDAD):** la política INSERT/UPDATE de `solicitudes_campana` hoy exige `rol_en_empresa IN ('admin','editor')`. El **admin** del afín ya puede crear campañas; para que el rol **marketing** (data-driven) también pueda, hay que cablear `tiene_permiso('publicidad_gestionar')` en esa política (o dejar MVP = solo admin gestiona, y diferir la granularidad como en farmacia).

### 6.4 Publicidad — reusar Inc.0
Afín (rol marketing) crea `solicitudes_campana` → super_admin aprueba vía `aprobar_solicitud_campana` → solo `activa` visible. Sin tablas nuevas. (Métricas propias = Inc.4.)

### 6.5 Roles admin del afín — data-driven (modelo Inc.2)
Seed `roles_empresa_catalogo`+`permisos_empresa_rol` para `tipo='empresa_afin'`. Matriz propuesta (a confirmar): `admin`(100,es_admin,todas) · `gerente`(80) · `catalogo`(40, productos_editar) · `marketing`(40, publicidad_gestionar) · `finanzas`(40, pagos_ezpay+finanzas_reportes) · `lectura`(10). Acciones: config_empresa, usuarios_roles, productos_editar, publicidad_gestionar, pagos_ezpay, finanzas_reportes (+ ventas si (b)).
- **SEGURIDAD:** `alta_miembro_farmacia` e `invitar_miembro_farmacia` hoy hardcodean `tipo='farmacia'` → **generalizar** a `tipo IN ('farmacia','empresa_afin')` (o cualquier tipo con seed). `asignar_rol_miembro` ya es genérico. Misma jerarquía anti-escalada + último-admin. Paquete de revisión.

### 6.6 SEGURIDAD (paquete de revisión) vs RUTINA
- **SEGURIDAD:** filtro RLS productos-médico por tipo; negación de visitas/equipos/ubicaciones a afines; seed roles afín + generalización de RPC alta/invitar; (si (b)) tabla compra + RLS + RPC.
- **RUTINA:** gating de secciones UI; storefront/catálogo afín; filtro cliente `useBusquedaMedicamentos`; pantallas del panel.

### 6.7 Plan por incrementos
- **Inc.3.A (SEGURIDAD):** seed roles afín + generalizar RPC alta/invitar; filtro RLS productos por tipo; negación visitas/equipos. Probes: afín gestiona productos/publicidad/pagos propios (OK); afín NO ve visitas/equipos/ubicaciones (BLOQUEADO); producto afín NO aparece en búsqueda del médico, lab sí; jerarquía afín (gerente no asigna admin).
  - + seed de productos ficticios del afín (para probar catálogo + filtro del médico).
  - + cablear `tiene_permiso('publicidad_gestionar')` en `solicitudes_campana` (INSERT/UPDATE) → rol marketing granular del afín gestiona campañas. **DECISIÓN: granular.**
- **Inc.3.B (UI rutina):** gating de secciones por tipo + catálogo del afín + pantalla de solicitar campaña (reusa el form de publicidad) + filtro cliente `useBusquedaMedicamentos`. tsc/build + no-regresión P1–P113.
- ~~Inc.3.C~~ descartado (no hay marketplace; "comprar" = publicidad, ver §6.3).

> ✅ Decisiones tomadas: (1) "comprar" = **(a) publicidad** (sin marketplace); (2) matriz de roles afín **aprobada**. Construir por incrementos — SEGURIDAD primero con paquete de revisión.
