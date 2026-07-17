# 📋 PROMPT PARA SIGUIENTE SESIÓN — EzPayConnect

> Última actualización: 2026-07-17 (cierre de jornada: ramas ordenadas + foto-médico + foto-calendario + planes lab/farmacia completos, todo en prod)

**Reglas de siempre:** Claude = revisor/prompts · CC = ejecuta · Codex = recon solo-lectura · Oscar aprueba cada paso · prompts en bloque copiable · un bloque por vez · no guardar memoria hasta que lo pida.

---

## ▶️ ANTES DE NADA

1. Leé en la RAÍZ del repo `C:\dev\ezpayconnect`: este archivo, `ESTADO_PROYECTO_EZPAYCONNECT.md`, y `DISENO-PLANES-LAB-FARMACIA.md`.
2. **Chequeo diario O1** (pegáselo a CC):
   ```
   supabase db query --linked "select count(*) as nacidas_sin_correlativo from recetas where id > 2725 and numero_correlativo is null;"
   ```
   (debe dar 0)
3. GitHub ya se recuperó de la caída del 16-17 jul (All Systems Operational). Deploys/merges normales.

**DEUDAS QUE MUERDEN:** `schema_migrations` en 047 → NUNCA `db push`, aplicar SIEMPRE con `-f`. NUNCA `functions deploy` sin nombre. Build = `vite build` (sin tsc previo). Deploy = git push a `main` → Vercel (proyecto único, med.ezpayconnect.com). **tsc baseline = 82** (bajó de 88 al arreglar el drift real de `PlanConfiguracion.plan_base_id`; NO subirlo). Convención: los `supabase/fixes/*.sql` se commitean con `git add -f` (la carpeta `fixes/` está gitignoreada a propósito).

---

## ✅ CERRADO Y EN PROD (17 jul)

**Ordenamiento de ramas (post-caída GitHub):** PR #4 `fix/root-redirect-por-rol` (root redirect por rol + `AuthContext` `.single()`→`.maybeSingle()` sin 406) mergeado. Ramas `feat/foto-medico`, `feat/foto-medico-calendario`, `feat/planes-lab-farmacia` creadas, mergeadas y en prod. Sin ramas pendientes.

**Foto del médico (frente COMPLETO, en prod):**
- Backend: bucket público `fotos-medicos` + 4 policies + RPC `guardar_foto_medico` (escribe `medicos.foto_url` Y `perfiles.avatar_url`). `supabase/fixes/foto_medico_01.sql`.
- Perfil: `/medico/perfil` (`MedicoPerfilPage`) subir/ver foto + ítem en `MedicoSidebar`.
- Calendario clínica: `listar_medicos_clinica` ahora devuelve `foto_url = COALESCE(medicos.foto_url, perfiles.avatar_url)` (`supabase/fixes/foto_calendario_clinica_01.sql`; fue DROP+CREATE porque cambió el `RETURNS TABLE`, preservando gate `es_staff_calendario_clinica` + GRANTs). Avatares en header de columna y chips móviles con fallback a iniciales.
- Superficies cara-al-paciente (agendar `buscar_medicos_paciente`, chat `mis_medicos_chat`) YA mostraban la foto de antes — no se tocaron.

