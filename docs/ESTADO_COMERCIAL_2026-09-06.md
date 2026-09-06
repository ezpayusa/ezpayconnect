# Estado del módulo comercial — 6 de septiembre de 2026

`main` = **`96abc11`** (más este commit de docs), sincronizada con `origin/main`
en las dos direcciones. Nada sin commitear salvo los untracked de siempre (manuales PDF y sus
scripts, `AUDITORIA-PROFUNDA-2026-07-05.md`, `CODEX_VALIDACION_AUDITORIA.md`, `tmp/`).

Verificado contra la base viva: **los 15 objetos de las migraciones 279–283 están en prod y los 5
archivos están trackeados en git. Cero drift.**

---

## Migraciones

| mig | qué hizo |
|---|---|
| **279** | `borrar_material_comercial(uuid)` + policy DELETE de storage para el bucket de material. Cierra el último pedazo de backend sin superficie del material comercial. |
| **280** | Agenda de visitas: columnas `hora_planificada`, `planificada_por` y `cancelacion_motivo`; `planificar_visita` pasa a `(uuid,date,time)`; nuevas `reprogramar_visita_comercial` y `cancelar_visita_comercial`; `abrir_jornada` adopta las visitas huérfanas del día. Errcodes PA026 y PA027. |
| **281** | GRANT por columna de las 3 columnas que la 280 agregó y dejó sin privilegio. Ver *Hallazgo 1*. |
| **282** | `visitas_com_una_por_dia` deja de contar las canceladas: pasa de CONSTRAINT UNIQUE a **índice único parcial** `WHERE estado <> 'cancelada'`. Ver *Hallazgo 2*. |
| **283** | `comercial_asesores_visibles()` — RPC SECURITY DEFINER que devuelve 5 columnas (`id`, `codigo_asesor`, `nombre_completo`, `activo`, `supervisor_id`) con el gate copiado literal de la policy `asesores_perfil_select`. Ver *Hallazgo 3*. |

**Próximo errcode libre: PA028.** Próxima migración: **284** (ya aprobada, no escrita — ver pendientes).

---

## Los tres hallazgos del día

Los tres los encontró Oscar verificando en un navegador real. Ninguno lo habría encontrado un test
del repo tal como estaba, y por eso los tres se cerraron con probes que ahora los vigilan.

### 1. 403 en toda lectura de visitas, por columnas sin GRANT (mig 281)

La 280 agregó tres columnas a `visitas_comerciales`. Desde la 277 esa tabla **no** tiene SELECT de
tabla para `authenticated` — tiene SELECT **columna por columna**, para dejar afuera las cuatro de
coordenada. Las tres columnas nuevas no entraron en ningún GRANT, y como el front pide una lista
explícita de columnas que ahora las incluye, se rompió **toda** la lectura de visitas con 403.

> **Un `ALTER TABLE ADD COLUMN` sobre una tabla con grants por columna es un cambio de privilegios
> disfrazado de cambio de esquema.** Nada lo estaba mirando.

Lo que lo vigila ahora: **P600**, un censo invertido — para cada columna de `visitas_comerciales` y
`jornadas_comerciales` que no sea de coordenada, exige que `authenticated` la pueda leer, y falla
nombrando la que falte. Es lo que hace que el próximo `ADD COLUMN` se ponga rojo solo. **P601** es
su control positivo por el otro lado: las 8 columnas de coordenada siguen ilegibles.

Detalle técnico que importa: P600/P601 usan `has_column_privilege()` y no
`information_schema.column_privileges` (que es lo que usa P574), porque el segundo sólo lista los
grants por columna **explícitos** y dejaría pasar invisible un `GRANT SELECT` de tabla entera.

### 2. El UNIQUE por día contaba las canceladas (mig 282)

`visitas_com_una_por_dia` era UNIQUE total sobre `(prospecto_id, asesor_id, fecha_planificada)`, así
que **cancelar una visita no liberaba el día**: el par (prospecto, día) quedaba quemado para siempre
y re-agendar devolvía 23505 / 409. Cancelar y re-agendar es el flujo normal — es para lo que existe
`cancelar_visita_comercial`, que la 280 agregó sin notar que el UNIQUE la dejaba sin salida.

Dos cosas que el arreglo no podía ser un `DROP INDEX`:

