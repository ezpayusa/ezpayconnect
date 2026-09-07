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

> **Números vivos (7-sep):** última migración aplicada **287** · próxima **288** · próximo errcode
> libre **PA030** · próxima probe libre **P649**. Se actualizan acá y sólo acá: tenerlos repetidos
> en cada sección fue justamente lo que los dejó contradiciéndose entre sí.

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
| filas | **708** |
| rojas | **13** — todas deuda AJENA; `P625` salió de la lista al cerrarse el punto 3 |
| resto | 695 |
| `b2_guard` | VERDE — `do_sin_handler` 156, `top_level_dml_ddl` 0, `cast_directo` 0 |
| centinela P000 | OK (687 veredictos, ninguno vacío) |

Probes nuevas del día, las 16 en verde: **P599–P601** (mig 281), **P602–P607** (mig 282),
**P608–P614** (mig 283). Más **P615–P630** del cierre del 6-sep (las 4 RPCs que estaban sin
cobertura), **P631–P636** (mig 284: privilegios sobre `perfiles`; P635/P636 ejercitan a `anon` contra
tablas dependientes), **P637–P638** (mig 285: PA028) y **P639–P648** (migs 286/287: las dos RPCs de
la pantalla de fichas). Próximo número libre: **P649**.

Las 13 rojas son **todas deuda ajena** —P163, P209, P222, P411, P414, P472, P473, P476, Pbuz×2,
Pqr×3—. El módulo comercial ya no aporta ninguna: **P625** era la única propia (doble checkout sin
guard) y salió de la lista cuando la mig 285 la cerró. Ya no se comparan a mano: `harness_run.py` tiene la lista `DEUDA` en código y falla si
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

### 3. ~~Endurecer check-in y checkout~~ — **CERRADO 6-sep (mig 285)**

Los dos huecos, vistos en rojo antes de cerrarlos:

- `checkin_visita_comercial` no exigía `estado = 'planificada'`: aceptaba check-in sobre una visita
  **cancelada** o **no_realizada**, que volvía a `en_curso` sin que nadie la reabriera. El único
  chequeo previo era `checkin_at IS NOT NULL` (PA025), que no dice nada del estado.
  → **PA028**, medido por **P637** (desde `cancelada`) y **P638** (desde `no_realizada`).
- `checkout_visita_comercial` no rechazaba un checkout previo: la segunda llamada pasaba y
  reescribía `checkout_at`. → **PA029**, medido por **P625**, que pasó de roja aceptada a exigir el
  rechazo.

`P625_co_DOBLE_checkout_doc` **salió de `DEUDA`** en `harness_run.py`: ya no es deuda tolerada, es
un guard real. El front mapea las dos en `erroresRpc.ts` (`recargar: 'visita'`, `reportar: false` —
son fichas viejas, no bugs nuestros).

### 4. ~~Pantalla de fichas de asesor (D12)~~ — **CERRADO 7-sep (migs 286/287 + front)**

`guardar_asesor_perfil` y `asignar_supervisor` ya tienen UI: `/admin-ezpay/pais/:paisId/asesores`,
**con entrada de navegación** desde el dashboard de país (a diferencia de prospectos y material, que
siguen huérfanas — punto 8).

Dos RPCs de lectura nuevas, las dos con gate por `WHERE ... COALESCE(...)` y **sin errcode**: sin
autoridad devuelven 0 filas, no 42501.

| mig | función | qué contesta | probes |
|---|---|---|---|
| **286** | `comercial_perfiles_sin_ficha(uuid)` | a quién le falta ficha en el país | P639–P643 |
| **287** | `comercial_supervisores_del_pais(uuid)` | candidatos válidos para `asignar_supervisor` | P644–P648 |

`comercial_supervisores_del_pais` cubre las tres condiciones del guard que se pueden anticipar —rol
(PA001), ficha activa (PA002), mismo país (PA003)—. **PA004 (dos niveles) no se anticipa**: depende
de a quién supervisa ya el candidato, así que el selector puede ofrecer uno que después sea
rechazado. Por eso la pantalla pinta ese rechazo **pegado a la fila** y no en un toast que se va.

**Un bug encontrado y cerrado en el mismo bloque:** `guardar_asesor_perfil` hace UPSERT y su
`ON CONFLICT DO UPDATE` pisa las nueve columnas con lo que venga en los parámetros, así que todo
campo que el formulario mandara y el select no precargara se guardaba **vacío** al editar. Medido
ejercitando las dos funciones: faltaba `bio`, y sólo esa. Lo vigila un **censo de simetría** en
`api.test.ts` que compara la igualdad de los dos conjuntos —molde del censo invertido de la mig 281
traído al front—, así que agregar un campo al formulario sin agregarlo al select se pone rojo solo y
nombra la columna.

Verificado en navegador contra la base real (Admin País QA de Guatemala): `asesores_perfil` en 200
con las 11 columnas incluida `bio` y sin `foto_path`/`foto_publica_path`, las tres RPC en 200, y el
fix de `bio` probado end-to-end (editar, guardar sin tocar nada, recargar, los valores siguen).

**Nuevo, sin dueño todavía: `fecha_ingreso` no tiene ninguna validación.** Se aceptó `2227-01-01`
sin chistar, ni en el formulario ni en `guardar_asesor_perfil`. Hoy no lo consume nada, pero las
comisiones incluyen bonos de actividad contados desde el ingreso, y una fecha absurda rompe ese
cálculo cuando se construya. El arreglo tiene dos mitades y las dos hacen falta: un `CHECK` en la
tabla (o un guard en la RPC) y un `max` en el input — el front solo no alcanza, porque la RPC es
llamable sin pasar por la pantalla.

