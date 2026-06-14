# Paneles (Afines + Farmacias) — Progreso / Handoff

> Handoff del trabajo de **paneles** (separado de la remediación de seguridad). Diseño completo en
> `docs/DISEÑO_PANELES.md`. Este archivo = "dónde estamos y cómo retomar limpio".

## Ramas
- **`seguridad/rls-remediacion`**: remediación RLS Fases 0–6 + **Inc.0** (cierres de huecos de
  proveedores). Migraciones **067–077**. Lista para merge a `main` (lo decide el usuario).
- **`paneles/farmacia-tenant`** (rama activa): construcción de paneles, **Inc.1 + Inc.2** sobre la base
  de seguridad.

## Estado por incremento
| Inc | Qué | Estado | Migración |
|---|---|---|---|
| 0 | Cerrar huecos proveedores (planes_asignaciones, campanas_publicitarias) + CHECK tipo | ✅ HECHO y pusheado (en `seguridad/rls-remediacion`) | 077 |
| 1 | Farmacia **tenant** (convivencia + promoción super_admin) | ✅ HECHO y pusheado | 078 |
| 2 Frente A | Modelo de **permisos data-driven** + RPC anti-escalada de roles | 🟡 **DISEÑADO (BORRADOR), NO aplicado** | 079 |
| 2 Frente B | UI portal `/farmacia/*` | ⛔ no empezado (va sobre el Frente A) | — |

Harness verificado hasta **P1–P71 verde** (Inc.1). Los probes **P72–P82** (Inc.2 Frente A) están escritos
y su **rojo capturado**, pero **079 NO se aplicó** a staging ni a la BD.

## Resumen del borrador `079_inc2_permisos_data_driven.sql` (NO aplicado)
- **Tablas catálogo** (escritura solo super_admin, lectura authenticated):
  - `roles_empresa_catalogo(tipo_empresa, rol, nivel, es_admin, label)`.
  - `permisos_empresa_rol(tipo_empresa, rol, accion)` (FK al catálogo).
- **Seed `tipo='farmacia'`** con niveles: `admin` 100 (es_admin) · `gerente_farmacia` 80 · `supervisor`
  60 · `inventario`/`finanzas`/`pagador` 40 · `cajero`/`dependiente`/`delivery` 20. Acciones:
  config_empresa, usuarios_roles, inventario_editar, ventas_caja, delivery, finanzas_reportes, pagos_ezpay.
- **Helper `private.tiene_permiso(accion)`** (SECURITY DEFINER, `search_path=''`, `COALESCE(...,false)`):
  resuelve rol del usuario en su empresa → consulta el catálogo. Las políticas del Inc.1
  (`farmacias_tenant_update` → `config_empresa`; `farm_med_tenant_all` → `inventario_editar`) pasan a
  usarlo **conservando el scope de empresa (AND `mi_empresa_proveedor`)**. Lectura pública intacta.
- **RPC `asignar_rol_miembro(target, nuevo_rol)`** (SECURITY DEFINER, `search_path=''`, COALESCE):
  jerarquía anti-escalada — requiere `usuarios_roles`; scope empresa; no tocar a un Admin salvo Admin;
  Admin asigna cualquier rol, no-Admin solo nivel **estrictamente inferior**.
- **Probes diseñados P72–P82**: P72/P73/P75 (rol sin permiso NO edita inventario/datos) → BLOQUEADO;
  P74 (Inventario edita inventario) → OK; P76–P80 (no-escalada: Gerente no asigna/modifica Admin, no
  asigna Gerente; operativo no asigna; no asigna en empresa ajena) → BLOQUEADO; P81/P82 (Admin asigna
  cualquiera; Gerente asigna operativo) → OK. *(Reparto: reasignar cuentas reales a la empresa-farmacia
  dentro del ROLLBACK, porque `cuentas_proveedor.id` tiene FK a `auth.users`.)*

## ⚠️ AJUSTES PENDIENTES de la revisión — RESOLVER ANTES DE APLICAR 079
**(a) CRÍTICO — el RPC debe ser el ÚNICO camino para tocar `rol_en_empresa`.**
Hoy el borrador no impide cambiar el rol por UPDATE/INSERT directo en `cuentas_proveedor`. Falta:
  - Revisar las políticas RLS de `cuentas_proveedor` (¿hay UPDATE propio que permita auto-editar el rol?)
    y **cerrar la escritura directa de la columna `rol_en_empresa`** (p.ej. quitar UPDATE directo del rol;
    que solo `asignar_rol_miembro` / super_admin lo cambien) — column-level o vía política/trigger.
  - Revisar las **edge functions de alta de personal** (`registrar_visitador_desde_invitacion`,
    `invitar_miembro_proveedor`, `cambiar_rol_proveedor` y similares): que respeten la jerarquía y no
    sean una puerta trasera de escalada.
  - **Probes de puerta trasera** a añadir: (1) un no-admin cambia su/otro `rol_en_empresa` por **UPDATE
    directo** → BLOQUEADO; (2) **auto-ascenso** (un miembro se sube a admin por UPDATE directo) → BLOQUEADO.

**(b) MENOR — `asignar_rol_miembro` valida que `nuevo_rol` exista en `roles_empresa_catalogo` para el
tipo del TARGET.** El borrador ya valida existencia contra el tipo del asignador (= target, misma empresa);
hacerlo explícito/robusto contra el tipo del target.

## Cómo retomar (próxima sesión, en `paneles/farmacia-tenant`)
1. Resolver (a) y (b) en `079` (+ las edge functions si aplica).
2. Añadir los probes de puerta trasera (UPDATE directo / auto-ascenso).
3. Patrón de siempre: capturar rojo → MOSTRAR → OK del usuario → aplicar a staging → harness
   **P1–P8x verde** (P65–P71 + no-escalada + puerta trasera) → build → commit.
4. Luego **Frente B**: UI `/farmacia/*` (FarmaciaLogin/Registro + guard por `tipo='farmacia'` +
   secciones), reutilizando el patrón del portal de laboratorio. El guard de UI **solo oculta/muestra**;
   la autorización real la impone la RLS del Frente A.

> Nada aplicado a staging en este cierre. `079` y los probes P72–P82 quedan **commiteados como BORRADOR**.