**Planes lab/farmacia (frente COMPLETO, Bloques 1-4, en prod):**
- **B1 (DB):** capacidades `laboratorio`/`farmacia` en `capacidades_catalogo` + RPC `otorgar_capacidad_empresa(empresa_id,codigo,hasta)` DEFINER (gate super_admin/admin_pais) + BACKFILL (lab 1, farmacia 3, `hasta=NULL` grandfathered). `supabase/fixes/planes_lab_farmacia_01.sql`. Modelo = capacidad (`empresa_capacidades`), NO tabla contratados.
- **B2 (checkout):** `PlanesLabPage` cablea `navigate('/proveedor/checkout?tipo=plan_laboratorio&referencia_id=<config.id>&monto=<precio>&descripcion=<enc>')`. Nueva página pública `/planes-farmacia` (`PlanesFarmaciaPage`, espejo, `tipo=plan_farmacia`). Confirmado: lab/farmacia reusan `cuentas_proveedor` (ver `LaboratorioPrivateRoute`) → el checkout `/proveedor/checkout` los acepta sin rebote.
- **B3 (verify):** `PagosProveedoresPage` — al verificar pago `plan_laboratorio`/`plan_farmacia` → `otorgar_capacidad_empresa(empresa_id, 'laboratorio'|'farmacia', hoy + atributos.duracion_dias||30)`. Fail-closed (si la capacidad falla, el pago NO queda verificado, igual patrón que campaña).
- **B4 (gate):** `LaboratorioLayout`/`FarmaciaLayout` leen `useCapacidades()` (`mis_capacidades()`) → sin capacidad activa muestran "Plan inactivo" (CTA a planes + logout). Es **visibilidad UI**; el gate server-side real (`empresa_tiene_capacidad` en RPCs clave) queda post-piloto. `mis_capacidades()` verificado: `(hasta IS NULL OR hasta > now())` → los 4 grandfathered pasan, nadie existente lockeado.
- **NOTA periodicidad:** el checkout manda `monto` pero NO mensual/anual; la capacidad se otorga por `atributos.duracion_dias` (default 30), igual que visitador. Si se quiere que un pago anual extienda 1 año, hay que cablear la periodicidad (checkout → pago → verify). Diferido.

**READINESS / ESCALABILIDAD (auditoría del piloto, 17 jul — código en prod):** Auditoría "¿aguanta 5,000 médicos?" → veredicto **SÍ, pendiente solo de config de infra**. Bloqueantes de código, CERRADOS:
- **Índices en rutas calientes** (10, `supabase/fixes/indices_piloto_01.sql`): citas(medico_id,fecha)/(clinica_id,fecha)/(paciente_id,medico_id), recetas(paciente_id), receta_items(farmacia_id), pagos_proveedor(empresa_id), medico_clinicas(clinica_id), examenes/facturas(medico_id), disponibilidad_medico. Plain `CREATE INDEX IF NOT EXISTS` (tablas chicas).
- **asistente-ia fail-closed** (edge deployada): sacado el mock que devolvía sugerencia clínica FALSA ante error de cuota → ahora error honesto 503/504 + timeout 25s (AbortController). El front (`AsistenteIA.tsx`) ya falla seguro.
- **N+1 + dumps de frontend** (`perf/hooks-piloto` mergeada): colapsado el N+1 de `receta_items` vía embed PostgREST (`useRecetas`/`useHistorialCompleto`/`useWebAppRecetas`); `autoFetch:false` en `ConsultaPage`/`RecetaModal` (ya no pagan dumps de lista solo para mutar); `.limit(500)` en recetas/facturas. RLS ya scopea por rol (NO agregar filtro `medico_id` explícito: rompería staff/admin).

**EMAIL DE FACTURAS REAL (17 jul, prod, merge `fe065bc`):** reemplazado el `alert()` simulado de `FacturasPage` por envío real: nueva Vercel function `api/send-factura.ts` (espejo de `api/send-receta.ts`, gate de rol clínico/admin, mismo `RESEND_API_KEY`) + hook `useEnviarFactura` + diálogo con email del paciente pre-cargado (`useFacturas` ahora trae `pacientes(...,email)`). Cierra el [D] "FacturasPage email falso".

**PESO EN LIBRAS (17 jul, prod):** `src/lib/unidades.ts` (conversiones + `PAISES_LB = {'GT'}`, extensible) + `useUnidadPeso()` (resuelve código vía `configuracion_pais`) + toggle kg/lb en `FormularioVitales` (usa `useUnidadPeso` **interno** → aplica a TODOS los forms de vitales) + display en `ConsultaPage`. **Canónico SIEMPRE kg** (el trigger `trg_calcular_imc` y el histórico intactos); lb es solo capa de input/display, con buffer local en el input para no jitterear. Default lb en GT, toggle para overridear.