### 5. Tarjeta pública del asesor (D11) — piezas 1 y 2 CERRADAS 7-sep

**Única superficie `anon` del módulo.** Token propio, bucket público separado del de evidencia, y
consentimiento **revocable**.

- **Pieza 1 — backend (mig 288, `96ebd09`).** Cuatro columnas en `asesores_perfil`, cuatro RPCs,
  PA030, probes P649–P661. `tarjeta_publica_por_token` la ejecuta **sólo `service_role`**.
- **Pieza 2 — superficie pública (`fcb9404` + `832cd56`).** Edge `tarjeta-asesor` + ruta `/t/:token`.
  Verificada en prod contra `med.ezpayconnect.com`: `text/html`, sin CSP, `og:url` con el dominio y
  el path correctos, vCard con su `text/vcard`, y **la revocación mata la URL** (apagada → 404,
  encendida → 200). 22 tests de deno.
  **La primera versión estaba rota y no se veía sin desplegar**: el gateway de Supabase reescribe el
  `text/html` a `text/plain` y Vercel no lo repara. Se arregló con un proxy propio en
  `api/tarjeta.ts` que corrige headers y no decide nada. La lección medida está en CLAUDE.md.
- **Pieza 3 — pendiente.** Bucket público para `foto_publica_path`. Hoy el campo viaja en el JSON de
  la RPC y **no se usa**: un `og:image` que 404ea es peor que no tenerlo.
- **Pieza 4 — pendiente.** Pantalla del asesor para encender/apagar la tarjeta y rotar el token.
  Hasta que exista, el consentimiento sólo se puede tocar por SQL.

### 6. Seed DEMO (D9/D10)

País DEMO propio y cuentas `*.demo` creadas por la vía canónica (`crear-empleado`), no sembradas a
mano.

### 7. Limpieza de datos QA en prod

- Jornada `db1ad4f2-6894-4452-a01c-7b8e315a6310` — asesor1, fecha 2026-09-05, **abierta sin cerrar**.
- Jornada `a4c9a69f-4364-43f4-9afd-22f2ec6a06fc` — asesor2, fecha 2026-09-04, **abierta sin cerrar**.
- Prospectos `QA CICLO 16:29` / `16:30`, `QA GEO cerca` / `lejos`, `QA ADJ sin checkin`.
- Visita `39866a82-20c2-4994-95d3-900034333ab7` (2026-09-08 15:15, planificada) — la creó Oscar
  verificando la agenda.
- **Fichas de asesor con datos de prueba** cargados al verificar la pantalla del punto 4:
  `QA-SUP-01` quedó con cargo `supervidor` (sic), territorio `centro`, bio `nada` y
  `fecha_ingreso 2227-01-01`. No estorban a nadie, pero son datos inventados en una tabla real.
- **`QA-ASE-01` tiene la TARJETA PÚBLICA ENCENDIDA** (`tarjeta_publica = true`) y datos de contacto
  inventados cargados por SQL el 7-sep para verificar la pieza 2: cargo `Asesor Comercial Senior`,
  territorio `Zona 10 y Zona 14, Ciudad de Guatemala`, teléfono `2378-4500`, celular
  `+502 5512-3456`. **Esta es la única fila del inventario QA que está publicada en internet**: el
  link `/t/<token>` responde a cualquiera que lo tenga. Al limpiar, apagarla es lo primero —
  `tarjeta_publica = false` la mata en el request siguiente, sin ventana.
- El inventario completo de cuentas y basura borrable está en la memoria de proyecto, no en el repo.

### 8. Higiene

- **`api/` no está en el `include` de NINGÚN tsconfig**, así que las funciones serverless de Vercel
  **nunca se typechequean** — ni la nueva `api/tarjeta.ts` ni las dos viejas `api/send-receta.ts` y
  `api/send-factura.ts`, que están vivas en prod. Medido 7-sep: `tsconfig.app.json` incluye `["src"]`
  y `tsconfig.node.json` incluye `["vite.config.ts"]`; no hay un tercero. O sea que el gate de
  `tsc -p tsconfig.app.json` que corremos en cada bloque **no mira ese directorio**, y Vercel tampoco
  typechequea al construir funciones. Las tres se verificaron a mano con una invocación suelta de
  `tsc` y salieron limpias, pero eso no es un gate: hay que meter `api` en un tsconfig (probablemente
  `tsconfig.node.json`, que ya tiene `types: ["node"]`) y ver qué baseline aparece antes de exigir 0.
- `COLS_JORNADA` trae `pais_id` y las dos columnas de precisión que **ninguna pantalla pinta**.
- Las rutas `/admin-ezpay/pais/:id/prospectos` y `/material` **no tienen entrada de navegación**: se
  llega sólo escribiendo la URL.
- `FormFechaHora` tiene `<label>` sin `htmlFor` — label huérfano para lectores de pantalla.
- **Ruido de red transversal — NO es del módulo comercial.** En una sola carga se ven ~6 requests
  repetidas a `perfiles?select=*` del propio usuario, y `notificaciones?select=*` haciendo polling,
  las dos con `select('*')`. Es el mismo patrón que la 277 corrigió en `visitas_comerciales` —una
  lista explícita de columnas en vez del asterisco— pero en otras dos tablas, y `perfiles` es
  justamente la que más datos personales tiene. Las repeticiones son un problema aparte del
  asterisco: hay que mirar quién dispara la consulta tantas veces antes de tocar el select.
  **Toca fuera del módulo comercial, así que no entra en este frente sin decisión propia.**

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
