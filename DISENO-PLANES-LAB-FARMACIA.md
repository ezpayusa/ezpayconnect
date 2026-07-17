# 🧪💊 DISEÑO — Planes reales de Laboratorio y Farmacia

> Fecha: 2026-07-17
> Estado: **Bloque 1 (backend) APLICADO en prod.** Bloques 2/3/4 (frontend) pendientes (esperan GitHub).
> Contexto de seguridad: `schema_migrations` en 047 → NUNCA `db push`, aplicar con `-f`; NUNCA `functions deploy`.

---

## Objetivo

Que **laboratorio y farmacia tengan plan real desde el piloto**, con el mismo modelo que visitador: la empresa elige plan → checkout con **comprobante** → el **admin verifica el pago** → se activa. **Sin pasarela de pago; pago por fuera** (uniforme con todo el sistema, decisión de Oscar).

---

## Decisión de modelo: CAPACIDAD (no tabla "contratados")

Se usa `empresa_capacidades`, **no** una tabla dedicada como `planes_visitador_contratados`. Razón: el plan de lab/farmacia es "**acceso al módulo**" (suscripción sin cuota consumible; visitador necesita su tabla por las visitas incluidas/usadas). Reusa la infra existente: `empresa_capacidades`, `mis_capacidades()`, `private.empresa_tiene_capacidad()`.

---

## Datos confirmados por recon (Codex, 17 jul)

- Catálogo de capacidades = `public.capacidades_catalogo` (cols: `codigo, nombre, descripcion, orden, activo, pais_id, ...`).
- `empresa_capacidades.capacidad_codigo` tiene **FK** → `capacidades_catalogo(codigo)` (por eso el código debe existir en el catálogo antes de referenciarlo).
- UNIQUE de `empresa_capacidades` = `(empresa_id, capacidad_codigo)` (usado para ON CONFLICT).
- `empresa_capacidades.origen` acepta solo `'tier'`/`'suelta'` (CHECK). Usamos `'suelta'`.
- `empresas_proveedoras` **no** tiene columna `activa`; usa `estado text` (valor vivo `'activa'`). Tipos vivos: `laboratorio_clinico` (1), `farmacia` (3), `laboratorio_farmaceutico` (1), `empresa_afin` (1). El portal de lab es para `laboratorio_clinico`.
- **Lab** ya tiene página pública de planes (`/planes-lab` → `PlanesLabPage`), pero su botón "Proceder al Pago" es un `alert()`.
- **Farmacia NO tiene página de compra** (solo config administrativa `PlanesFarmaciaConfigPage`). Hay que **crearla**.
- Patrón de checkout reusable (visitador): `/proveedor/checkout?tipo=plan_visitador&referencia_id=<planes_configuracion.id>&monto=<precio>&descripcion=<encodeURIComponent(nombre)>`.
- Rama admin actual (`PagosProveedoresPage`): al verificar un pago `tipo='plan_visitador'` → lee `planes_configuracion` → inserta `planes_visitador_contratados`. Solo existen ramas `plan_visitador` y `campana`.

---

## Piezas

### Pieza 1 — DB (APLICADO ✅) — `supabase/fixes/planes_lab_farmacia_01.sql`
1. Agregó códigos `laboratorio` y `farmacia` a `capacidades_catalogo` (orden 5/6, activo=true).
2. RPC `otorgar_capacidad_empresa(p_empresa_id uuid, p_codigo text, p_hasta timestamptz)` `SECURITY DEFINER`, `search_path=''`, gate `private.tiene_rol(['super_admin','admin_pais'])`, restringida a los 2 códigos, upsert por `(empresa_id, capacidad_codigo)`. REVOKE public / GRANT authenticated.
3. **BACKFILL** de existentes activos (`estado='activa'`): `laboratorio` a los `laboratorio_clinico`, `farmacia` a los `farmacia`, con `hasta=NULL` (grandfathered, sin vencimiento). Resultado verificado: laboratorio 1, farmacia 3.

### Pieza 2 — Checkout (frontend, PENDIENTE)
- **Lab:** en `PlanesLabPage`, reemplazar el `alert()` del botón por `navigate('/proveedor/checkout?tipo=plan_laboratorio&referencia_id=<config.id>&monto=<precio>&descripcion=<enc>')`. `config.id` = `planes_configuracion.id` (lo devuelve `getConfigForPlan`).
- **Farmacia:** CREAR la página de selección (espejo de `VisitadorPlanesPage`/`PlanesLabPage`), filtrando `planesBase` tipo `'farmacia'`, con `tipo=plan_farmacia`.
- Si la página se abre sin login → rutear a registro/login del portal primero (como hace `PlanesPage` médico con `user` null).

### Pieza 3 — Admin verifica (frontend, PENDIENTE) — `PagosProveedoresPage`
- Agregar ramas `tipo='plan_laboratorio'` y `'plan_farmacia'` en el handler de verificar pago → al verificar, `supabase.rpc('otorgar_capacidad_empresa', { p_empresa_id: pago.empresa_id, p_codigo: 'laboratorio'|'farmacia', p_hasta: <fecha_fin_ciclo> })`.
- Reusa la notificación `notificar_pago_resultado` que ya corre al verificar.

### Pieza 4 — Gate (frontend, VA ÚLTIMO) — PENDIENTE
- `LaboratorioLayout` y `FarmaciaLayout` leen `mis_capacidades()`; sin la capacidad activa → estado "Plan inactivo / contactá al admin" (o banner) en vez del portal.
- Nivel **visibilidad UI** (como visitador). Los existentes ya están cubiertos por el backfill → no se cortan; los nuevos sin plan verificado ven el estado inactivo.
- (Endurecer server-side con `private.empresa_tiene_capacidad` en RPCs clave = **post-piloto**.)

---

## Orden de ejecución (el orden IMPORTA)

- **Bloque 1 (DB):** ✅ HECHO — catálogo + RPC + backfill. El backfill dejó a los existentes cubiertos **antes** de que exista ningún gate → cero lockout.
- **Bloque 2/3 (checkout + admin verify):** frontend, esperan GitHub.
- **Bloque 4 (gate):** frontend, **último**, después de que el backfill ya esté (ya está).

**Regla de oro:** backfill (Bloque 1, ya aplicado) SIEMPRE antes del gate (Bloque 4).
