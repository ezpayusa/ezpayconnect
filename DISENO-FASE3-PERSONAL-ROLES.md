# 👥 DISEÑO — FASE 3 LAB: Personal y Roles del laboratorio

> Fecha: 2026-07-16
> Estado: CERRADO + DEPLOYADO en prod (merge e72d976). Seed vivo en prod (fase3_01).
> Contexto de seguridad: schema_migrations en 047 → NUNCA `db push`; aplicar con `-f`; NUNCA `functions deploy` sin nombre.

---

## Objetivo

Dar al portal del laboratorio la misma gestión de "Personal y Roles" que ya tiene farmacia: un admin del lab
invita/gestiona a su equipo, y cada rol ve/hace solo lo suyo. Todo **reusando** el modelo data-driven de
farmacia — sin backend nuevo salvo el seed de catálogo.

---

## Decisiones

1. **Opción B (data-driven).** Roles y permisos viven en catálogo (`roles_empresa_catalogo` +
   `permisos_empresa_rol`), legibles por `authenticated`. La UI gatea leyendo esos catálogos; **no** hay
   lógica de roles hardcodeada en el front.
2. **3 roles del lab:** `admin` (nivel 100, es_admin), `tecnico` (nivel 40), `recepcion` (nivel 40).
3. **Gating en dos niveles (UX):** filtro del sidebar por `accion` + gates internos por página. La barrera
   **real** la imponen RLS + los RPC `SECURITY DEFINER` (los gates del front solo evitan mostrar acciones
   que el servidor rechazaría).
4. **Sin concepto de "solo lectura":** no hay un permiso/rol read-only. La lectura es simplemente la ausencia
   de la `accion` de escritura — el listado/vista queda visible y solo se ocultan/deshabilitan las acciones
   de escritura que el rol no tiene.

---

## Seed (fase3_01_seed_roles_laboratorio.sql)

### `roles_empresa_catalogo` (tipo_empresa = laboratorio_clinico)

| rol | nivel | es_admin | label |
|-----|-------|----------|-------|
| admin | 100 | ✅ | Administrador |
| tecnico | 40 | — | Tecnico/Bioquimico |
| recepcion | 40 | — | Recepcion |

### `permisos_empresa_rol` (acción × rol)

| acción | admin | tecnico | recepcion |
|--------|:-----:|:-------:|:---------:|
| usuarios_roles | ✅ | | |
| config_empresa | ✅ | | |
| catalogo_examenes_editar | ✅ | | |
| resultados_cargar | ✅ | ✅ | |
| walkin_registrar | ✅ | | ✅ |
| afiliaciones_gestionar | ✅ | | ✅ |

Idempotente por `ON CONFLICT (tipo_empresa, rol)` y `(tipo_empresa, rol, accion)` → re-correrlo no duplica.

---

## Reuso de backend (cero backend nuevo salvo el seed)

Todo el cableado de alta/roles ya existía del Frente A de proveedores y es **tipo-agnóstico** (opera sobre
`cuentas_proveedor` / `empresas_proveedoras` por `empresa.tipo`):

| Pieza | Rol |
|-------|-----|
| edge `invitar-staff-proveedor` | Alta Opción B: crea/encuentra el auth user y delega la autz al RPC DEFINER. Ramas: nuevo (credencial por email) / vinculado (usuario existente) / 409 (ya tiene cuenta proveedor). |
| RPC `vincular_membresia_proveedor` (DEFINER) | Gate invitador = `usuarios_roles`; empresa/rol forzados server-side; guard 1:1 (una membresía por usuario). |
| RPC `autorizar_invitacion_staff` (DEFINER) | Autorización server-side de la invitación (gate `usuarios_roles`). |
| RPC `asignar_rol_miembro` (DEFINER) | Cambio de rol: jerarquía, mismo-empresa, no-tocar-Admin, último-Admin. |
| RPC `cambiar_estado_miembro_proveedor` (DEFINER) | Activar/desactivar: admin/misma-empresa/no-uno-mismo. |

El gate server-side de todos estos RPC se apoya en `private.tiene_permiso`, que resuelve la autorización
leyendo el catálogo data-driven (`permisos_empresa_rol`) **+ overrides por cuenta** — misma fuente que la UI,
así que el front (via `useLaboratorioPermisos`) y el servidor no divergen.

El seed del lab es lo único que se agregó a DB; el resto de la maquinaria ya estaba deployada.

---

## Frontend (por archivo)

| Archivo | Cambio |
|---------|--------|
| `src/laboratorio/hooks/useLaboratorioPermisos.ts` | **Nuevo.** Copia del hook data-driven de farmacia (`useFarmaciaPermisos`), tipo `RolFarmacia`→`RolProveedor`. Lee `permisos_empresa_rol` + `roles_empresa_catalogo` por `empresa.tipo` + `rol`. Expone `tienePermiso`, `roles`, `rolesAsignables`, `soyAdmin`, `loading`. |
| `src/laboratorio/pages/LabPersonalPage.tsx` | **Nuevo.** Espejo de `FarmaciaPersonalPage` sin sucursales: gate `usuarios_roles`, listar `cuentas_proveedor` por `empresa_id`, invitar (edge, `sucursal_id: null`), cambiar rol (`asignar_rol_miembro`), toggle activar/desactivar (`cambiar_estado_miembro_proveedor`), selector desde `rolesAsignables`. |
| `src/App.tsx` | Ruta `/laboratorio/personal` (lazy `LabPersonalPage`). |
| `src/laboratorio/layout/LaboratorioLayout.tsx` | `NavItem.accion?`; ítem "Personal y Roles" (icon `Users`, accion `usuarios_roles`); `accion` en walk-in/afiliaciones; filtro `NAV_ITEMS.filter(i => !i.accion || tienePermiso(i.accion))`. |
| `src/laboratorio/pages/LabOrdenesPage.tsx` | Gate `resultados_cargar` sobre Recibir/En proceso/Resultado (Ver queda visible). |
| `src/laboratorio/pages/LabCatalogoPage.tsx` | Gate `catalogo_examenes_editar` sobre agregar/toggle/eliminar (lectura queda). |
| `src/laboratorio/pages/LabWalkInPage.tsx` | Gate de PÁGINA `walkin_registrar` (bloquea URL directa). |
| `src/laboratorio/pages/LabAfiliacionesPage.tsx` | Gate de PÁGINA `afiliaciones_gestionar`. |
| `src/laboratorio/pages/LabPerfilPage.tsx` | Gate `config_empresa`: `<fieldset disabled>` sobre los inputs + oculta Guardar (la vista queda). |

**Typecheck:** `npx tsc --noEmit -p tsconfig.app.json` → **88 (baseline), sin regresión.** Farmacia sin tocar.

---

## Matriz de permisos efectiva

| Rol | Sidebar visible | Puede |
|-----|-----------------|-------|
| **Admin** | Todo | Todo (personal, config, catálogo, resultados, walk-in, afiliaciones) |
| **Tecnico** | Dashboard, Órdenes, Catálogo (RO), Perfil (RO), Notificaciones | `resultados_cargar` (cargar resultados en Órdenes) |
| **Recepcion** | + Walk-in, Afiliaciones | `walkin_registrar` + `afiliaciones_gestionar` |

Dashboard, Órdenes, Catálogo, Perfil y Notificaciones quedan **visibles para todos** (sin `accion`); sus
acciones internas de escritura sí van gateadas.