1. El índice **colgaba de una CONSTRAINT** (la 273 lo declaró inline en el `CREATE TABLE`), así que
   `DROP INDEX` falla con `2BP01`. Hay que soltar la constraint.
2. En Postgres una constraint UNIQUE **no puede ser parcial**. El reemplazo es, necesariamente, un
   índice suelto y no una constraint. Se conservó el nombre para que el 23505 siga diciendo lo mismo.

El predicado es `<> 'cancelada'` y **no** una lista de estados vivos: `realizada` y `no_realizada`
son hechos ocurridos y siguen bloqueando el día. Sólo la cancelación libera la reserva (**P604**).

Cubre los dos caminos: **P602** el `INSERT` (agendar) y **P607** el `UPDATE` (reprogramar *hacia* un
día que tiene una cancelada), que es el que se habría quedado vivo si el arreglo hubiera sido más
angosto.

### 3. El supervisor veía "sin asesor" en su propia cartera (mig 283)

`perfiles` tiene RLS activa y **una sola** policy de SELECT útil: `auth.uid() = id`. Ningún rol
comercial aparece en ninguna. Por eso todo embed `asesor:perfiles(...)` devolvía `NULL` para
cualquier asesor que no fuera uno mismo, y la cartera del supervisor mostraba "sin asesor" en los
cinco prospectos — con `asesor_id` poblado en las cinco filas.

Descartadas con evidencia las otras dos hipótesis: el select **sí** pedía el nombre, el front **sí**
lo pintaba, y `authenticated` **sí** tiene privilegio sobre `perfiles.nombre_completo`. Control
positivo: el mismo JOIN sobre los mismos datos, mirado por el propio asesor, devuelve 5 de 5.

**No se abrió `perfiles` con una policy nueva.** La tabla no tiene privilegio por columna —
`authenticated` tiene SELECT de TABLA — así que una policy habría expuesto las 16 columnas de golpe
(email, teléfono, dirección del consultorio, lat/lng, avatar) a cambio de un solo campo. La RPC
devuelve 5 columnas y ninguna sensible. **P614** fija que `perfiles` sigue cerrada, por catálogo y
por camino real.

Advertencia escrita en la cabecera de la 283 y que hay que leer antes de tocar su gate: `perfiles` y
`asesores_perfil` son de `postgres`, que tiene `rolbypassrls = true`, y ninguna tiene FORCE ROW
LEVEL SECURITY. Una función SECURITY DEFINER con ese owner **lee las dos tablas sin RLS**: acá no
hay una policy detrás haciendo de red, y **el `WHERE` es la única barrera**. Por eso el gate va
envuelto entero en `COALESCE(..., false)`.

---

## Front

- **Agenda completa**: agendar a futuro con hora opcional, próximas visitas, reprogramar y cancelar.
- **`COLS_VISITA` / `COLS_VISITA_GEO`**: las coordenadas del prospecto viajan sólo a la ficha de la
  visita, que es la pantalla del check-in y el único lugar que las usa — y las usa como booleano
  (`lat == null`), no para calcular: la distancia la calcula la RPC y llega en `checkin_distancia_m`.
- **Ninguna consulta de `src/comercial` nombra `perfiles`.** Se eliminaron los cuatro embeds; el de
  `jornadasDelDia` no lo consumía ninguna pantalla y se fue sin reemplazo.
- **"sin asesor", "asesor no visible" y el nombre real dejan de ser el mismo texto.** Que las tres
  situaciones colapsaran en una es lo que hizo que un bug de RLS se leyera durante semanas como un
  dato faltante. `nombreAsesor()` las separa y hay test que lo fija.
- **`jornadaDeHoy` filtra por `asesor_id`** (bug latente). Consultaba por fecha con `maybeSingle()`
  y sin filtrar: al asesor le andaba de casualidad —la RLS le muestra una sola jornada— pero al
  supervisor le muestra las de **todo su equipo**, y con dos jornadas abiertas el mismo día revienta.
  No se veía porque en QA hay un solo asesor con jornada. Ese `.eq` **no** es un gate de
  pertenencia: es "la mía" vs "las del equipo", dos preguntas distintas.
