# Estado del módulo comercial — 6 de septiembre de 2026

`main` = **`af61e4d18fd3910370c21bbf1e27caed4cefcd5f`** (`af61e4d`), sincronizada con `origin/main`
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
| filas | **669** |
| rojas | **13** — exactamente las 13 de deuda ajena, **ninguna fuera de esa lista** |
| resto | 656 |
| `b2_guard` | VERDE — `do_sin_handler` 156, `top_level_dml_ddl` 0, `cast_directo` 0 |
| centinela P000 | OK (668 veredictos, ninguno vacío) |

Probes nuevas del día, las 16 en verde: **P599–P601** (mig 281), **P602–P607** (mig 282),
**P608–P614** (mig 283). Próximo número libre: **P615**.

Las 13 rojas de deuda: P163, P209, P222, P411, P414, P472, P473, P476, Pbuz×2, Pqr×3. Se comparan
texto a texto en cada corrida para probar que no cambiaron.

---

## Lo que queda

> Nota: el pedido de este cierre remitía a "la lista del punto siguiente", que no llegó. Lo que
> sigue es lo acumulado y verificado durante la sesión. **Confirmar con Oscar antes de tomarlo como
> el backlog acordado.**

### Aprobado y pendiente de escribir

- **Mig 284 — grants de `anon` sobre `perfiles`.** `anon` tiene SELECT, INSERT, UPDATE, DELETE y
  TRUNCATE **de tabla entera** sobre la tabla con más datos personales del sistema. Hoy no es
  explotable —las cinco policies dependen de `auth.uid()`, que para anon es NULL— pero la única
  protección es la RLS. Misma clase que P222 (`anon ve farmacias — policy anon vestigial`).

### Deuda técnica del harness

- **Fixtures de jornada acoplados a datos vivos de prod.** Una jornada QA real abierta en prod puso
  en rojo a **P537, P547, P550 y P591** durante toda la tarde del 5-sep, y volvieron a verde solas
  al cambiar `CURRENT_DATE`. Causa: `abrir_jornada` **adopta** la jornada real del día en vez de
  sembrar una limpia. La más grave es **P550**, cuyo modo de falla fue `ROJO (PERMITIÓ …)` — una
  probe de seguridad que reporta permisividad falsa por contaminación de fixture es peor que una que
  falla, porque invita a "arreglar" una RPC que está bien.
- **5 probes no determinísticas** que sólo cambian un id entre corridas: P175, P62, P441, FX14, P515.
- P547 ya tiene anotada su cobertura parcial en el archivo ("la ventana temporal de PA024 no se
  verifica dentro de la transacción").

### Producto / decisiones sin tomar

- **El supervisor no tiene "mi jornada".** `/comercial/hoy` es la pantalla del asesor y ahora pide
  la jornada propia; un supervisor que entre verá la suya, que probablemente no exista. Antes veía
  *alguna* del equipo, por accidente. No es una regresión —era un bug mostrando datos ajenos como
  propios— pero si el supervisor debe poder abrir jornada, eso no está decidido.
- **La hora prefijada del `<input type="time">`** que Oscar reportó: medido, el componente arranca
  vacío al agendar y con el valor real al reprogramar; los 8 tests de comportamiento pasaron contra
  el código sin tocarlo. La hipótesis es el picker nativo de Chrome, que precarga la hora actual
  como punto de partida sin escribirla. Falta verificarlo por CDP en un navegador real.
- **`FormFechaHora` tiene `<label>` sin `htmlFor`** — label huérfano para lectores de pantalla.

### Datos QA vivos en prod, para limpiar

- Jornada `db1ad4f2-6894-4452-a01c-7b8e315a6310` (asesor1, fecha 2026-09-05) **abierta sin cerrar**.
- Prospectos `QA CICLO 16:29` / `16:30`, `QA GEO cerca` / `lejos`, `QA ADJ sin checkin`.
- Visita `39866a82-20c2-4994-95d3-900034333ab7` (2026-09-08 15:15, planificada) — la que Oscar creó
  verificando la agenda.
- El inventario completo de cuentas y basura borrable está en la memoria de proyecto, no en el repo.

### Residuos de cierres anteriores, sin tocar

- 3 funciones de trigger con EXECUTE para `anon`.
- El destino real de los 5 roles en `/sin-panel`.
- La cuenta `Fabio1@prueba`.

---

## Vercel

No verificable desde esta sesión: el CLI responde `The specified token is not valid`.
**Comparar en el dashboard contra `af61e4d`.**
