#!/usr/bin/env bash
# ============================================================
# FASE 0 · Andamiaje de tests de RLS (SOLO LECTURA)
# ------------------------------------------------------------
# Simula la sesión de un usuario por cada rol (vía claims JWT) y mide QUÉ
# FILAS PUEDE VER en las tablas sensibles. NO muta datos: solo SELECT count(*)
# bajo el rol `authenticated` con el `sub` del usuario simulado.
#
# Patrón de simulación (verificado): dentro de una misma invocación, el
# Management API envuelve el archivo en una transacción, así que
# set_config(..., true) persiste entre statements.
#
#   select set_config('request.jwt.claims', '{"sub":"<uid>","role":"authenticated"}', true);
#   select set_config('role','authenticated', true);
#   select ...   -- ahora corre como ese usuario, con RLS aplicada
#
# Uso:   bash tests/rls/run.sh
# Requiere: npx supabase CLI logueado y proyecto linkeado (db query --linked).
#
# Este script NO aplica cambios. Es el medidor para comparar el baseline ROJO
# (hoy) contra el estado VERDE esperado tras cada fase (ver EXPECTATIVAS.md).
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

# Ejecutor SQL. Verificado con supabase CLI 2.100.1 (subcomando `db query` existe).
# Fallback portable si en otra máquina no estuviera: reemplazar por psql, p.ej.
#   run_sql() { psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$1"; }
# (con la connection string del proyecto en $SUPABASE_DB_URL).
run_sql() { npx supabase db query --linked -f "$1" 2>/dev/null | grep -vE 'Connecting|Initial|Skipping|docker'; }

tmp() { mktemp /tmp/rls_XXXX.sql; }

# --- 1. Resolver un uid representativo por rol (y un paciente, y anon) ---
F=$(tmp)
cat > "$F" <<'SQL'
select 'persona' k,
  json_build_object(
    'super_admin',  (select id from perfiles where rol='super_admin' limit 1),
    'admin_clinica',(select id from perfiles where rol='admin_clinica' limit 1),
    'gerente',      (select id from perfiles where rol='gerente' limit 1),
    'medico',       (select id from perfiles where rol='medico' limit 1),
    'soporte',      (select id from perfiles where rol='soporte' limit 1),
    'vendedor',     (select id from perfiles where rol='vendedor' limit 1),
    'cliente',      (select id from perfiles where rol='cliente' limit 1),
    'paciente',     (select auth_user_id from pacientes where auth_user_id is not null limit 1)
  ) v;
SQL
echo "== Resolviendo personas (uid por rol) =="
PERSONAS=$(run_sql "$F")
echo "$PERSONAS"
rm -f "$F"

# Helper: extrae el uid de una persona del JSON anterior
uid_de() { echo "$PERSONAS" | grep -oE "\"$1\": *\"[0-9a-f-]+\"" | grep -oE '[0-9a-f]{8}-[0-9a-f-]+' | head -1; }

# Tablas sensibles a medir (visibilidad = nº de filas que el usuario puede leer)
SNAPSHOT=$(cat <<'EOSQL'
select ord, caso, val from (
  select 1  ord,'citas'                  caso,(select count(*) from citas) val
  union all select 2 ,'historial_medico',     (select count(*) from historial_medico)
  union all select 3 ,'recetas',              (select count(*) from recetas)
  union all select 4 ,'recetas_avanzadas',    (select count(*) from recetas_avanzadas)
  union all select 5 ,'receta_items',         (select count(*) from receta_items)
  union all select 6 ,'dispensaciones',       (select count(*) from dispensaciones)
  union all select 7 ,'examenes',             (select count(*) from examenes)
  union all select 8 ,'pacientes',            (select count(*) from pacientes)
  union all select 9 ,'expediente_notas',     (select count(*) from expediente_notas)
  union all select 10,'signos_vitales',       (select count(*) from signos_vitales)
  union all select 11,'medicos',              (select count(*) from medicos)
  union all select 12,'cuentas_bancarias_pais',(select count(*) from cuentas_bancarias_pais)
  union all select 13,'invitaciones_clinica', (select count(*) from invitaciones_clinica)
  union all select 14,'invitaciones_medico',  (select count(*) from invitaciones_medico)
) t order by ord;
EOSQL
)

# --- 2. Snapshot por persona ---
medir() {
  local rol="$1" uid="$2"
  echo ""
  echo "==================== ROL: $rol  (uid=${uid:-<anon>}) ===================="
  local F; F=$(tmp)
  if [ -n "$uid" ]; then
    {
      echo "select set_config('request.jwt.claims', '{\"sub\":\"$uid\",\"role\":\"authenticated\"}', true);"
      echo "select set_config('role','authenticated', true);"
      echo "$SNAPSHOT"
    } > "$F"
  else
    # anon: sin claims, rol anon
    {
      echo "select set_config('role','anon', true);"
      echo "$SNAPSHOT"
    } > "$F"
  fi
  run_sql "$F" | grep -E '"caso"|"val"' | paste - - | sed -E 's/.*"caso": "([^"]+)".*"val": ([0-9]+).*/  \1 = \2/'
  rm -f "$F"
}

for ROL in super_admin admin_clinica gerente medico soporte vendedor cliente paciente; do
  medir "$ROL" "$(uid_de "$ROL")"
done
medir "anon" ""

# --- 3. Pruebas de ESCRITURA NEGATIVA (opt-in: WITH_WRITES=1) ---
# Usan ROLLBACK, nunca persisten. Se dejan opt-in para que el snapshot de
# lectura sea 100% inofensivo por defecto.
if [ "${WITH_WRITES:-0}" = "1" ]; then
  echo ""
  echo "==================== PRUEBAS DE ESCRITURA NEGATIVA (ROLLBACK) ===================="
  run_sql tests/rls/probes_escritura.sql \
    | grep -E '"probe"|"verdict"|"esperado_post_fix"' \
    | paste - - - \
    | sed -E 's/.*"probe": "([^"]+)".*"verdict": "([^"]*)".*"esperado_post_fix": "([^"]*)".*/  \1\n     hoy: \2\n     objetivo: \3/'
else
  echo ""
  echo "== (Pruebas de escritura negativa desactivadas. Para correrlas: WITH_WRITES=1 bash tests/rls/run.sh) =="
  echo "== Son seguras: cada una termina en ROLLBACK y no persiste nada. =="
fi

echo ""
echo "== Listo. Compara estos números contra tests/rls/EXPECTATIVAS.md =="
echo "== ROJO = el rol ve/escribe más de lo que debería. VERDE = solo lo suyo. =="