- **El selector de asesor del panel de país filtra por el país de la URL**, y dice *"No hay asesores
  activos en este país"* en vez de quedar mudo.
- Los tres `select('*')` que quedaban (`prospecto_contactos`, `reportes_visita`, `visita_adjuntos`)
  pasaron a columnas explícitas.

**128 tests en 8 archivos**, todos verdes. `tsc -p tsconfig.app.json` en **82** (baseline; los 7 de
`admin-ezpay` son preexistentes y no crecieron). `vite build` verde.

---

## Harness

| | |
|---|---|
| filas | **688** |
| rojas | **14** — todas en la lista de deuda que el runner sostiene en codigo |
| resto | 674 |
| `b2_guard` | VERDE — `do_sin_handler` 156, `top_level_dml_ddl` 0, `cast_directo` 0 |
| centinela P000 | OK (687 veredictos, ninguno vacío) |

Probes nuevas del día, las 16 en verde: **P599–P601** (mig 281), **P602–P607** (mig 282),
**P608–P614** (mig 283). Más **P615–P630** del cierre del 6-sep (las 4 RPCs que estaban sin
cobertura). Próximo número libre: **P631**.

Las 14 rojas: las 13 de deuda ajena —P163, P209, P222, P411, P414, P472, P473, P476, Pbuz×2,
Pqr×3— más **P625**, que es deuda PROPIA del módulo (doble checkout sin guard, punto 3 del
backlog). Ya no se comparan a mano: `harness_run.py` tiene la lista `DEUDA` en código y falla si
aparece una roja fuera de ella **o** si una de la lista sale verde.

---

## Lo que queda — backlog acordado

### 1. CERRADO 6-sep (`96abc11`)

Probes **P615–P630** de las cuatro RPCs que estaban sin cobertura (`coordenadas_visita`,
`cerrar_jornada`, `checkout_visita_comercial`, `config_visitas_efectiva`), limpieza de jornadas QA,
guarda anti-NULL en P547–P550, runner con clasificación de rojas y lista de deuda, `--output json`
explícito y telemetría del CLI apagada en el subproceso.

### 2. Mig 284 — revocar a `anon` sobre `perfiles`

Revocar **INSERT, UPDATE, DELETE y TRUNCATE**. `TRUNCATE` es el que urge: **no pasa por RLS**, así
que hoy la única barrera contra vaciar la tabla con más datos personales del sistema es que nadie lo
intente. INSERT/UPDATE/DELETE sí los tapa la RLS —las cinco policies dependen de `auth.uid()`, NULL
para anon— pero son grants vestigiales. Misma clase que P222 (`anon ve farmacias`).

**El SELECT de `anon` se mide ANTES de tocarlo**: hay superficies públicas que podrían depender de
él, y revocarlo a ciegas es cambiar el comportamiento sin saber de qué.

### 3. Endurecer check-in y checkout

- `checkin_visita_comercial` **no exige `estado = 'planificada'`**: acepta hacer check-in sobre una
  visita **cancelada**.
- `checkout_visita_comercial` **no rechaza un checkout previo**: la segunda llamada pasa y reescribe
  un hecho. **P625 está ROJO en la lista de `DEUDA`** exactamente por esto.

**Al arreglarlo hay que sacar `P625_co_DOBLE_checkout_doc` de `DEUDA` en `harness_run.py`** — si no,
el runner falla con *"deuda que salio VERDE"*, que es el aviso funcionando como corresponde.

### 4. Pantalla de fichas de asesor (D12) — ANTES del seed

`guardar_asesor_perfil` y `asignar_supervisor` existen y **no tienen UI**. Va antes del seed porque
sin ella las fichas del seed habría que sembrarlas a mano.

### 5. Tarjeta pública del asesor (D11)

**Única superficie `anon` del módulo.** Token propio, bucket público separado del de evidencia, y
consentimiento **revocable**.

### 6. Seed DEMO (D9/D10)

País DEMO propio y cuentas `*.demo` creadas por la vía canónica (`crear-empleado`), no sembradas a
mano.

### 7. Limpieza de datos QA en prod

