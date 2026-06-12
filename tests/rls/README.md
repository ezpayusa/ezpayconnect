# Tests de RLS — Plan de remediación de seguridad

Andamiaje para verificar, rol por rol, que cada usuario **solo accede a lo que
debe**. Es el medidor que acompaña el plan de remediación por fases.

## Archivos
- `run.sh` — mide la **visibilidad de lectura** por rol (solo SELECT, no muta).
  Con `WITH_WRITES=1` corre además las pruebas de escritura negativa.
- `probes_escritura.sql` — pruebas de **escritura negativa** (anon no inserta
  citas; médico no cancela/roba cita ajena vía RPC). Terminan en ROLLBACK.
- `EXPECTATIVAS.md` — matriz objetivo por rol/tabla + baseline ROJO actual
  (lectura y escritura).

## Cómo correrlo
```bash
bash tests/rls/run.sh                 # solo visibilidad de lectura (inofensivo)
WITH_WRITES=1 bash tests/rls/run.sh   # incluye pruebas de escritura negativa (ROLLBACK)
```
Requiere `npx supabase` logueado y el proyecto linkeado (usa `db query --linked`,
igual que las migraciones). El script:
1. Resuelve un uid representativo por cada rol real (`perfiles.rol`) + un
   paciente (`pacientes.auth_user_id`) + anon.
2. Para cada persona, simula su sesión (claims JWT + rol `authenticated`/`anon`)
   y cuenta cuántas filas ve en las tablas sensibles.
3. Imprime la visibilidad para compararla contra `EXPECTATIVAS.md`.

## Cómo se simula un rol (sin tocar datos)
```sql
select set_config('request.jwt.claims', '{"sub":"<uid>","role":"authenticated"}', true);
select set_config('role','authenticated', true);
select count(*) from historial_medico;   -- ahora corre con la RLS de ese usuario
```
`auth.uid()` lee el `sub` de los claims; al fijar `role=authenticated` se aplica
la RLS como ese usuario. Todo es transaccional y de solo lectura.

## Flujo de trabajo por fase
1. Antes de tocar políticas: correr `run.sh` → confirmar el **baseline ROJO**.
2. Aplicar la migración de la fase (en revisión / staging, nunca directo a prod
   sin confirmación).
3. Correr `run.sh` de nuevo → las celdas de esa fase deben pasar a **VERDE**.
4. Build limpio + flujos de QA → confirmar que no se rompió nada legítimo.

## Estado de esta entrega (FASE 0)
- Estos archivos y las migraciones `067`/`068` **NO se han aplicado** a la base.
- `run.sh` está listo para correr y capturar el baseline cuando se confirme.
- No se han reescrito todavía las ~25 políticas de roles (eso es Fase 6).

## Dependencias y orden de las migraciones de Fase 0
El migrador aplica en orden ascendente; el número refleja el orden de aplicación:
1. **`067_fase0_helpers_autorizacion.sql`** — crea el esquema **`private`** (no
   expuesto) y las funciones helper (`EXECUTE` solo `authenticated`). Usa objetos
   existentes ya verificados: `obtener_clinica_usuario(uuid)`, `perfiles`,
   `pacientes`, `medico_clinicas`. No crea ni altera políticas de negocio.
2. **`068_fase0_roles_catalogo.sql`** — crea el catálogo (TABLA) y su RLS propia;
   su política `roles_catalogo_admin` usa `private.tiene_rol()` (por eso va
   después de 067). **No** aplica todavía FK/CHECK sobre `perfiles.rol` (eso es
   Fase 6, para no bloquear escrituras hasta alinear el código).

## Verificación manual pendiente (Fase 0)
- Confirmar en Dashboard → Project Settings → API → **Exposed schemas** que el
  esquema `private` **NO** está listado (debe ser solo `public, graphql_public`),
  para que los helpers no sean invocables como RPC desde el cliente.