**Sesiones previas (16-17 jul):** reset/set-password COMPLETO (allowlist YA configurada, el flag de fable fue falso positivo — NO es bloqueante), Sentry vivo + scrubbing, imprimir cubierto, decisiones Frente 2. (Historial en ESTADO.)

---

## 📋 PENDIENTES (orden sugerido)

**0. INFRA PRE-PILOTO (acción de Oscar, dashboard Supabase — bloqueante #3 de la auditoría):** el proyecto está en plan **FREE** (compute Nano, `max_connections=60`, Realtime ~200 concurrentes, 50k MAU, auto-pausa). NO aguanta 5k médicos + pacientes. **Subir a Pro** (Billing→Subscription, ~$25/mes: 100k MAU, sin auto-pausa) + **compute Small/Medium** (Compute and Disk) + verificar/subir el **límite de Realtime concurrente** (Pro ~500 default; pico estimado 1,500-2,500 con chat). Hacerlo **2-3 días antes** del piloto (no el día 1) para smoke-test. Costo del piloto ≈ $30-250/mes según compute + MAU de pacientes que se logueen.

**1. LIMPIEZA DATOS QA** (DB, `-f`, se puede sin GitHub): ~38 filas QA/prueba contaminan reportes del piloto. Recon Codex que enumere filas exactas → bloque reversible. **OJO:** los super_admin/QA que Oscar DEJA: `admin.qa@`, `doctor@prueba.com`, y las cuentas grandfathered `laboratorio.qa@` / `farmacia.qa@` (más las empresas backfilleadas).

**2. CHICOS / CLEANUP:**
- `PlanesVisitadorPage.tsx` (la pública, `src/pages/planes/`) tiene el mismo `alert()` muerto que tenía PlanesLab → cablear a `/proveedor/checkout?tipo=plan_visitador` (cierra el hallazgo [D] de la auditoría). Mismo patrón que el fix de lab (referencia_id = config.id).
- Foto del médico en **Personal de clínica** (hoy icono por rol; la RPC `obtener_personal_clinica` ya joinea `medicos`, faltaría que devuelva `foto_url` + avatar en la fila). Add-on del frente foto.
- **Follow-ups de perf (auditoría, no bloqueantes):** picker de pacientes con búsqueda server-side (hoy `usePacientes` baja la lista completa para el selector de `RecetaModal`); `.limit()` en `useCitas`/`usePacientes` y en el dropdown país-wide de `CitasPage:179`; poda de `RecetasPage` (importada sin `<Route>`, huérfana).

**MEDIOS de la auditoría (aguantan el piloto, hacer antes de escalar más):** `procesar-recordatorios` sin lock anti-doble-corrida → emails duplicados a pacientes (corrección real); `enviar-push-campana` sin LIMIT → una campaña grande muere a mitad; Realtime chat sin filtro server-side en 3 canales (mayor win de escala, esperar a definir cap de Realtime en Pro); `WebAppDashboard` a `count head:true`; Resend con backoff; `consultar-biblioteca` con api_key NCBI.

**3. DIFERIDOS post-piloto:** check-in offline (IndexedDB+sync), imprimir resultado solo-texto (PDF generado), gate SERVER-SIDE de lab/farmacia con `empresa_tiene_capacidad` en RPCs clave, periodicidad anual real en checkout de planes, cosmético (dashboard admin con mocks Math.random, buscador navbar decorativo, ingresos ×250, rutas huérfanas V1, hooks/lib muertos).

---

## 🧭 CONTEXTO

Oscar viaja a Guatemala el sábado; sigue trabajando por Escritorio Remoto (Chrome Remote Desktop "PC Casa", 24/7, sin suspensión). Todo el código en GitHub (`github.com/ezpayusa/ezpayconnect`). Auditoría pre-piloto (fable5): veredicto LISTO condicionado — 0 RPCs rotos, 0 catch silenciosos, 8/8 módulos con backend real. Working tree con untracked de Oscar que se dejan **floating a propósito**: manuales PDF + `scripts/*.mjs` (generadores de manuales, prueba en Codex), y los 3 de siempre (`AUDITORIA-*`, `CODEX_*`, `_recon_*`).
