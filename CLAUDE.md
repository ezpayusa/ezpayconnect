# EzPayConnect — Memoria de proyecto

Plataforma médica con paneles de admin (admin-ezpay), proveedor, país (admin_pais) y paciente / clínica.
Stack: React + Vite + TypeScript, Supabase / Postgres, deploy en Vercel, repo en /c/dev/ezpayconnect.

## Reglas de trabajo (mantener siempre)
- Diagnosticar antes de tocar nada. Rastrear el flujo de datos de punta a punta y confirmar la causa raíz (idealmente contra la DB viva) antes de escribir código.
- Un commit por bloque, con mensaje claro. Nada de un commit gigante al final.
- Verificar en cada cambio: tsc -p tsconfig.app.json (baseline actual = 82 errores; objetivo = 0 nuevos) + vite build verde + prueba por rol en prod.
- NUNCA ampliar policies de RLS sobre tablas adyacentes a datos médicos (p. ej. campana_metricas). Para dar acceso, usar RPCs SECURITY DEFINER con search_path='', fail-closed (si el scope es NULL → 0 filas) y gate interno.
- Probar aislamiento por rol impersonando request.jwt.claims en prod: cada rol ve lo suyo y no lo ajeno.
- **Harness de RLS (`tests/rls/probes_escritura.sql`): OBLIGATORIO correr `python tests/rls/b2_guard.py`
  (o `npm run harness:guard`) al tocarlo.** Es el gate de estructura del frente B2: falla si aparece
  una sentencia DML/DDL fuera de un bloque `DO` con `EXCEPTION` handler, o si crecen los bloques `DO`
  sin handler. Está enganchado como hook de pre-commit en `.githooks/pre-commit`; en un clone nuevo
  hay que activarlo una vez con `git config core.hooksPath .githooks`.
  **Por qué**: el harness corre en UNA transacción — una sentencia que revienta fuera de un handler
  no da rojo, MATA la transacción y la salida queda vacía, que se lee como "todavía no lo corrí".
  Pasó dos veces (18cf819 y el lote 1 de PA-FAILOPEN) y una de ellas tardó dos meses en detectarse.
  Baselines vivos: `top_level_dml_ddl=0` (excluye `pg_temp`), `do_sin_handler=319` (deuda con fecha,
  la ataca la fase 2 de B2). El señalizador P516 del harness los publica, pero NO mide: el gate es el script.

## Modelo de identidad / helpers
- mi_empresa_proveedor() → empresa_id del proveedor logueado desde cuentas_proveedor (tipo-agnóstica; cubre los 4 tipos: farmacia, laboratorio_clinico, laboratorio_farmaceutico, empresa_afin).
- get_auth_user_rol() / get_auth_user_pais_id() → rol y país del usuario desde perfiles.
- Gate de país estándar: super_admin (cualquier país) O admin_pais con get_auth_user_pais_id() = p_pais_id (rechaza con 42501 no_autorizado si es admin de otro país).

## Frente cerrado: métricas de publicidad (HEAD final 9fb665e, todo en prod)
Causa raíz: RLS super_admin-only sobre campana_metricas + vistas security_invoker → métricas de anuncios en 0 para proveedor y para panel de país. Vínculo proveedor↔campaña se hacía por título (frágil).

Solución (RPCs SECURITY DEFINER, sin ampliar RLS):
- metricas_campana_proveedor() — scope mi_empresa_proveedor(). Consumida por useMetricasCampana / PublicidadMetricasPage (los 4 tipos).
- metricas_campana_pais(p_pais_id) — con el gate de país; extendida para devolver empresa_id / empresa_nombre / empresa_tipo (desglose por empresa). Consumida por PaisDashboardPage y useMetricasCampanaAdmin.
- RPC de frequency cap scoped a auth.uid() (antes devolvía [] y el cap nunca se aplicaba).
- campanas_publicitarias + empresa_id y solicitud_campana_id (con backfill 14/14). Los 3 orígenes de creación de campañas setean el dueño (aprobar_solicitud_campana RPC, PagosProveedoresPage, y el form manual admin = house-ad con empresa_id NULL a propósito).
- CHECK chk_campana_dueno: solicitud_campana_id IS NULL OR empresa_id IS NOT NULL (una campaña nacida de solicitud debe llevar dueño; house-ads siguen válidas).

Commits del frente: 50ee110 (A) · 44ef4e3 (B1) · 747d8bd (B2) · 6067921 (B3) · 352097b (C) · a9a2618 (CHECK) · 9fb665e (desglose por empresa).

Detalles a recordar:
- Los .sql de fixes viven en supabase/fixes/ y se agregaron con git add -f (el dir puede estar en .gitignore) — confirmar siempre que quedan en origin.
- El overview de todos los países (useMetricasCampanaAdmin.fetchMetricasPais → vista v_metricas_campana_pais) se dejó como está: solo super_admin, que sí pasa la RLS.

## Pendiente / ideas
- (Producto, no código) Prompts de video sobre el software médico para mostrar a futuros clientes.
