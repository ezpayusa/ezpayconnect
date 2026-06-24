# DISEÑO DEFINITIVO — Módulo DELIVERY Fase 1 (+ despacho sin-QR)

> Doc de diseño para revisión. **NO es migración.** Nada aplicado, nada commiteado. Cada ola pasa por revisor + OK de Oscar paso a paso.
> Convenciones del spine: RPCs DEFINER `search_path=''` schema-qualified; escritura SOLO por RPC; RLS `empresa_id=mi_empresa_proveedor() AND COALESCE(private.sucursal_visible(farmacia_id),false)`; gate-antes-de-efecto (l.54); RPC-vivo grandfather-inerte (l.51); CREATE OR REPLACE re-declara DEFINER/sp''/grants (l.50); validación en PREVIEW antes de main (l.25).

---

## 0 · VALIDACIÓN EN VIVO vs decisiones cerradas (2026-06-24)

| Supuesto del diseño | Verificado en vivo | Estado |
|---|---|---|
| `entregas` no existe | 0 tablas | ✅ |
| `receta_items.modalidad` no existe | 0 columnas | ✅ a crear |
| 4 permisos `entregas_*` no existen | `count=0` | ✅ a crear |
| Helpers `sucursal_visible/mi_sucursal/mi_empresa_proveedor/tiene_permiso` | existen | ✅ |
| `dispensaciones` tiene `receta_avanzada_id, farmacia_id, paciente_id, total_dispensado` | sí | ✅ (monto) |
| Bucket evidencia: NO reusar `evidencias-visitas` | `public=true` (confirmado riesgo) | ✅ bucket nuevo privado |
| `geocodificar` vivo | es **EDGE** (`supabase/functions/geocodificar`), no pg_proc | ✅ (orquesta el front) |
| **Ancla `receta_base_id` FK→`recetas(id)`** | ⚠️ **`recetas` PK es COMPUESTO `(id, paciente_id)`** — pero `id` es **independientemente referenciable** (`recetas_avanzadas.receta_base_id` YA hace `FK → recetas(id)`) | ✅ viable (FK a `recetas(id)` OK) |
| Vínculo auth↔paciente para gate del paciente | ⚠️ **NO es `user_id`** → es **`pacientes.auth_user_id`**; además existe helper **`private.paciente_es_mio(paciente_id)`** | ✅ usar el helper |
| `receta_items.receta_id` FK a recetas | ⚠️ **NO tiene FK** (columna suelta, igual que `medicamento_id`) | ⚠️ `entregas` ancla a `recetas(id)` directo, no vía receta_items |
| Punto de auto-create | los RPCs `registrar_dispensacion(_dirigida)` exponen `v_emp`, `v_ra.{paciente_id,medico_id}`, `v_receta_id`; el loop ya filtra `sucursal_visible` (141/143) | ✅ insertar **tras el loop**, reusando el gate |

**Contradicciones marcadas explícitas (no asumidas):**
1. **`recetas` PK compuesto** — la decisión dijo `UNIQUE(receta_base_id, farmacia_id)` sobre `entregas` (correcto, no afecta) y FK a `recetas`. El FK funciona porque `recetas(id)` es único por sí solo (lo prueba `recetas_avanzadas`). **No** se puede asumir `recetas(id)` como PK simple, pero **sí** como destino de FK.
2. **`pacientes.auth_user_id`** (no `user_id`) — la decisión de gate del paciente se implementa con `private.paciente_es_mio()`, no con un `user_id` inexistente.
3. **Un despacho de un EXENTO** (mi_sucursal NULL) puede tocar ítems de **varias** farmacias de la empresa en una sola llamada → el auto-create debe **agrupar por `farmacia_id`** (no asumir una sola sucursal por llamada).

---

## 1 · PLAN DE OLAS DEFINITIVO

| Ola | Contenido | Front | Riesgo | Estado tras aplicar |
|---|---|---|---|---|
| **A** | `receta_items.modalidad` + trigger uniformidad + `fijar_modalidad_grupo` | **SÍ** (RecetaModal pre-marca, WebAppRecetas selector) | bajo (aditivo, default pickup) | INERTE: todo pickup, nada crea entregas |
| **B** | tabla `entregas` + RLS + 4 permisos (catálogo) | no | bajo (tabla sin RPC de write) | inerte |
| **C** | RPCs `crear/asignar/reasignar/actualizar_estado_entrega` + `listar_entregas_delivery` + **auto-create dentro de `registrar_dispensacion(_dirigida)`** | **SÍ** (gerente crea/asigna, PWA delivery estados) | **ALTO** (toca RPCs vivos 141/143) | delivery vive SOLO si modalidad=delivery (grandfather-inerte) |
| **D** | `registrar_cobro_entrega` + bucket privado `entregas-evidencia` + `actualizar_direccion_entrega` + wiring geocodificar | **SÍ** (PWA cobro + foto/firma) | medio | cobro + evidencia + coords |
| **E** | `listar_entregas_monitoreo` + `stats_entregas_sucursal` | **SÍ** (admin/gerente) | bajo (solo lectura) | monitoreo |
| **F** | `buscar_recetas_pendientes_paciente` (sin-QR) | **SÍ** (bandeja búsqueda) | bajo (**ortogonal**, no toca entregas) | despacho sin-QR |

**Orden que minimiza regresión sobre el spine:**
- **A, B** son puramente aditivas/inertes → primero, sin riesgo.
- **C es el único toque a RPCs vivos (141/143)** → grandfather-inerte obligatorio + dry-run + preview. Va después de A+B.
- **F es independiente** de toda la cadena de entregas (es pickup) → puede ir en cualquier momento, incluso primero (valor inmediato, riesgo mínimo).
- `listar_entregas_delivery` se mueve a **C** (el delivery necesita su cola para actuar sobre estados). Cadena crítica: **B→C→D→E**.

---

## 2 · OLA A — Modalidad

