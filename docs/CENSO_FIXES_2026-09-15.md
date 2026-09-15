# Censo de `supabase/fixes/` — 15 de septiembre de 2026

**Pregunta:** ¿qué de lo que corre en producción está definido SOLO en `supabase/fixes/` y no en
`supabase/migrations/`? O sea: si mañana se levanta una base limpia solo con las migraciones, ¿qué
le falta para ser prod?

**Por qué se hizo:** el diagnóstico del upload de Fase 4 encontró que la policy viva
`resultados_scoped_select` no estaba en ninguna migración — vivía en `supabase/fixes/fase4_01`. No
era drift fuera de git (los fixes están trackeados), pero sí significaba que `migrations/` no
reproduce prod.

## Método

- **19 archivos** en `supabase/fixes/`, los 19 trackeados en git.
- **Funciones:** `prosrc` vivo de prod comparado, con espacios normalizados, contra el cuerpo del
  fix y contra la ÚLTIMA migración que define esa misma función.
- **Policies:** recreadas como policies temporales dentro de `BEGIN`/`ROLLBACK` y comparadas
  normalizadas (`pg_get_expr`) contra las vivas. Post-rollback: 0 temporales restantes.
- **Columnas, defaults, constraints, índices, datos:** verificados en prod contra
  `information_schema.columns`, `pg_constraint`, `pg_indexes` y conteos. Los 10 índices, además,
  columna por columna. En migraciones se buscó **sentencia por sentencia** (no línea por línea),
  para no perder definiciones en varias líneas o dentro de un `CREATE TABLE`.
- "Aplicado en prod" se verificó contra la base, no por el nombre del archivo.

## Tabla

| fix | objeto | ¿mismo texto en `migrations/`? | ¿vivo en prod? |
|---|---|---|---|
| `aprobar_solicitud_campana_dueno_01` | fn `aprobar_solicitud_campana` | no — la vigente es la de **270** | **superado**: prod = 270 ≠ fix |
| `campanas_pub_check_dueno_01` | CHECK `chk_campana_dueno` | no | sí |
| `campanas_pub_empresa_backfill_01` | cols `empresa_id`, `solicitud_campana_id` + índice + backfill | no | sí (índice exacto, backfill 14/14) |
| `contexto_ia_paciente_soap_hist_01` | fn `contexto_ia_paciente` | **no** — 174 tiene otra versión | sí, fix = prod |
| `expediente_notas_nota_default_01` | DEFAULT `''` en `expediente_notas.nota` | no | sí |
| `fase3_01_seed_roles_laboratorio` | dato: 3 roles + 9 permisos de lab | no | sí (3 / 9) |
| `fase4_01_liberacion_paciente_schema_policies` | 3 cols `liberado_*` + policies `resultados_scoped_select` y "Paciente ve sus examenes" | **no** — 074 y 005 tienen las originales | sí, las dos policies = fix |
| `fase4_02_liberacion_paciente_rpcs` | fn `liberar_examen_al_paciente`, `liberar_orden_al_paciente`, `paciente_examenes` | no | sí, = fix |
| ″ | fn `notificar_resultado_examen` | no — la vigente es la de **271** | **superado**: prod = 271 |
| `fix_normalizar_archivo_url_publico` | dato: URLs públicas → path | no | efecto presente (0 URLs viejas) |
| `fix_resultados_select_readback` | policy `resultados_scoped_select` | no | **superado por otro fix** (`fase4_01`) |
| `foto_calendario_clinica_01` | fn `listar_medicos_clinica` | **no** — 232 tiene otra versión | sí, fix = prod |
| `foto_medico_01` | bucket `fotos-medicos` + 4 policies + fn `guardar_foto_medico` | no (289 solo lo nombra en comentarios) | sí, las 4 policies = fix |
| `indices_piloto_01` | 10 índices | no | sí, 10/10 con columnas idénticas |
| `metricas_campana_pais_desglose_02` | fn `metricas_campana_pais` | no — la vigente es la de **266** | **superado**: prod = 266 |
| `metricas_campana_pais_rpc_01` | fn `metricas_campana_pais` | no — la vigente es la de **266** | **superado**: prod = 266 |
| `metricas_campana_proveedor_rpc_01` | fn `metricas_campana_proveedor` | no | sí, = fix |
| `mis_impresiones_campana_rpc_01` | fn `mis_impresiones_campana_recientes` | no | sí, = fix |
| `planes_lab_farmacia_01` | seed de capacidades + fn `otorgar_capacidad_empresa` + backfill de empresas | no | sí (2 capacidades, 0 empresas sin la suya), fn = fix |
| `receta_items_fk_recetas_01` | FK `receta_items_receta_id_fkey` | **sí, en 001** (`REFERENCES recetas(id) ON DELETE CASCADE`) | sí |