- Jornada `db1ad4f2-6894-4452-a01c-7b8e315a6310` — asesor1, fecha 2026-09-05, **abierta sin cerrar**.
- Jornada `a4c9a69f-4364-43f4-9afd-22f2ec6a06fc` — asesor2, fecha 2026-09-04, **abierta sin cerrar**.
- Prospectos `QA CICLO 16:29` / `16:30`, `QA GEO cerca` / `lejos`, `QA ADJ sin checkin`.
- Visita `39866a82-20c2-4994-95d3-900034333ab7` (2026-09-08 15:15, planificada) — la creó Oscar
  verificando la agenda.
- El inventario completo de cuentas y basura borrable está en la memoria de proyecto, no en el repo.

### 8. Higiene

- `COLS_JORNADA` trae `pais_id` y las dos columnas de precisión que **ninguna pantalla pinta**.
- Las rutas `/admin-ezpay/pais/:id/prospectos` y `/material` **no tienen entrada de navegación**: se
  llega sólo escribiendo la URL.
- `FormFechaHora` tiene `<label>` sin `htmlFor` — label huérfano para lectores de pantalla.

### Decisión abierta

**¿El supervisor puede abrir su propia jornada?** `/comercial/hoy` es la pantalla del asesor y desde
`af61e4d` pide la jornada propia; un supervisor que entre verá la suya, que probablemente no exista.
Antes veía *alguna* del equipo, por accidente — no es una regresión, era un bug mostrando datos
ajenos como propios. Pero si el supervisor debe poder abrir jornada, no está decidido.

### Deuda técnica del harness (contexto de los puntos 1 y 3)

- **CERRADO 6-sep.** Los fixtures de jornada estaban acoplados a datos vivos de prod: una jornada
  QA real abierta puso en rojo a **P537, P547, P550 y P591** toda la tarde del 5-sep, y volvieron a
  verde solas al cambiar `CURRENT_DATE`.
  El mecanismo real: `abrir_jornada` **no adopta jornadas** — lanza **PA020** si existe *cualquier*
  jornada del asesor con `fecha = CURRENT_DATE`, abierta o cerrada, porque su `EXISTS` **no mira
  `fin_at`**. Lo que sí adopta son las **visitas huérfanas planificadas** del día.
  La cadena fue: jornada real → P537 recibe PA020 → `vj_jornada` queda vacío → el fixture no publica
  `vj_jornada_inicio` → P550 arma su `p_cliente_at` como `NULL - 1 second` = NULL → un check-in con
  `p_cliente_at` NULL **no es diferido** y PA024 no tiene por qué rechazarlo → `ROJO (PERMITIÓ …)`.
  Una probe de seguridad que reporta permisividad falsa por contaminación de fixture es peor que una
  que falla, porque invita a "arreglar" una RPC que está bien.
  Cerrado con dos defensas: la limpieza de jornadas QA (que la causa no ocurra) y la guarda
  anti-NULL de P547–P550 (que si vuelve a ocurrir digan `N/A`, no `PERMITIÓ`).
- **5 probes no determinísticas** que sólo cambian un id entre corridas: P175, P62, P441, FX14, P515.
  Verificado sobre 88 corridas completas: ninguna empezó jamás con `ROJO`/`FALLO`, por eso no están
  en la lista de deuda del runner.
- P547 **sí** verifica la ventana temporal de PA024: el fixture retrasa `inicio_at` 3 horas para que
  la ventana exista dentro de la transacción, donde `now()` está congelado. El residual real es el
  de P550 entre 00:00 y 03:00, por el clamp al día, y ya está escrito en la propia probe.

### Sin dueño en el backlog, sin perder

- **La hora prefijada del `<input type="time">`** que Oscar reportó: medido, el componente arranca
  vacío al agendar y con el valor real al reprogramar; los 8 tests de comportamiento pasaron contra
  el código sin tocarlo. La hipótesis es el picker nativo de Chrome, que precarga la hora actual
  como punto de partida sin escribirla. Falta verificarlo por CDP en un navegador real.

### Residuos de cierres anteriores, sin tocar

- 3 funciones de trigger con EXECUTE para `anon`.
- El destino real de los 5 roles en `/sin-panel`.
- La cuenta `Fabio1@prueba`.

---

## Vercel

No verificable desde esta sesión: el CLI responde `The specified token is not valid`.
**Comparar en el dashboard contra `af61e4d`.** Los commits posteriores son `tests/rls` y docs; el
front desplegado no cambió.