### DDL
```sql
ALTER TABLE public.receta_items
  ADD COLUMN modalidad text NOT NULL DEFAULT 'pickup'
  CHECK (modalidad IN ('pickup','delivery'));     -- default pickup = NO-REGRESIVO
```
**CHECK adicional (delivery exige sucursal) + uniformidad por (receta_id, farmacia_id) — trigger STATEMENT-level:**
```sql
-- delivery⇒sucursal: un ítem no ruteado (farmacia_id NULL) no puede ser delivery
ALTER TABLE public.receta_items
  ADD CONSTRAINT chk_modalidad_delivery_farmacia CHECK (modalidad <> 'delivery' OR farmacia_id IS NOT NULL);

-- uniformidad: todos los ítems de (receta, farmacia) comparten modalidad. STATEMENT-level (estado FINAL).
CREATE FUNCTION private.receta_items_modalidad_uniforme() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (SELECT DISTINCT receta_id, farmacia_id FROM newtab WHERE farmacia_id IS NOT NULL) g
    JOIN public.receta_items ri ON ri.receta_id=g.receta_id AND ri.farmacia_id=g.farmacia_id
    GROUP BY g.receta_id, g.farmacia_id HAVING count(DISTINCT ri.modalidad) > 1
  ) THEN RAISE EXCEPTION 'modalidad no uniforme en grupo (receta, farmacia)'; END IF;
  RETURN NULL;
END $$;
-- Postgres prohíbe transition tables con multi-evento Y con lista de columnas → DOS triggers, sin `UPDATE OF`:
CREATE TRIGGER trg_modalidad_uniforme_ins AFTER INSERT ON public.receta_items
  REFERENCING NEW TABLE AS newtab FOR EACH STATEMENT EXECUTE FUNCTION private.receta_items_modalidad_uniforme();
CREATE TRIGGER trg_modalidad_uniforme_upd AFTER UPDATE ON public.receta_items
  REFERENCING NEW TABLE AS newtab FOR EACH STATEMENT EXECUTE FUNCTION private.receta_items_modalidad_uniforme();
```
> **[CORRECCIÓN #4 — el trigger ROW era el defecto, detectado por el smoke de 144]** Un trigger `FOR EACH ROW` se auto-rechaza a mitad del UPDATE de grupo de `fijar_modalidad_grupo` (al cambiar la 1ª fila, las hermanas siguen con la modalidad vieja → divergencia transitoria → RAISE). La versión correcta es **`FOR EACH STATEMENT` con transition table** (evalúa el estado final). Postgres no admite transition tables con multi-evento ni con `UPDATE OF col` → **dos triggers** (INSERT y UPDATE), el de UPDATE sin lista de columnas (dispara en todo UPDATE de `receta_items`; **nunca rechaza** grupos uniformes → costo despreciable, sin cambio de semántica del despacho). Aplicado en **mig 145**.
> - **Caso #1 (re-ruteo, cambio de `farmacia_id`):** `NEW TABLE` basta — quitar un ítem del grupo ORIGEN no lo vuelve no-uniforme (subconjunto de uniforme es uniforme); el único grupo que puede romperse es el DESTINO, que está en `newtab`. No se requiere `OLD TABLE`. Fase 1 no prohíbe re-rutear un ítem ya delivery; si el re-ruteo crea destino mixto, el trigger lo rechaza.
> - **Caso #2 (`delivery` con `farmacia_id` NULL):** lo impide el `CHECK chk_modalidad_delivery_farmacia` (delivery exige sucursal).

### RPC `fijar_modalidad_grupo` (médico Y paciente; última escritura gana; congela tras despacho)
```sql
CREATE FUNCTION public.fijar_modalidad_grupo(p_receta_id bigint, p_farmacia_id integer, p_modalidad text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid := auth.uid(); v_es_medico bool; v_es_paciente bool; v_n int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF p_modalidad NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'Modalidad inválida'; END IF;
  -- gate: el médico de la receta O el paciente dueño
  SELECT EXISTS (SELECT 1 FROM public.recetas r WHERE r.id=p_receta_id AND r.medico_id=v_uid) INTO v_es_medico;
  SELECT EXISTS (SELECT 1 FROM public.recetas r WHERE r.id=p_receta_id
                 AND COALESCE(private.paciente_es_mio(r.paciente_id),false)) INTO v_es_paciente;
  IF NOT (v_es_medico OR v_es_paciente) THEN RAISE EXCEPTION 'No autorizado para esta receta'; END IF;
  -- guard GATE-ANTES-DE-EFECTO: editable solo hasta que la sucursal despache el grupo
  IF EXISTS (SELECT 1 FROM public.receta_items
             WHERE receta_id=p_receta_id AND farmacia_id=p_farmacia_id AND dispensado=true) THEN
    RAISE EXCEPTION 'Modalidad congelada: la sucursal ya despachó este grupo';
  END IF;
  UPDATE public.receta_items SET modalidad=p_modalidad
    WHERE receta_id=p_receta_id AND farmacia_id=p_farmacia_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('receta_id',p_receta_id,'farmacia_id',p_farmacia_id,'modalidad',p_modalidad,'items',v_n);
END $$;
REVOKE EXECUTE ON FUNCTION public.fijar_modalidad_grupo(bigint,integer,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fijar_modalidad_grupo(bigint,integer,text) TO authenticated;
```
- **Un solo RPC** compartido (gate por OR médico/paciente). "Última escritura gana" (sin lock). El UPDATE del grupo entero = uniformidad por construcción; el trigger es backstop.
- **Front:** RecetaModal (médico pre-marca por grupo al rutear); WebAppRecetas (paciente cambia). Ambos llaman este RPC.

### Front que toca la Ola A (marcar, sin implementar)
- **Pre-marca del MÉDICO — [RecetaModal.tsx](src/components/consulta/RecetaModal.tsx):** la agrupación por cadena/sucursal ya existe ([:187-198](src/components/consulta/RecetaModal.tsx#L187)) y el ruteo per-ítem en [:370](src/components/consulta/RecetaModal.tsx#L370) (`abrirModalFarmacia`). El control de modalidad va **por grupo de sucursal** (un toggle pickup/delivery por `(receta, farmacia)`), habilitado **después** de rutear (cuando `item.farmacia_id` está seteado) → llama `fijar_modalidad_grupo(receta_id, farmacia_id, modalidad)`. Al emitir aún por insert directo (pre-O1), la pre-marca se hace tras crear la receta (cuando ya hay `receta_id`+ítems con `farmacia_id`).
- **Control del PACIENTE — [WebAppRecetas.tsx:97](src/webapp/pages/WebAppRecetas.tsx#L97)** (`r.items.map`) + [useWebAppRecetas.ts:51-55](src/webapp/hooks/useWebAppRecetas.ts#L51): agrupar los ítems por `farmacia_id` y ofrecer pickup/delivery **por sucursal**; cada cambio llama el **mismo** `fijar_modalidad_grupo`. (Requiere exponer `farmacia_id`/`modalidad` en el select del hook — hoy no los trae.)
- Ambos paths → **un solo RPC**; la UI puede ocultar el control si está congelado, pero la autoridad es el guard del RPC.

### Verificación Ola A
- **No-regresión del default pickup (crítico):** el insert directo actual de `useRecetas` ([useRecetas.ts:63/87](src/hooks/useRecetas.ts#L63)) **NO se rompe** — los ítems entran sin `modalidad` (→ default `pickup`) y con `farmacia_id=NULL` → el trigger `EXISTS (... x.farmacia_id=NEW.farmacia_id ...)` con NULL no matchea → 0 rechazos. Probe Pmod_batch: insert batch de N ítems (varias farmacias, todas pickup) → 0 rechazos.
- **Trigger batch vs ítem único:** (batch) mixto de farmacias, todas pickup → OK; (ítem único) `UPDATE modalidad` de un grupo que ya tiene otra modalidad → RAISE (correcto); cambio vía `fijar_modalidad_grupo` (todo el grupo a la vez) → nunca deja el grupo a medias → sin falso-rechazo ni deadlock.
- **Freeze server-side:** fijar delivery → uniforme; tras `dispensado=true` en cualquier ítem del grupo → `fijar_modalidad_grupo` da **RAISE 'congelada'** (ambos paths). "Última escritura gana" solo mientras no congelado.
- **Gate del paciente:** paciente dueño (`paciente_es_mio(recetas.paciente_id bigint)`) → OK; **otro paciente** → RAISE 'No autorizado'; tercero (ni médico ni paciente) → RAISE.
- **Harness:** verde sin filas nuevas rojas; ninguna RPC de despacho cambia (nada lee `modalidad` hasta Ola C).

### Inercia de la Ola A (explícito)
- **A NO crea ninguna entrega.** La tabla `entregas` ni siquiera existe en A (es Ola B). `modalidad` por sí sola **no dispara nada**: el auto-create vive en Ola C, dentro de `registrar_dispensacion(_dirigida)`, y solo actúa si `modalidad='delivery'`.
- **Inerte vs 141/143:** A no toca `registrar_dispensacion(_dirigida)` ni `verificar_receta_despacho` ni ninguna RLS de confinamiento → cero impacto sobre el spine de sucursales. El despacho se comporta idéntico.
- **Inerte vs ruteo 3.3:** A agrega una columna ortogonal; el ruteo per-ítem (`farmacia_id`) no cambia. La uniformidad solo aplica una vez que un grupo tiene `farmacia_id` + `modalidad` seteados; en el alta (farmacia_id NULL, pickup) no interviene.

### Dependencia anotada (O1 regulatorio)
Cuando entre **O1 (`emitir_receta`, único escritor)**, deberá **setear `modalidad`** en su insert de `receta_items` (default `'pickup'` si `p_items` no la trae). Hasta entonces, el **`DEFAULT 'pickup'` lo cubre** y el insert directo de `useRecetas` sigue funcionando. Registrado también en [DISENO-REGULATORIO.md](DISENO-REGULATORIO.md) B8.

---

## 3 · OLA B — Tabla `entregas` + permisos + RLS

### DDL
```sql
CREATE TABLE public.entregas (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receta_base_id  bigint  NOT NULL REFERENCES public.recetas(id),          -- recetas(id) es referenciable (ver §0)
  farmacia_id     integer NOT NULL REFERENCES public.farmacias(id),         -- la SUCURSAL
  empresa_id      uuid    NOT NULL REFERENCES public.empresas_proveedoras(id),  -- denormalizado p/ RLS (= farmacias.empresa_id)
  paciente_id     bigint  NOT NULL REFERENCES public.pacientes(id),
  delivery_id     uuid    REFERENCES public.cuentas_proveedor(id),          -- repartidor; NULL hasta asignar
  estado          text    NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente','asignada','en_camino','entregada','fallida')),
  motivo_fallo    text    CHECK (motivo_fallo IN ('rechazada','ausente','direccion_mala')),
  direccion_entrega text,                                                   -- snapshot de pacientes.direccion, editable
  telefono_contacto text,                                                   -- snapshot de pacientes.telefono
  lat             double precision, lng double precision,                   -- nullable; entrega válida sin coords
  monto           numeric(12,2),                                            -- snapshot SUM(dispensaciones.total_dispensado)
  metodo_cobro    text    CHECK (metodo_cobro IN ('efectivo','tarjeta','transferencia','sin_cobro')),
  cobrado         boolean NOT NULL DEFAULT false,
  cobrado_at      timestamptz, cobrado_por uuid REFERENCES public.cuentas_proveedor(id),
  evidencia_path  text,                                                     -- PATH en bucket privado (no URL)
  asignado_por    uuid, asignado_at timestamptz, entregado_at timestamptz, notas text,
  intentos        integer NOT NULL DEFAULT 0,                              -- reaperturas vía reasignar_entrega (fallida→asignada)
  reabierta_at    timestamptz, reabierta_por uuid REFERENCES public.cuentas_proveedor(id),  -- audita el último reintento (no es borrón)
  created_by      uuid,                                                     -- NULL = auto-al-despachar
  created_at      timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_entrega_receta_sucursal UNIQUE (receta_base_id, farmacia_id),       -- UNA por sucursal
  CONSTRAINT chk_motivo_si_fallida CHECK ((estado='fallida') = (motivo_fallo IS NOT NULL)),
  CONSTRAINT chk_cobro_coherente   CHECK (cobrado=false OR (cobrado_at IS NOT NULL AND cobrado_por IS NOT NULL AND metodo_cobro IS NOT NULL)),
  CONSTRAINT chk_monto_no_negativo CHECK (monto IS NULL OR monto >= 0)
);
CREATE INDEX idx_entregas_delivery_estado ON public.entregas (delivery_id, estado);   -- cola del repartidor
CREATE INDEX idx_entregas_farmacia_estado ON public.entregas (farmacia_id, estado);   -- monitoreo por sucursal
CREATE INDEX idx_entregas_empresa_estado  ON public.entregas (empresa_id, estado);    -- monitoreo admin / RLS

ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
-- SELECT: espejo EXACTO 141/143 (empresa + sucursal_visible) + slice del rol delivery (solo SUS entregas).
CREATE POLICY entregas_select ON public.entregas FOR SELECT TO authenticated
  USING (
    ( COALESCE(empresa_id = public.mi_empresa_proveedor(), false)
      AND COALESCE(private.sucursal_visible(farmacia_id), false)
      AND ( public.mi_rol_proveedor() <> 'delivery' OR delivery_id = auth.uid() ) )   -- delivery: solo las suyas
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  );
-- Escritura DENEGADA a authenticated/anon: SIN policy de write + REVOKE de TODO lo no-RLS-gated
-- (lección farmacia_medicamentos: TRUNCATE/TRIGGER/REFERENCES no respetan RLS → revocarlos explícito).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.entregas FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.entregas FROM anon;
GRANT  SELECT ON public.entregas TO authenticated;     -- lectura gateada por RLS; escritura solo owner/DEFINER (Ola C)
```
**Cómo conviven los tres niveles bajo la RLS (espejo 141/143):**
- **EXENTOS** = `{admin, gerente_farmacia, finanzas, pagador}` (def. de `sucursal_visible`) → `sucursal_visible=true` siempre → ven **TODA la empresa**; `mi_rol_proveedor()<>'delivery'` → sin slice → ven todas.
- **CONFINABLES** `{supervisor, inventario, cajero, dependiente}` con `sucursal_id` → ven solo su sucursal; sin slice de delivery.
- **delivery** (confinable) → su sucursal **Y** `delivery_id=auth.uid()` → **solo SUS entregas**. La RPC `listar_entregas_delivery` (C) replica el mismo slice (defensa en profundidad).
- **super_admin** → todo.
> **[Q1 CERRADO — corrección de modelo, no parche] `gerente_farmacia` EXENTO = nivel EMPRESA, es correcto.** No hay discrepancia: `gerente_farmacia` es **exento = ve toda la cadena, igual que `admin`** — **no** es el "gerente de sucursal" del mockup. El **"gerente de sucursal" del mockup = un rol CONFINABLE** (no-exento, asignado a una sucursal vía 114), que el espejo `sucursal_visible` ya acota a su sucursal **sin predicado extra**.
> **Invariante del SPINE que esto respeta (citado):** *el `sucursal_id` de un rol EXENTO es INFORMATIVO, NO un gate; está PROHIBIDO leerlo y tratarlo como confinamiento.* Por eso **NO** se agrega ningún predicado que confine a `gerente_farmacia` — ni en B ni en E. El "⚠️" previo se resuelve por **encuadre** (no estaba confinando a quien creía), no por código.
> **Para Ola E (anotado):** el monitoreo "su sucursal" aplica al **rol confinable**, no a `gerente_farmacia`. Atar `gerente_farmacia` a una sucursal sería un **cambio deliberado al modelo de exentos del SPINE** (afectaría 140/141/143) — **fuera del alcance de delivery y NO recomendado.**
> **PII:** la RLS habilita el monitoreo, pero `direccion/telefono` SOLO se exponen vía las RPCs de entregas (C/E); el flujo pickup/bandeja sigue mostrando solo nombre.

### Permisos (4 filas nuevas en `permisos_empresa_rol`, `tipo_empresa='farmacia'`)
Registro: filas `(tipo_empresa='farmacia', rol, accion)` en el catálogo `permisos_empresa_rol`, resueltas por el chokepoint `private.tiene_permiso` (catálogo + override 117). DDL = `INSERT INTO public.permisos_empresa_rol (tipo_empresa,rol,accion) VALUES ... ON CONFLICT DO NOTHING`. **+ techo (Q2):** `INSERT INTO public.acciones_techo (accion) VALUES ('entregas_cobrar') ON CONFLICT DO NOTHING`.

| accion | roles default | racional |
|---|---|---|
| `entregas_ver` | delivery, supervisor, gerente_farmacia, admin, finanzas, pagador | lectura; RLS confina (delivery→sus filas; confinable→su sucursal; exento→empresa) |
| `entregas_gestionar` | supervisor, gerente_farmacia, admin | crear/asignar/reasignar (incl. reapertura) |
| `entregas_actualizar_estado` | delivery, supervisor, gerente_farmacia, admin | el delivery mueve su entrega; gestión puede corregir |
| `entregas_cobrar` | delivery, cajero, gerente_farmacia, admin, finanzas, pagador | cobro contra-entrega + conciliación |

- **[Q2 CERRADO] Techo 117:**
  - **`entregas_cobrar` = TECHO** (agregar a `public.acciones_techo`, mismo patrón que `registro_regulatorio`). Es la **única capacidad financiera** de las cuatro (snapshotea `monto`/`metodo_cobro`/`cobrado_*`). El techo **NO impide** que delivery/cajero la tengan; **controla que SOLO el admin de empresa pueda repartirla** (el override 117 no puede concederla/quitarla a otros roles fuera del default — `tiene_permiso` ignora el override para techo).
  - **`entregas_ver`, `entregas_actualizar_estado`, `entregas_gestionar` = operativos**, editables per-empresa vía override 117 (gestión, no plata).
- **Confinabilidad (114) confirmada:** `delivery` es **CONFINABLE** (no está en los EXENTOS de `sucursal_visible`; nivel 20) → con `sucursal_id` ve solo su sucursal, y la RLS le agrega el slice `delivery_id=auth.uid()`. En los defaults, **`delivery` NO recibe `entregas_gestionar`** (no crea/asigna/reabre — la reapertura `fallida→asignada` es solo gestión, §4). **SÍ recibe `entregas_cobrar`** (cobra contra-entrega), `entregas_actualizar_estado` (mueve su propia entrega) y `entregas_ver` (su cola).
- **Flujo COD (contra-entrega) confirmado:** el **admin de empresa** asigna `entregas_cobrar` (techo → solo él lo reparte) a `delivery` y/o `cajero` de mostrador → al entregar, quien lo tiene marca `cobrado` vía **`registrar_cobro_entrega` (Ola D)**, que snapshotea **`monto` (SUM por tanda, D-1) + `metodo_cobro` + `cobrado/at/por` atómicamente**. El `delivery` sigue **SIN `entregas_gestionar`** (no crea/asigna/reabre).

### empresa_id — por qué se desnormaliza (vs derivar de farmacia)
`empresa_id` se persiste en `entregas` (no se deriva de `farmacias` en la policy) por: (1) **RLS performante** — la policy compara una columna directa (`empresa_id = mi_empresa_proveedor()`) en vez de un subquery correlacionado `(SELECT empresa_id FROM farmacias WHERE id=farmacia_id)` por fila; (2) **indexable** (`idx_entregas_empresa_estado`); (3) **point-in-time** — la entrega registra la empresa al momento de crearse. Lo **puebla el RPC de Ola C** = `farmacias.empresa_id` de la `farmacia_id` (en el auto-create, ya es `v_emp` del RPC de despacho). Riesgo (farmacia cambia de empresa) = remoto; el único escritor es el RPC → consistencia confiada al RPC (no se agrega trigger en Fase 1).

### CHECKs de coherencia (lista)
1. `estado IN ('pendiente','asignada','en_camino','entregada','fallida')` (inline).
2. `motivo_fallo IN ('rechazada','ausente','direccion_mala')` (inline) **+** `chk_motivo_si_fallida`: `(estado='fallida') = (motivo_fallo IS NOT NULL)` (motivo obligatorio ⇔ fallida; prohibido fuera de fallida).
3. `metodo_cobro IN ('efectivo','tarjeta','transferencia','sin_cobro')` (inline).
4. `chk_cobro_coherente`: `cobrado=false OR (cobrado_at IS NOT NULL AND cobrado_por IS NOT NULL AND metodo_cobro IS NOT NULL)`.
5. `chk_monto_no_negativo`: `monto IS NULL OR monto >= 0`.
6. `UNIQUE(receta_base_id, farmacia_id)` — una entrega por grupo.

### Verificación Ola B (para cuando se apruebe el apply)
- **Estructural:** `\d entregas` (PK, FKs `recetas(id)`/`farmacias(id)`/`pacientes(id)`/`cuentas_proveedor(id)`, UNIQUE, 6 CHECKs, defaults), índices (UNIQUE + delivery/farmacia/empresa+estado), grants (`authenticated`=SELECT; anon=∅; INSERT/UPDATE/DELETE/TRUNCATE/TRIGGER/REFERENCES revocados), 4 permisos en catálogo, **`entregas_cobrar` en `acciones_techo`** (techo).
- **Probe techo (Q2):** `entregas_cobrar` no-delegable → un override 117 que intente concederla a un rol fuera del default es **ignorado por `tiene_permiso`** (techo autoritativo en la resolución); los otros 3 sí son afectables por override.
- **Probes RLS (tabla sembrada a mano en BEGIN/ROLLBACK):** sembrar entregas en empresa A (sucursales X,Y) + empresa B. (a) **exento** (admin A) → ve todas las de A, ninguna de B; (b) **confinable@X** (supervisor A, sucursal X) → solo entregas de X; (c) **delivery@X** → solo sus filas (`delivery_id=él`), no las de otro delivery de X; (d) **cross-empresa** (actor A) → 0 filas de B; (e) **anon** → 0; (f) **INSERT/UPDATE directo** por `authenticated` → **DENEGADO** (sin grant); (g) **gerente_farmacia A** → ve toda A (exento — documentar la discrepancia, no es bug de B).
- **No-regresión:** tabla **vacía**, 0 callers, sin RPC de write → emisión / despacho 141/143 / ruteo 3.3 / Ola A **idénticos**. Harness 141/143 verde (459 filas, 0 ROJO).

### Inercia / no-regresión de B (explícito)
Crear tabla + 4 permisos + RLS **no afecta ningún path vivo**: no hay caller de `entregas` (los RPCs son Ola C); los 4 permisos nuevos no los exige ningún flujo existente; la RLS es de una tabla nueva vacía. Emisión, despacho (141/143), ruteo 3.3 y Ola A (`modalidad`/`fijar_modalidad_grupo`) no tocan `entregas`. **B nace 100% inerte.**

### Dependencias hacia C (anotadas, NO implementadas en B)
La tabla deja la estructura lista; C la llena:
- **auto-create** (dentro de `registrar_dispensacion*`): setea `receta_base_id`, `farmacia_id`, `empresa_id=v_emp`, `paciente_id` de **`recetas` (bigint)**, `direccion_entrega`/`telefono_contacto` = snapshot de `pacientes`, `monto` = `SUM(dispensaciones.total_dispensado)` (recalculado por tanda, D-1), `created_by=NULL`. Requiere `modalidad='delivery'` (Ola A) + grupo despachado.
- **cobro** (`registrar_cobro_entrega`): setea `metodo_cobro`, `cobrado=true`, `cobrado_at`, `cobrado_por`; respeta `chk_cobro_coherente`.
- **dirección/geocodificar** (`actualizar_direccion_entrega`): el front llama al edge `geocodificar` → setea `direccion_entrega`, `lat`, `lng` (nullable; entrega válida sin coords).
- **reapertura** (`reasignar_entrega`): `intentos+1`, `reabierta_at/por`, `motivo_fallo→NULL` (arista fallida→asignada, solo `entregas_gestionar`, `cobrado=false`).
- **evidencia** (Ola D): `evidencia_path` = path en bucket privado (no URL).

---

## 4 · OLA C — RPCs de ciclo + auto-create (TOCA 141/143)

### 4.0 · Censo EXACTO de puntos de inserción (equivalente al "único escritor")
Verificado en vivo (`pg_proc` que insertan en `dispensaciones` + grants):
- **SOLO DOS escritores de `dispensaciones`, ambos DEFINER:**
  1. **`registrar_dispensacion(p_token text, p_item_ids bigint[], p_farmaceutico text)`** — **walk-in Y QR** (misma RPC; el token viene del QR del paciente). Loop verificado: `FOR r IN SELECT ri... WHERE ri.receta_id=v_receta_id AND f.empresa_id=v_emp AND sucursal_visible(ri.farmacia_id) AND ri.id=ANY(p_item_ids) AND dispensado=false LOOP UPDATE dispensado + INSERT dispensaciones END LOOP`.
  2. **`registrar_dispensacion_dirigida(p_receta_id bigint, p_item_ids bigint[], p_farmaceutico text)`** — **bandeja** (sin token, por `receta_id`). Mismo loop/gate.
- **`authenticated` NO tiene INSERT sobre `dispensaciones`** (solo `service_role`/`postgres`/owner) → las 2 RPCs DEFINER son el **único camino** de escritura. **No hay un 3er escritor** que quede sin el hook → consistencia garantizada. (Las "3 vías" del spine colapsan en **2 RPCs**: `registrar_dispensacion` sirve walk-in **y** QR.)
- Otros que mencionan `dispensaciones`: `stats_finanzas_sucursal`, `stats_recetas_sucursal` (solo LEEN, reportes; no escriben).
- **Conclusión:** el bloque auto-create va en **2 lugares idénticos** (tras el loop de cada RPC). El monto se deriva de `dispensaciones` (recién insertadas en el loop), así que el bloque debe ir **después** del loop.

### Máquina de estados (validada en cada RPC, gate-antes-de-efecto)
`pendiente →(gestionar) asignada →(actualizar_estado) en_camino →(actualizar_estado) entregada | fallida(motivo)`; `asignada→fallida` ok; `asignada/en_camino →(gestionar) asignada` (reasignar); **`fallida →(gestionar) asignada` (reabrir, con salvaguardas)**; `entregada` terminal. Idempotente: estado==actual → no-op.
- **[D-9] `fallida(motivo: rechazada|ausente|direccion_mala)` = terminal-REABRIBLE-vía-gestión, SIN reversión** de dispensación/stock (no reabre `dispensado`, no restock; inmutabilidad regulatoria A6). El retorno físico del med es **nota operativa**, fuera del sistema.
- **Reapertura `fallida → asignada` (vía `reasignar_entrega`), salvaguardas:**
  - gateada **SOLO por `entregas_gestionar`** (NO el rol delivery — un delivery no reabre su propia falla);
  - **SOLO si `cobrado=false`** → **RAISE si la entrega ya fue cobrada**;
  - **`intentos = intentos + 1`** + set `reabierta_at=now()`, `reabierta_por=auth.uid()`, nuevo `delivery_id`, `motivo_fallo=NULL`, `estado='asignada'`. El contador **audita** el reintento (el monitoreo E lo muestra; **no es un borrón**);
  - **NO toca la dispensación** (sigue válida — coherente con D-9 / A6);
  - Fase 1: `rechazada`, `ausente` y `direccion_mala` usan la **misma** transición con el contador visible (no se trata `rechazada` distinto por ahora).

### Firmas + gate (cuerpos resumidos; todos DEFINER sp'')
| RPC | Firma | Gate | Confina |
|---|---|---|---|
| `crear_entrega` | `(p_receta_base_id bigint, p_farmacia_id int)→jsonb` | `entregas_gestionar` | empresa + `sucursal_visible(p_farmacia_id)`; UPSERT snapshot |
| `asignar_entrega` | `(p_entrega_id bigint, p_delivery_id uuid)→jsonb` | `entregas_gestionar` | entrega visible; valida `p_delivery_id` = rol delivery de misma empresa+sucursal; `pendiente→asignada` |
| `reasignar_entrega` | `(p_entrega_id bigint, p_delivery_id uuid)→jsonb` | `entregas_gestionar` | desde asignada/en_camino (reasignar) **y fallida (reabrir)**; **RAISE si `cobrado=true`**; en reapertura `fallida→asignada`: `intentos+1`, `reabierta_at/por`, `motivo_fallo=NULL`. NO toca dispensación |
| `actualizar_estado_entrega` | `(p_entrega_id bigint, p_nuevo_estado text, p_motivo_fallo text DEFAULT NULL)→jsonb` | `entregas_actualizar_estado` | empresa+sucursal; **si rol delivery: AND `delivery_id=auth.uid()`**; valida transición; idempotente |
| `listar_entregas_delivery` | `()→jsonb` | `entregas_ver` | empresa + sucursal_visible + **`delivery_id=auth.uid()`** (cola propia) |

Ejemplo de cuerpo (`actualizar_estado_entrega`, patrón gate-antes-de-efecto):
```sql
CREATE FUNCTION public.actualizar_estado_entrega(p_entrega_id bigint, p_nuevo_estado text, p_motivo_fallo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_es_delivery bool;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'),false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(),false)
    AND COALESCE(private.sucursal_visible(farmacia_id),false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  -- delivery solo su propia entrega
  v_es_delivery := (v_e.delivery_id = auth.uid());
  IF private.mi_sucursal() IS NOT NULL AND NOT v_es_delivery
     AND NOT COALESCE(private.tiene_permiso('entregas_gestionar'),false) THEN
     RAISE EXCEPTION 'No autorizado: no es tu entrega'; END IF;
  IF v_e.estado = p_nuevo_estado THEN RETURN to_jsonb(v_e); END IF;             -- idempotente
  -- transición legal:
  IF NOT ( (v_e.estado='asignada'  AND p_nuevo_estado IN ('en_camino','fallida'))
        OR (v_e.estado='en_camino' AND p_nuevo_estado IN ('entregada','fallida')) ) THEN
     RAISE EXCEPTION 'Transición ilegal % → %', v_e.estado, p_nuevo_estado; END IF;
  IF p_nuevo_estado='fallida' AND p_motivo_fallo IS NULL THEN RAISE EXCEPTION 'Motivo requerido'; END IF;
  UPDATE public.entregas SET estado=p_nuevo_estado, motivo_fallo=p_motivo_fallo,
    entregado_at = CASE WHEN p_nuevo_estado='entregada' THEN now() ELSE entregado_at END, updated_at=now()
    WHERE id=p_entrega_id;
  -- HOOK push paciente (Fase 4): en_camino / entregada → punto de notificación (stub, sin efecto aquí)
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
```
Cuerpo de `asignar_entrega` (valida que el delivery sea de la MISMA sucursal de la entrega — scope #8):
```sql
CREATE FUNCTION public.asignar_entrega(p_entrega_id bigint, p_delivery_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_del public.cuentas_proveedor;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_gestionar'),false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(),false)
    AND COALESCE(private.sucursal_visible(farmacia_id),false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.estado <> 'pendiente' THEN RAISE EXCEPTION 'Solo se asigna desde pendiente (estado=%)', v_e.estado; END IF;
  SELECT * INTO v_del FROM public.cuentas_proveedor
    WHERE id=p_delivery_id AND empresa_id=v_e.empresa_id AND rol_en_empresa='delivery' AND activo=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery inválido (no es delivery activo de la empresa)'; END IF;
  -- #8: el delivery debe ser de la MISMA sucursal de la entrega (o exento sin sucursal → no aplica a delivery)
  IF v_del.sucursal_id IS DISTINCT FROM v_e.farmacia_id THEN
    RAISE EXCEPTION 'El delivery no pertenece a la sucursal de la entrega'; END IF;
  UPDATE public.entregas SET estado='asignada', delivery_id=p_delivery_id,
    asignado_por=auth.uid(), asignado_at=now(), updated_at=now() WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
```

### Auto-create dentro de `registrar_dispensacion(_dirigida)` — bloque ADITIVO grandfather-inerte
Tras el `LOOP` que marca dispensado + inserta `dispensaciones` (validado en vivo: el loop ya filtra `sucursal_visible`), agregar **antes del `RETURN`**:
```sql
-- AUTO-CREATE (best-effort, #4-B): NUNCA aborta el despacho. Corre TRAS el loop, envuelto en BEGIN…EXCEPTION.
-- Kill-switch con DEFAULT FAIL-SAFE: ausencia de fila/tabla → OFF (ante duda, no auto-crear; el despacho no se afecta).
IF COALESCE((SELECT habilitado FROM private.delivery_flags WHERE clave='autocreate_entregas'), false) THEN
  BEGIN
    -- una entrega por (receta, farmacia) delivery que este actor despachó. Agrupa por farmacia_id (multi-sucursal). Idempotente.
    INSERT INTO public.entregas (receta_base_id, farmacia_id, empresa_id, paciente_id,
                                 direccion_entrega, telefono_contacto, monto, created_by)
    SELECT v_receta_id, ri.farmacia_id, v_emp, r.paciente_id, pac.direccion, pac.telefono,  -- paciente_id de RECETAS (bigint)
           (SELECT SUM(d.total_dispensado) FROM public.dispensaciones d
              WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id),
           NULL                                                          -- created_by NULL = auto
    FROM public.receta_items ri
    JOIN public.recetas   r   ON r.id  = v_receta_id
    JOIN public.pacientes pac ON pac.id = r.paciente_id
    WHERE ri.receta_id = v_receta_id
      AND ri.farmacia_id IS NOT NULL
      AND ri.modalidad = 'delivery'                                     -- grandfather: default pickup → 0 filas
      AND COALESCE(private.sucursal_visible(ri.farmacia_id), false)     -- hereda el confinamiento del loop
      AND EXISTS (SELECT 1 FROM public.dispensaciones d
                   WHERE d.receta_avanzada_id = v_ra.id AND d.farmacia_id = ri.farmacia_id)  -- ya despachada
    GROUP BY ri.farmacia_id, r.paciente_id, pac.direccion, pac.telefono
    ON CONFLICT (receta_base_id, farmacia_id) DO UPDATE                 -- [D-1=B] recálculo del monto por tanda
      SET monto = excluded.monto, updated_at = now()
      WHERE entregas.estado = 'pendiente';                             -- ya asignada/en_camino/cobrada → NO recalcula
  EXCEPTION WHEN OTHERS THEN
    -- best-effort: el despacho YA está comprometido y NO se revierte. NO se traga en silencio → rastro para E.
    RAISE WARNING 'auto-create entrega falló (receta %, empresa %): %', v_receta_id, v_emp, SQLERRM;
    BEGIN
      INSERT INTO private.delivery_autocreate_fallos (receta_base_id, empresa_id, error, ocurrido_at)
      VALUES (v_receta_id, v_emp, SQLERRM, now());
    EXCEPTION WHEN OTHERS THEN NULL;   -- el log también es best-effort; jamás afecta el despacho
    END;
  END;
END IF;
```
**[D-1 = opción B, CERRADO] Recálculo del monto en despacho parcial:** el `excluded.monto` es el `SUM(dispensaciones.total_dispensado)` recomputado de ese `(receta, farmacia)` en **esta** tanda (incluye todo lo despachado hasta ahora). El `ON CONFLICT DO UPDATE ... WHERE estado='pendiente'` lo aplica:
- **1ª tanda:** INSERT con monto = SUM parcial; estado `pendiente`.
- **2ª+ tanda, entrega aún `pendiente`:** UPDATE → monto = SUM acumulado (refleja TODO lo despachado). Idempotente.
- **Caso borde — entrega ya NO-pendiente (asignada/en_camino/cobrada) y llega otra tanda:** el `WHERE estado='pendiente'` **no matchea → el monto NO se mueve** (no se pisa un cobro/asignación en curso). **Discrepancia a registrar** (nota): si tras asignar llega más despacho, el monto cobrado puede quedar por debajo de lo despachado → el monitoreo (E) debe poder **detectar `monto < SUM(dispensaciones)` en entregas no-pendientes** y señalarlo (no se auto-corrige en Fase 1; es señal operativa para el gerente).
- **Grandfather-inerte:** con default `pickup` y 0 escrituras de modalidad → `ri.modalidad='delivery'` nunca matchea → 0 inserts → `registrar_dispensacion*` se comporta **idéntico a hoy**.
- **Manual** (`crear_entrega`): mismo INSERT con `ON CONFLICT DO UPDATE` de snapshots; `created_by=auth.uid()`.

### Fuentes de los campos + coords nullables
- **`empresa_id = v_emp`** = `public.mi_empresa_proveedor()`, ya calculado al inicio del RPC de despacho. El loop **solo** despacha ítems con `f.empresa_id = v_emp` → la entrega creada tiene `empresa_id = v_emp` = empresa de la farmacia (consistente con el FK y la RLS). No se re-deriva de `farmacias` (ya está garantizado por el loop).
- **`paciente_id`** = `recetas.paciente_id` (**bigint**, vía `JOIN recetas r ON r.id=v_receta_id`) — NO `v_ra.paciente_id` (text de `recetas_avanzadas`). Evita cast.
- **`monto`** = `SUM(dispensaciones.total_dispensado)` del grupo en esta tanda (las filas recién insertadas por el loop).
- **`direccion_entrega`/`telefono_contacto`** = snapshot de `pacientes` al crear. **`lat`/`lng` = NULL** en el auto-create → **la entrega es VÁLIDA sin coords** (no hay CHECK que las exija; el mapa la muestra sin-pin). La geocodificación es **async** (Ola D / edge `geocodificar`, vía `actualizar_direccion_entrega`). Confirmado: ninguna restricción bloquea la entrega por coords faltantes.
- **`estado='pendiente'` (default), `intentos=0` (default), `created_by=NULL`** (auto).

### Kill-switch (backout sin redeploy) — gate del bloque
El bloque auto-create se envuelve en un guard leído de una mini-config, para **apagarlo en vivo** sin redeploy. **Default FAIL-SAFE = `false`** (ausencia = APAGADO; semántica cerrada detallada abajo en "Kill-switch — semántica cerrada"):
```sql
IF COALESCE((SELECT habilitado FROM private.delivery_flags WHERE clave='autocreate_entregas'), false) THEN
   BEGIN ... INSERT INTO public.entregas (...) ... EXCEPTION WHEN OTHERS THEN ...rastro... END;   -- best-effort #4-B
END IF;
```
- **Tablas nuevas (Ola C):**
  - `private.delivery_flags(clave text PRIMARY KEY, habilitado boolean NOT NULL DEFAULT true)`, **seed `('autocreate_entregas', true)`** (habilita la feature; absence ⇒ off por el COALESCE).
  - `private.delivery_autocreate_fallos(id bigint IDENTITY PK, receta_base_id bigint, empresa_id uuid, error text, ocurrido_at timestamptz DEFAULT now())` — rastro de fallos del best-effort (lo lee E).
- Un `UPDATE private.delivery_flags SET habilitado=false WHERE clave='autocreate_entregas'` (admin plataforma) **desactiva el auto-create al instante**; el despacho vuelve a pre-C. El read es 1 fila por PK (despreciable).
- **Backout en 2 niveles:** (1) flag off (instantáneo, sin redeploy); (2) `CREATE OR REPLACE` de los 2 RPCs a la versión 143 (sin el bloque). El flag es la 1ª línea de defensa.

### [#4 — DECISIÓN OSCAR] Transaccionalidad del auto-create
El bloque corre **dentro de la transacción del RPC de despacho**. Qué pasa si el INSERT de entrega falla:
| Opción | Comportamiento | Trade-off |
|---|---|---|
| **(A) Atómico (misma tx, sin guard de excepción)** | un fallo del auto-create **aborta el despacho** (rollback de dispensaciones + dispensado) | consistencia total (nunca despacho-sin-entrega); **PERO acopla el path caliente**: un bug/constraint en entregas **pierde el despacho** — inaceptable para el requisito "el despacho no debe perderse" |
| **(B) Best-effort (sub-bloque `BEGIN…EXCEPTION` dentro del RPC)** | si el auto-create falla, se hace rollback **solo del savepoint** (no de la entrega) y el **despacho COMMITEA igual**; se registra la falla | **el despacho nunca se pierde**; queda una entrega **faltante** (NO huérfana — huérfano sería entrega sin despacho; acá es despacho sin entrega, **reconciliable**). El monitoreo E detecta "grupos delivery despachados sin entrega" → el gerente la crea con `crear_entrega`. |
| **(C) Desacoplado (trigger AFTER INSERT en dispensaciones, o job)** | el auto-create no vive en el RPC | desacopla, pero agrega un trigger en el path caliente o un job de reconciliación; más superficie |
**[#4 = (B) best-effort, CERRADO Oscar] Patrón exacto:**
- El bloque va en un **sub-bloque `BEGIN … EXCEPTION WHEN OTHERS THEN … END` DENTRO de cada RPC, TRAS el loop** de dispensación. Si el INSERT/UPDATE de entrega falla, el savepoint del sub-bloque se revierte (deshace la entrega parcial) pero **el despacho —ya comprometido— NO se revierte**; la transacción del RPC **commitea igual**.
- **NO se traga en silencio:** el handler hace **`RAISE WARNING`** (a los logs del servidor) **+** inserta una fila en **`private.delivery_autocreate_fallos (receta_base_id, empresa_id, error, ocurrido_at)`** (best-effort anidado; si ese insert también falla, `NULL` → jamás afecta el despacho). Ese es el **rastro que E lee** para la reconciliación.
- **Huérfana imposible / residual = FALTANTE:** el bloque corre **después** del loop y exige `EXISTS dispensaciones` del grupo → **nunca** hay entrega sin despacho (huérfana). El único riesgo residual es **entrega FALTANTE** (despacho sin entrega) — exactamente el caso que **E reconcilia** (discrepancia #2).
- **Pickup byte-idéntico:** la rama `delivery` + su `EXCEPTION` es el **único** código nuevo en caliente. Con `pickup` (default) el `IF flag AND modalidad='delivery'` no entra (y con flag off ni se evalúa) → el despacho es **idéntico** al de 143. (A) habría arriesgado el path crítico; (C) era sobre-ingeniería.

**Doble savepoint anidado (confirmaciones explícitas):**
1. **El handler externo NO re-lanza** (no hay `RAISE` al final del `EXCEPTION WHEN OTHERS` externo) → la excepción del auto-create **nunca sube** a la transacción del despacho. El despacho commitea.
2. **El handler interno traga su propio fallo** (`EXCEPTION WHEN OTHERS THEN NULL`) → la cadena *auto-create-falla → log-falla* termina en `NULL`; ni el INSERT del log puede romper el despacho.
3. **Ambos `BEGIN…EXCEPTION` crean savepoints implícitos de PL/pgSQL:** un error que abortó la sub-transacción del auto-create se **revierte al savepoint** (la sub-tx queda limpia) → la **sesión queda usable** para el INSERT del log y para el COMMIT del despacho (PL/pgSQL no deja la transacción en estado abortado tras capturar en un bloque).
4. **`RAISE WARNING` antes del INSERT del log es seguro:** el `WARNING` ya se **emitió** (va a los logs) antes de intentar el INSERT; si el INSERT del log falla, el WARNING ya quedó registrado y el handler interno lo traga — sin efecto sobre el despacho.

### Kill-switch `private.delivery_flags` — semántica cerrada
- **Default FAIL-SAFE:** `COALESCE((SELECT habilitado FROM private.delivery_flags WHERE clave='autocreate_entregas'), false)` → **ausencia de fila/tabla = APAGADO**. Ante cualquier duda (fila borrada, tabla ausente, SELECT vacío) **no se auto-crea**, y el despacho **nunca** se ve afectado (el flag-read y el bloque están fuera del camino del despacho). La migración C **siembra la fila en `true`** para habilitar la feature; quitarla/ponerla `false` la apaga.
- **Apagado a mitad de grupo (entre tanda 1 y tanda 2):** comportamiento **esperado, NO bug** — tanda 1 (flag on) creó la entrega `pendiente` con su `monto` parcial; tanda 2 (flag off) **no entra al bloque** → el `monto` **no se recalcula** y queda en el de la tanda 1 (**subcontado**). Resultado: **estado consistente** (la entrega existe, `pendiente`), solo el **`monto` desactualizado** (`monto < SUM(dispensaciones)`), **reconciliable** y **señalable en E** (discrepancia #1). No produce estado inconsistente ni entrega rota.

### Interacción con 141/143 (lo más delicado — confirmaciones explícitas)
- **Hereda el gate del loop:** el auto-create corre en el **mismo contexto DEFINER** del RPC, **después** del loop que ya filtró `f.empresa_id=v_emp AND sucursal_visible(ri.farmacia_id)`. El `INSERT...SELECT` **repite** `sucursal_visible(ri.farmacia_id)` + `EXISTS dispensaciones del grupo` → solo crea entregas de farmacias que **este actor efectivamente despachó**. Un **confinable** que despacha su sucursal crea entrega **SOLO de su sucursal** (las demás no pasan `sucursal_visible`).
- **NO abre ningún path nuevo de lectura/escritura** que 141/143 cierren: no lee `recetas`/`receta_items` fuera del confinamiento del loop; no expone PII (la dirección entra a `entregas`, cuya RLS es espejo de 141/143); no crea entregas cross-empresa (el loop ya limita a `v_emp`).
- **Pickup intacto:** la **única** rama de código nuevo en caliente es `IF flag AND modalidad='delivery'`. Con `pickup` (default) el `INSERT...SELECT` rinde **0 filas** (y el kill-switch lo puede saltar entero) → el despacho es **byte-idéntico** al de hoy. Verificado por diseño + smoke de no-regresión abajo.

### Verificación / Cutover Ola C (la más crítica)
1. **Dry-run de inercia sobre el histórico:** `SELECT count(*) FROM receta_items WHERE modalidad='delivery'` → **debe ser 0** (modalidad nació pickup en A; nadie llamó `fijar_modalidad_grupo` en prod aún). → el auto-create es inerte sobre todo lo existente.
2. **NO-REGRESIÓN del despacho pickup (las 2 vías), ANTES y DESPUÉS, idénticas** (BEGIN/ROLLBACK): despachar un grupo pickup vía `registrar_dispensacion` (token) y vía `registrar_dispensacion_dirigida` → mismas filas en `dispensaciones`, mismos `dispensado=true`, mismo `RETURN`, **0 entregas creadas**. Confinable/exento/cross-empresa → idéntico a pre-C.
3. **Smoke delivery (BEGIN/ROLLBACK):** marcar un grupo `delivery` (vía `fijar_modalidad_grupo` de A) → despachar → **nace 1 entrega `pendiente` con `monto`=SUM correcto**; **despacho parcial** (2ª tanda) → `monto` recalculado (D-1, estado pendiente); **multi-sucursal** (exento despacha 3337+147 ambos delivery) → **2 entregas, una por sucursal**; **confinable** solo crea la de su sucursal; **cross-empresa** → entregas separadas por empresa.
4. **Ciclo RPCs (Pent_ciclo/Pent_reabrir):** crear→asignar(same-sucursal)→en_camino→entregada feliz; transición ilegal → RAISE; fallida sin motivo → RAISE; idempotencia; delivery ajeno → RAISE; cola `listar_entregas_delivery` solo las propias; reapertura `fallida→asignada` por gestor (`intentos+1`, `reabierta_*`), por delivery → RAISE, de cobrada → RAISE; asignar delivery de otra sucursal → RAISE (#8).
5. **Best-effort (#4-B):** simular fallo del INSERT de entrega (p.ej. forzar un error en el bloque) → el **despacho COMMITEA** igual (dispensaciones + dispensado presentes) **Y** queda **1 fila en `private.delivery_autocreate_fallos`** + `WARNING` en logs → E detecta "delivery despachado sin entrega". Entrega faltante reconciliable con `crear_entrega`.
6. **Kill-switch encendiendo/apagando EN VIVO:**
   - `habilitado=false` → despacho delivery **NO** crea entrega (vuelve a pre-C); `=true` → vuelve a crear. **Backout sin redeploy.**
   - **Ausencia de fila** (borrarla) → COALESCE→`false` → **APAGADO** (fail-safe verificado).
   - **Apagado a mitad de grupo:** tanda 1 (on) crea entrega `pendiente`; `UPDATE ...false`; tanda 2 (off) → **no recalcula `monto`** → entrega intacta `pendiente`, `monto` subcontado (`monto < SUM`) → discrepancia #1 señalable en E. **Estado consistente, no bug.**
7. **Harness 141/143:** 459 filas, 0 ROJO, scan limpio (post-apply).
- **Cutover:** server-side puro (sin deploy front para los RPCs). **Apply (una migración):** tablas `private.delivery_flags` (seed `autocreate_entregas=true`) + `private.delivery_autocreate_fallos`; RPCs nuevos (`crear/asignar/reasignar/actualizar_estado_entrega`, `listar_entregas_delivery`); `CREATE OR REPLACE` de **`registrar_dispensacion` + `registrar_dispensacion_dirigida`** con el bloque best-effort. Grandfather-inerte (flag on pero 0 grupos delivery hoy → 0 efecto) → dry-run → smoke no-regresión pickup (2 vías) → smoke delivery → kill-switch on/off → harness → commit. Front de Ola C (panel gerente + PWA delivery) se marca aparte.

### Dependencias hacia D / E / F (anotadas)
- **D (cobro):** `registrar_cobro_entrega` consumirá la entrega `pendiente/asignada/en_camino` → setea `cobrado/at/por/metodo_cobro` (techo `entregas_cobrar`); + bucket evidencia (`evidencia_path`) + `actualizar_direccion_entrega` (geocodificar → lat/lng).
- **E (monitoreo):** `listar_entregas_monitoreo` (confinable ve su sucursal; exento toda la empresa) + `stats_entregas_sucursal`; **hereda 2 discrepancias de C a reconciliar:**
  - **Discrepancia #1 — `monto` subcontado:** `monto < SUM(dispensaciones.total_dispensado)` del grupo, en entregas no-pendientes (D-1 caso borde) o por kill-switch a mitad de grupo. Derivable por query; señal para el gerente (no se auto-corrige en Fase 1).
  - **Discrepancia #2 — entrega FALTANTE:** grupo `delivery` con `dispensaciones` pero **sin** fila en `entregas` (best-effort #4-B falló). E la detecta (a) **estructuralmente** (delivery group despachado sin entrega) y (b) leyendo **`private.delivery_autocreate_fallos`** (el rastro del EXCEPTION). Reconciliable con `crear_entrega`.
- **F (sin-QR):** `buscar_recetas_pendientes_paciente` (ortogonal, no crea entrega) — independiente de C.
- **Front Ola C:** panel gerente (crear/asignar/reasignar/estado) + PWA delivery (cola `listar_entregas_delivery` + actualizar_estado). Marcado, no implementado.

---

## 5 · OLA D — Cobro + bucket evidencia + geocodificación
> Toca **dinero** y **storage**. Least-privilege + lecciones de auditoría: **R6** (`evidencias-visitas` público — NO reusar) · **R9** (`resultados-examenes` privado pero con `getPublicUrl` + insert policy laxa). Patrón bueno a seguir: `comprobantes_scoped_*` (path `{empresa_id}/...` + `split_part(name,'/',1)=mi_empresa_proveedor()`).

### 5.1 · RPC `registrar_cobro_entrega` (DEFINER sp'', gate `entregas_cobrar` — TECHO 117)
```sql
CREATE FUNCTION public.registrar_cobro_entrega(p_entrega_id bigint, p_metodo_cobro text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas; v_ra_id uuid; v_monto numeric; v_es_delivery boolean;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_cobrar'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF p_metodo_cobro NOT IN ('efectivo','tarjeta','transferencia','sin_cobro') THEN RAISE EXCEPTION 'Método inválido'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);          -- confinamiento empresa + sucursal
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  v_es_delivery := (v_e.delivery_id = auth.uid());
  IF private.mi_sucursal() IS NOT NULL AND NOT v_es_delivery
     AND NOT COALESCE(private.tiene_permiso('entregas_gestionar'), false) THEN
    RAISE EXCEPTION 'No autorizado: no es tu entrega'; END IF;                -- el cobrador debe tener acceso
  IF v_e.cobrado THEN RAISE EXCEPTION 'Entrega ya cobrada'; END IF;           -- no recobrar
  IF v_e.estado NOT IN ('en_camino','entregada') THEN                         -- [DECISIÓN OSCAR (a)]
    RAISE EXCEPTION 'Solo se cobra desde en_camino/entregada (estado=%)', v_e.estado; END IF;
  -- monto RE-DERIVADO en el servidor (NO se confía en ningún parámetro del cliente)
  SELECT ra.id INTO v_ra_id FROM public.recetas_avanzadas ra WHERE ra.receta_base_id=v_e.receta_base_id;
  SELECT SUM(d.total_dispensado) INTO v_monto FROM public.dispensaciones d
    WHERE d.receta_avanzada_id=v_ra_id AND d.farmacia_id=v_e.farmacia_id;
  UPDATE public.entregas SET cobrado=true, cobrado_at=now(), cobrado_por=auth.uid(),
    metodo_cobro=p_metodo_cobro, monto=COALESCE(v_monto, monto), updated_at=now()
  WHERE id=p_entrega_id;     -- snapshot ATÓMICO: monto+metodo+cobrado_* en un solo UPDATE
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_cobro_entrega(bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_cobro_entrega(bigint,text) TO authenticated;
```
- **Sin `p_monto`:** el monto es **autoritativo del servidor** (`SUM(dispensaciones)` re-derivado al momento del cobro). No hay parámetro de monto del cliente que falsear.
- **[DECISIÓN OSCAR (a), CERRADO] Estados desde los que se cobra: `{en_camino, entregada}`** — COD: el delivery cobra al llegar (en_camino) o al confirmar (entregada). `pendiente`/`asignada` = aún no entregado; `fallida` = no hubo entrega → ninguno cobra.
- **`cobrado=true` ⇒ RAISE** (no recobro). El `chk_cobro_coherente` (B) ya exige `cobrado_at`+`cobrado_por`+`metodo_cobro` no nulos → el UPDATE los setea juntos.
- **Interacción D-1:** cobrar requiere `estado≠pendiente` → el guard de D-1 (`recalcula solo si estado='pendiente'`) **ya no aplica** a una entrega cobrada → el `monto` queda **congelado** en el del cobro. **Tanda de despacho DESPUÉS del cobro** → `monto` cobrado `< SUM(dispensaciones)` final → **discrepancia #1 para E** (ya anotada; no se auto-corrige, señal operativa).
- **[CASO BORDE — cobrada + fallida (cobro COD seguido de rechazo/reasignación)]:** se cobra en `en_camino` (`cobrado=true`) y luego la entrega pasa a `fallida` (rechazo post-pago, ausencia, etc.). Como **`fallida` NO revierte** (D-9 / inmutabilidad A6) y **`cobrado=true` persiste**, la entrega queda en **`estado='fallida' + cobrado=true`**. **Esto NO es un bug:** es realidad operativa COD (se pagó pero la entrega falló). La **devolución del dinero se maneja FUERA del sistema en Fase 1**. → **discrepancia VÁLIDA "cobrado+no-entregado" que E debe LISTAR** (`cobrado=true AND estado='fallida'`). Además, `reasignar_entrega` **bloquea la reapertura de una entrega cobrada** (RAISE si `cobrado=true`, ya en las salvaguardas) → una entrega **cobrada-y-fallida NO se reabre por RPC; queda terminal-cobrada** (su retorno/anulación es operativo).

### 5.2 · Bucket de evidencia (foto/firma) — NUEVO PRIVADO
- **Bucket `entregas-evidencia`, `public=false`.** NO reusar `evidencias-visitas` (R6 público). **NUNCA `getPublicUrl`** (R9) → solo **signed URLs**.
- **Path-scoping:** `{empresa_id}/{entrega_id}/{firma|foto}_{ts}.{ext}`. El 1er segmento (empresa) + 2º (entrega) permiten que la policy confine por empresa y por pertenencia de la entrega.
- **`entregas.evidencia_path`** = `text` nullable (ya existe, B). Guarda el **path**, NUNCA la URL firmada (se firma al leer).
- **Storage policy INSERT (subida)** — evita el bug R9 (ni laxa ni rota): el **delivery asignado** sube a su entrega, dentro del scope:
```sql
CREATE POLICY entregas_evidencia_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (
  bucket_id='entregas-evidencia'
  AND split_part(name,'/',1) = public.mi_empresa_proveedor()::text          -- 1er segmento = su empresa
  AND COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false)
  AND EXISTS (SELECT 1 FROM public.entregas e
              WHERE e.id = NULLIF(split_part(name,'/',2),'')::bigint
                AND e.empresa_id = public.mi_empresa_proveedor()
                AND e.delivery_id = auth.uid())                              -- es SU entrega asignada
);
```
- **Storage policy SELECT (para `createSignedUrl`)** — espejo de la RLS de `entregas` (empresa + sucursal_visible + slice delivery):
```sql
CREATE POLICY entregas_evidencia_select ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id='entregas-evidencia' AND (
    EXISTS (SELECT 1 FROM public.entregas e
            WHERE e.id = NULLIF(split_part(name,'/',2),'')::bigint
              AND e.empresa_id = public.mi_empresa_proveedor()
              AND COALESCE(private.sucursal_visible(e.farmacia_id), false)
              AND (public.mi_rol_proveedor() <> 'delivery' OR e.delivery_id = auth.uid()))
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  )
);
-- sin policy de UPDATE/DELETE → inmutable salvo owner/service_role. REVOKE no aplica (storage.objects gestionado por RLS).
```
- **Quién genera la signed URL + TTL:** el **front** (gerente/admin/delivery con acceso) llama **`createSignedUrl(path, ttl)`** — la policy SELECT de arriba lo **confina** (solo si la entrega le es visible). **[DECISIÓN OSCAR (b), CERRADO] TTL = 120 s** (corto; la URL es de un solo uso visual; se re-firma al re-abrir). Nunca se persiste la URL firmada.
- **Asociación SOLO vía RPC DEFINER** (no escritura directa a `evidencia_path`):
```sql
CREATE FUNCTION public.registrar_evidencia_entrega(p_entrega_id bigint, p_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_e public.entregas;
BEGIN
  IF NOT COALESCE(private.tiene_permiso('entregas_actualizar_estado'), false) THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_e FROM public.entregas WHERE id=p_entrega_id
    AND COALESCE(empresa_id=public.mi_empresa_proveedor(), false)
    AND COALESCE(private.sucursal_visible(farmacia_id), false);
  IF NOT FOUND THEN RAISE EXCEPTION 'Entrega no visible/no existe'; END IF;
  IF v_e.delivery_id <> auth.uid() THEN RAISE EXCEPTION 'Solo el delivery asignado adjunta evidencia'; END IF;
  IF p_path NOT LIKE (public.mi_empresa_proveedor()::text || '/' || p_entrega_id::text || '/%') THEN
    RAISE EXCEPTION 'Path fuera de scope'; END IF;                          -- el path debe ser de SU entrega
  UPDATE public.entregas SET evidencia_path=p_path, updated_at=now() WHERE id=p_entrega_id;
  RETURN (SELECT to_jsonb(e) FROM public.entregas e WHERE e.id=p_entrega_id);
END $$;
REVOKE EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_evidencia_entrega(bigint,text) TO authenticated;
```
- **Flujo:** delivery sube el archivo (policy INSERT scope+ownership) → llama `registrar_evidencia_entrega(entrega, path)` (valida delivery asignado + path) → guarda `evidencia_path`. Gerente/admin abre la entrega → `createSignedUrl(evidencia_path, TTL)` (policy SELECT confina). **Doble defensa:** storage policies + RPC.

### 5.3 · Geocodificación (best-effort, no bloquea)
- **`actualizar_direccion_entrega`** (DEFINER sp''), gate `entregas_gestionar` **o** el delivery asignado de la entrega; persiste `direccion_entrega`/`lat`/`lng`; confinado empresa+sucursal_visible. El **front** llama al **edge `geocodificar`** (texto→lat/lng) y pasa el resultado a este RPC (los RPCs no llaman edges).
```sql
(p_entrega_id bigint, p_direccion text, p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL) → jsonb
```
- **Cuándo corre (recomendado):** **on-demand al abrir el mapa** o **al asignar** (el front geocodifica y persiste). NO un job en Fase 1.
- **Best-effort:** la entrega es **válida sin coords** (ya establecido en C); el fallo de geocode **NO bloquea cobro ni estado** — `lat/lng` quedan NULL, el mapa muestra sin-pin, se navega por texto. Mismo patrón que C.
- **PII:** la dirección sigue saliendo **solo** por RPCs de entregas confinadas (el edge recibe el texto server-side; no se expone fuera del scope de entregas).

### 5.4 · Interacción / no-regresión
- D es **puramente aditiva** sobre `entregas` (Ola C): `registrar_cobro_entrega`, `registrar_evidencia_entrega`, `actualizar_direccion_entrega` + el bucket nuevo. **NO toca** `registrar_dispensacion(_dirigida)`, pickup, 141/143 ni emisión. **0 impacto** en el path de despacho. El bucket es nuevo (no toca `evidencias-visitas`/`resultados-examenes`).

### 5.5 · Cutover Ola D
- **Estructural:** RPC `registrar_cobro_entrega` (DEFINER sp'', gate techo, sin p_monto) + `registrar_evidencia_entrega` + `actualizar_direccion_entrega`; bucket `entregas-evidencia` (public=false) + 2 storage policies (INSERT scope+ownership, SELECT espejo entregas); columnas ya existen (B).
- **Smoke (BEGIN/ROLLBACK):** cobro feliz (cobrado_* + monto re-derivado correcto) · **recobro → RAISE** · cobrar **sin permiso/techo → RAISE** · cobrar entrega de **otra sucursal → RAISE** · cobrar en estado no permitido (pendiente/asignada/fallida) → RAISE · **tanda post-cobro** → monto NO se mueve (discrepancia #1 registrada, sin recobro) · **subida fuera de scope** (otra empresa/otra entrega) → DENEGADA · **subida por no-asignado** → DENEGADA · `registrar_evidencia_entrega` por no-asignado/path-fuera-de-scope → RAISE · **signed URL** se genera para quien ve la entrega y **expira** (TTL); no-visible → no puede firmar · **geocode best-effort** (dirección mala → lat/lng NULL, cobro/estado siguen) · **harness 141/143 verde**.
- **Backout:** D es aditiva → `DROP` de los 3 RPCs + bucket/policies revierte sin tocar el despacho (C intacto). No hay kill-switch necesario (no toca path caliente).

### 5.6 · Dependencias hacia E / F
- **E (monitoreo):** lee `cobrado/cobrado_at/cobrado_por/metodo_cobro` (estado de cobro), **3 discrepancias** (#1 `monto<SUM`; #2 entrega faltante; **#3 `cobrado=true AND estado='fallida'`** = cobrado-pero-no-entregado, COD), y la **evidencia** (genera signed URL TTL 120 s para mostrarla al gerente/admin, confinado). 
- **F (sin-QR):** independiente.

---

## 6 · OLA E — Monitoreo

| RPC | Firma | Gate | Confina |
|---|---|---|---|
| `listar_entregas_monitoreo` | `(p_estado text DEFAULT NULL, p_sucursal_id int DEFAULT NULL)→jsonb` | `entregas_ver` | empresa + sucursal_visible (gerente→su sucursal; admin/exento→todas). Expone paciente nombre+direccion+telefono (confinado) |
| `stats_entregas_sucursal` | `(p_desde date, p_hasta date, p_sucursal_id int)→jsonb` | `entregas_ver`/`recetas_reportes` | espejo `stats_recetas_sucursal`; agregados por estado/sucursal |

### Verificación Ola E
- Probe Pent_mon: gerente@X ve solo entregas de X; admin ve todas las de su empresa; cross-empresa cerrado; stats coinciden con conteos. PII (direccion/telefono) sale solo aquí (confinado), nunca en bandeja pickup.

---

## 7 · OLA F — Despacho sin-QR (ORTOGONAL, NO crea entrega)

### RPC `buscar_recetas_pendientes_paciente`
```sql
(p_nombre text, p_fecha_nac date) → jsonb     -- identidad mínima: nombre + fecha_nacimiento (pacientes los tiene)
  gate: recetas_dispensar; confina empresa + sucursal_visible
  devuelve: recetas con ítems pendientes (dispensado=false) ruteados a la SUCURSAL DEL CALLER para ese paciente
  → el despacho posterior usa registrar_dispensacion_dirigida (ya existe). NO crea entrega (es pickup).
```
- Suplantación mitigada: 2 datos (nombre+fecha_nac) + `despachado_por` audita + acotado a la sucursal del caller.

### Verificación Ola F
- Probe Pbusca: identidad correcta → lista solo pendientes de la sucursal del caller; cross-empresa/otra sucursal → vacío; no expone dirección (solo lo necesario para despacho mostrador). Independiente de entregas (no crea ninguna).

---

## 8 · INTERACCIONES CON PROD (explícito)

1. **141/143 (confinamiento por sucursal):** el auto-create (C) se inserta **dentro** de `registrar_dispensacion(_dirigida)`, **después** del gate `sucursal_visible` del loop → hereda el confinamiento; solo crea entregas para farmacias que el actor pudo despachar. La RLS de `entregas` (B) es **espejo** de 141/143 (empresa + sucursal_visible) → consistencia total. **Sin relajar** ningún filtro existente (AND conjuntivo).
2. **Ruteo per-ítem 3.3:** `modalidad` es per-`(receta, farmacia)` = **per-sucursal**, coherente con el ruteo per-ítem (cada ítem ya tiene `farmacia_id`). La uniformidad garantiza que un grupo de sucursal tenga una sola modalidad → una sola entrega. `fijar_modalidad_grupo` actualiza todo el grupo.
3. **RLS `farmacia_medicamentos`:** **sin interacción** — el surtido es free-text sin `medicamento_id` (verificado en el recon regulatorio) y el `monto` de la entrega viene de `dispensaciones`, no del surtido. Delivery no lee `farmacia_medicamentos`.
4. **`recetas` PK compuesto:** `entregas.receta_base_id` FK→`recetas(id)` funciona (id referenciable); **no** se asume PK simple.
5. **Despacho sin-QR (F)** reusa `registrar_dispensacion_dirigida` (141-gated) → mismo confinamiento; ortogonal a entregas.

---

## 9 · RESOLUCIONES PRE-APROBACIÓN (#1–#9)

### 9.1 · [#1 = D-1, CERRADO opción B] Despacho PARCIAL × delivery — monto recalculado por tanda
**Decisión Oscar:** el monto se **RECALCULA** como `SUM(dispensaciones.total_dispensado)` de ese `(receta, farmacia)` en **cada** tanda, con **guard `estado='pendiente'`** (una vez asignada/en_camino/cobrada → ya NO se recalcula). Implementación = `ON CONFLICT DO UPDATE SET monto=excluded.monto ... WHERE entregas.estado='pendiente'` (punto exacto: §4, dentro del bloque auto-create, **tras el loop** de `registrar_dispensacion(_dirigida)`). Caso borde "entrega no-pendiente + otra tanda" → monto NO se mueve, discrepancia señalable en monitoreo (E). Detalle completo en §4.

### 9.2 · [#2 — RESUELTO en vivo] FK `entregas.receta_base_id → recetas(id)`
Verificado: existe **`recetas_id_uniq: UNIQUE (id)`** standalone (además del PK compuesto `(id, paciente_id)`). → el FK es **válido**. **PRECONDICIÓN Ola B (check exacto antes de aplicar):**
```sql
SELECT 1 FROM pg_constraint WHERE conrelid='public.recetas'::regclass AND contype='u'
  AND pg_get_constraintdef(oid)='UNIQUE (id)';   -- debe devolver 1 fila
```
Si esa UNIQUE **no existiera**, el `CREATE TABLE entregas ... REFERENCES recetas(id)` **fallaría** (`there is no unique constraint matching given keys`) → habría que (i) `ALTER TABLE recetas ADD CONSTRAINT recetas_id_uniq UNIQUE (id)` primero, o (ii) anclar a otra columna única. **Hoy existe → no se requiere acción**, pero el check va como gate de la migración B.

### 9.3 · [#3 — CONFIRMADO] Freeze server-side, mismo RPC ambos paths
`fijar_modalidad_grupo` es el **ÚNICO** punto de cambio de modalidad para **ambos** (médico pre-marca y paciente cambia): gate `v_es_medico OR v_es_paciente`, y el **mismo guard server-side** `IF EXISTS (dispensado=true para ese (receta,farmacia)) → RAISE 'congelada'`. **"Última escritura gana" aplica SOLO mientras no esté congelado**; tras la 1ª dispensación del grupo, ambos paths reciben el RAISE. El freeze **NO** vive en UI. (La UI puede ocultar el control, pero la autoridad es el RPC.)

### 9.4 · [#4 — CORREGIDO: ROW era el defecto; STATEMENT-level es la versión correcta]
**Mi análisis previo era ERRÓNEO.** Afirmé que el UPDATE de grupo de `fijar_modalidad_grupo` no dispararía el trigger ROW "porque actualiza todo el grupo a la vez". **Falso:** un UPDATE multi-fila procesa **fila por fila**; el trigger `BEFORE ROW` en la fila 1 (cambiada a delivery) ve a las hermanas **aún en pickup** → divergencia **transitoria** → RAISE. Lo detectó el **smoke de 144** (`P0001 modalidad no uniforme en (receta 2404, farmacia 3337)`).
- **Fix (mig 145):** trigger `AFTER ... FOR EACH STATEMENT` con `REFERENCING NEW TABLE` → evalúa el **estado FINAL** del statement → el UPDATE de grupo uniforme pasa; un UPDATE divergente de 1 fila sigue rechazado (`count(DISTINCT modalidad)>1`).
- **Restricciones Postgres:** transition tables **no** se permiten con multi-evento ni con `UPDATE OF col` → **dos triggers** (`_ins` AFTER INSERT, `_upd` AFTER UPDATE sin lista de columnas). El de UPDATE dispara en **todo** UPDATE de `receta_items` (incl. `dispensado` del despacho) pero **nunca rechaza** grupos uniformes → costo = un lookup indexado por UPDATE, **sin cambio de semántica** del despacho (141/143 verdes confirmado).
- **Insert batch (`useRecetas`):** ítems entran pickup → grupo uniforme → 0 rechazos (no-regresión verificada).
- **Caso #1 (re-ruteo):** `NEW TABLE` basta (origen no se rompe por remoción; destino sí está en newtab). Verificado en vivo: re-rutear un ítem pickup a un grupo delivery → RAISE destino mixto.
- **Caso #2 (delivery+farmacia NULL):** `CHECK chk_modalidad_delivery_farmacia` lo rechaza. Verificado en vivo.
- **Verificado en smoke completo post-145:** los 9 casos verdes.

### 9.5 · [#5 — DEPENDENCIA marcada] Coordinación con el work item REGULATORIO (path de emisión)
Ola A (delivery: `receta_items.modalidad` + pre-marca en RecetaModal) y Regulatorio O1 (`emitir_receta` como único escritor + acuse) tocan el **mismo flujo de alta** de RecetaModal y el insert de `receta_items`:
- **(a) Antes de que O1 exista:** el `DEFAULT 'pickup'` + el trigger **NO rompen el insert directo actual del cliente** (§9.4: items entran pickup/farmacia_id null → trigger no-op). → **Ola A es segura sin O1.**
- **(b) Cuando O1 entre:** `emitir_receta` (único escritor) **debe setear `modalidad`** al insertar `receta_items` (default 'pickup' si no se especifica; el médico la pre-marca por grupo tras rutear, vía `fijar_modalidad_grupo`). El acuse regulatorio (en `handleAddMedicamento`) y la pre-marca de modalidad (al rutear) son **puntos distintos del MISMO modal** → no colisionan, pero **ambos** deben sobrevivir el cutover de `emitir_receta`.
- **Acoplamiento de orden:** Ola A puede ir **antes** de O1 (no depende de él). Pero **O1 debe conocer `modalidad`** (incluirla en su insert de items). → marcar en el doc regulatorio que **`emitir_receta` setea `modalidad` (default pickup)** como parte de su contrato. **Dependencia registrada en ambos docs.**

### 9.6 · [#6 — RESUELTO en vivo] Consistencia de tipos `paciente_id`/`medico_id`
| Columna | Tipo |
|---|---|
| `pacientes.id` | **bigint** |
| `recetas.paciente_id` | **bigint** ✅ (coincide) |
| `recetas_avanzadas.paciente_id` | **text** ⚠️ |
| `dispensaciones.paciente_id` | **text** ⚠️ |
| `recetas.medico_id` | uuid · `recetas_avanzadas.medico_id`/`dispensaciones.medico_id` | **text** ⚠️ |
| `pacientes.auth_user_id` | uuid · `private.paciente_es_mio` | **sobrecargada (bigint + text)** |
**Resoluciones aplicadas al diseño:**
- `entregas.paciente_id` = **bigint** FK→`pacientes(id)`. El auto-create toma `paciente_id` de **`recetas` (bigint)**, NO de `recetas_avanzadas` (text) — **ya corregido** en el bloque §4 (`JOIN recetas r ON r.id=v_receta_id`, `r.paciente_id`). Evita cast text→bigint.
- **Gate del paciente** (`fijar_modalidad_grupo`): `private.paciente_es_mio(r.paciente_id)` con `r.paciente_id` **bigint** → usa el overload bigint. ✅
- **`buscar_recetas_pendientes_paciente`** une por `pacientes` (bigint) + `recetas.paciente_id` (bigint) → sin mismatch. NO usar `recetas_avanzadas.paciente_id` (text).
- El **monto** (join `dispensaciones.receta_avanzada_id = v_ra.id`) **no** toca `paciente_id` → sin problema de tipo. Las columnas text de recetas_avanzadas/dispensaciones son una inconsistencia legacy preexistente; el diseño delivery **no la hereda** porque sourcea de `recetas`.

### 9.7 · [#7 — ACLARADO] Acoplamiento a `recetas_avanzadas`
**`entregas` NO ancla a `recetas_avanzadas`** — ancla a `recetas(id)`. El acoplamiento real es del **DESPACHO**, no de la entrega: `registrar_dispensacion` (QR) lee el token de `recetas_avanzadas`; `registrar_dispensacion_dirigida` **RAISE si no existe `recetas_avanzadas`** ('PDF no generado: no despachable'). → **todo despacho (delivery o pickup) ya requiere `recetas_avanzadas`**; es un hecho preexistente del spine, no introducido por delivery. El auto-create usa `v_ra.id` **solo** para el join del monto (`dispensaciones.receta_avanzada_id`). → **no hay dependencia nueva**: si hay despacho, hay `recetas_avanzadas`. La "dependencia" previa se reformula así y **no requiere acción**.

### 9.8 · [#8 — CONFIRMADO] Scope de lectura/asignación del rol delivery = sucursal_visible + delivery_id
- **`listar_entregas_delivery`** (DEFINER, bypassa RLS) replica **explícitamente**: `empresa_id=mi_empresa_proveedor() AND COALESCE(sucursal_visible(farmacia_id),false) AND delivery_id=auth.uid()`. → un delivery confinable **no ve entregas fuera de su sucursal**, ni de otros delivery.
- **`asignar_entrega`** valida que `p_delivery_id` sea una `cuentas_proveedor` rol delivery de la **misma empresa Y cuya `sucursal_id` corresponda a la `farmacia_id` de la entrega** (o exento) → no se puede asignar una entrega de la sucursal X a un delivery confinado a Y. Gate-antes-de-efecto.
- La **RLS de SELECT** (Ola B) ya confina por empresa+sucursal_visible; las RPCs DEFINER replican el mismo término (no se apoyan solo en delivery_id).

### 9.9 · [#9 = D-9, CERRADO opción a] `fallida` terminal-REABRIBLE-vía-gestión — sin reversión
**Decisión Oscar:** `fallida(motivo: rechazada|ausente|direccion_mala)` = estado de logística de delivery **SIN reversión** de dispensación ni restock (inmutabilidad A6: `dispensaciones` append-only, no se reabre `receta_items.dispensado`). **Ya NO es estrictamente terminal:** es **terminal-reabrible-vía-gestión**.
- **Reapertura (arista FIJADA, `fallida → asignada` vía `reasignar_entrega`):** SOLO `entregas_gestionar` (no el rol delivery); SOLO si `cobrado=false` (**RAISE si cobrada**); `intentos+1` + `reabierta_at`/`reabierta_por` (audita, no borra); `motivo_fallo→NULL`, nuevo `delivery_id`. **NO toca la dispensación.** Las 3 causas (rechazada/ausente/direccion_mala) usan la misma transición con el contador visible en el monitoreo E.
- **El med ya despachado (nota OPERATIVA, no lógica de sistema):** los medicamentos salieron de la sucursal; ante `fallida`, su retorno/descarte físico se maneja **fuera del sistema** (procedimiento de farmacia). Fase 1 **no** modela restock ni contra-asiento; el stock queda descontado; cualquier reposición es un alta de inventario operativa aparte.
- (b) reversión con contra-asiento se **difiere** a fase posterior por su choque con la inmutabilidad regulatoria (A6).

### Notas residuales (no bloquean)
- **Hook push (Fase 4):** punto marcado en `actualizar_estado_entrega`; sin tabla/efecto en Fase 1.
- **`pacientes.auth_user_id`** (uuid) es el vínculo auth↔paciente que usa `paciente_es_mio`; confirmado en vivo.

---

## DECISIONES YA CERRADAS RESPETADAS (checklist)
✅ modalidad nueva default pickup, per-sucursal, híbrida médico/paciente, congela tras despacho · ✅ UNA entrega por sucursal (UNIQUE) · ✅ dirección propia snapshot + lat/lng nullable + geocodificar · ✅ creación híbrida auto-al-despachar(delivery)/manual, pickup nunca crea · ✅ cobro snapshot SUM(dispensaciones) + metodo/cobrado/at/por · ✅ estados pendiente→asignada→en_camino→entregada/fallida(motivo) · ✅ 4 permisos finos, delivery confinable, exentos ven todo · ✅ bucket nuevo privado + signed URLs · ✅ monitoreo admin-todo/gerente-sucursal · ✅ PII solo por RPCs de entregas confinadas; delivery solo las suyas; pickup nunca expone dirección · ✅ RLS empresa+sucursal_visible, escritura solo por RPC DEFINER sp'' · ✅ buscar_recetas_pendientes_paciente ortogonal (pickup, no crea entrega).
```
```