## Conteos

- **13 fixes son la ÚNICA definición de algo vivo en prod:** `campanas_pub_check_dueno_01`,
  `campanas_pub_empresa_backfill_01`, `contexto_ia_paciente_soap_hist_01`,
  `expediente_notas_nota_default_01`, `fase3_01_seed_roles_laboratorio`, `fase4_01`,
  `fase4_02` (por 3 de sus 4 funciones), `foto_calendario_clinica_01`, `foto_medico_01`,
  `indices_piloto_01`, `metricas_campana_proveedor_rpc_01`, `mis_impresiones_campana_rpc_01`,
  `planes_lab_farmacia_01`.
- **4 son redundantes con una migración:** `aprobar_solicitud_campana_dueno_01` (270),
  `metricas_campana_pais_rpc_01` (266), `metricas_campana_pais_desglose_02` (266),
  `receta_items_fk_recetas_01` (001).
- Los 2 restantes no entran en ninguno de los dos conteos: `fix_normalizar_archivo_url_publico`
  (transformación de datos ya hecha) y `fix_resultados_select_readback` (superado por otro fix, no
  por una migración). 13 + 4 + 2 = 19.

## Salvedades

1. **"Vivo en prod" en los fixes de DATOS** significa que el estado está presente, no que ese archivo
   lo haya producido.
2. **Este censo solo mide los fixes.** No mide cuánto drift hay además entre `migrations/` y prod por
   otras vías. El hallazgo de abajo prueba que ese drift existe.

## Hallazgo: la `receta_items` de prod no salió de la 001

`001_inicial.sql:173` define:

```sql
receta_id INTEGER NOT NULL REFERENCES recetas(id) ON DELETE CASCADE,
```

que Postgres nombra `receta_items_receta_id_fkey`. Pero el comentario de
`receta_items_fk_recetas_01.sql` dice que en prod la columna era **`bigint`** y **existía sin
constraint** — el embed PostgREST `recetas(...,receta_items(...))` fallaba con "Could not find a
relationship". Ninguna migración dropea esa FK. Si la tabla de prod hubiera salido de la 001, la
columna sería `integer` y la FK existiría desde el primer día.

Conclusión: la `receta_items` de producción se creó por otra vía. Una base limpia **sí** tendría la
FK (por la 001), pero con `receta_id integer`, distinto de prod.

## Si mañana se levanta una base limpia solo con `supabase/migrations/`

1. **Fase 4 no funcionaría.** Faltarían las columnas `liberado_*`, las 2 policies con el gate de
   liberación y 3 RPCs. La policy de SELECT de `resultados-examenes` quedaría la de la 074, sin la
   rama de read-back del prefijo: el upload del lab volvería a fallar con "new row violates
   row-level security policy".
2. **Faltarían 5 funciones y 2 quedarían en versión vieja.** Faltarían
   `metricas_campana_proveedor`, `mis_impresiones_campana_recientes`, `otorgar_capacidad_empresa` y
   `guardar_foto_medico` (además de las 3 de Fase 4 ya contadas). `contexto_ia_paciente` y
   `listar_medicos_clinica` quedarían con la versión de las migraciones 174 y 232. Faltarían también
   el bucket `fotos-medicos` con sus 4 policies, los 10 índices y los seeds de roles y capacidades
   del lab.
3. **Algunas cosas se romperían al usarse, aunque las migraciones apliquen bien.** Faltarían
   `campanas_publicitarias.empresa_id` y `solicitud_campana_id` con su CHECK:
   `aprobar_solicitud_campana` (270, plpgsql) se crearía igual —plpgsql no valida columnas al
   `CREATE`— pero fallaría al aprobar la primera campaña. Y sin el `DEFAULT ''` de
   `expediente_notas.nota`, el INSERT del SOAP de `guardarNotaSOAP` fallaría por `NOT NULL`, con lo
   que "Finalizar" quedaría bloqueado por el gate PE001.

## Qué NO se hizo

No se propuso plan de reconciliación. Este documento es el inventario; la decisión de pasar los 13
fixes a migraciones numeradas (y cómo) queda para otro bloque.
