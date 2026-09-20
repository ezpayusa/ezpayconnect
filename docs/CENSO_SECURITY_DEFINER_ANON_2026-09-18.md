# Censo SECURITY DEFINER ejecutable por `anon`

Recon de producción enlazada. Fuente: `pg_proc`, `pg_get_functiondef`, ACL efectivo y grep de call-sites. Sin cambios de producto.

| Firma | PUBLIC EXECUTE | Origen de anon EXECUTE | `auth.uid()` en todas las ramas | Grupo | Justificación |
|---|---:|---|---|---|---|
| `abrir_canal_administracion()` | Sí | Heredado de PUBLIC | Sí | A | Empresa/rol salen de `auth.uid()`; sin cuenta activa lanza `No autorizado`. |
| `abrir_canal_equipo(uuid)` | Sí | Heredado de PUBLIC | Sí | A | Empresa caller se deriva de `auth.uid()` y el gate de equipo falla sin ella. |
| `abrir_directo(uuid)` | Sí | Heredado de PUBLIC | Sí | A | `v_empresa` se deriva de `auth.uid()` y NULL lanza `No autorizado`. |
| `actualizar_estado_cita(bigint,text)` | No | Explícito a anon | Sí | A | El UPDATE exige médico, paciente, admin de clínica o super_admin ligado a `auth.uid()`. |
| `admin_clinica_de_medico(uuid)` | Sí | Heredado de PUBLIC | Sí | A | Los dos EXISTS dependen de `auth.uid()`; anon devuelve false. |
| `afiliaciones_de_clinica()` | Sí | Heredado de PUBLIC | Sí | A | `mi_clinica_id()` deriva identidad; anon no obtiene filas. |
| `afiliaciones_laboratorio()` | Sí | Heredado de PUBLIC | Sí | A | `mi_empresa_proveedor()` deriva identidad; anon no obtiene filas. |
| `asignar_medico_cita(bigint,uuid)` | No | Explícito a anon | Sí | A | Guard de admin de clínica/super_admin antes del UPDATE. |
| `asignar_visitador_equipo(uuid,uuid)` | Sí | Heredado de PUBLIC | Sí | A | Rol y empresa caller salen de `auth.uid()`; anon cae en no autorizado. |
| `auto_configurar_planes_publicidad()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger; no es invocable como RPC por un caller anon. |
| `cambiar_auditoria_chat(uuid,boolean)` | Sí | Heredado de PUBLIC | Sí | A | Rol admin y empresa caller se derivan de `auth.uid()` antes del UPDATE. |
| `cambiar_estado_miembro_proveedor(uuid,boolean)` | Sí | Heredado de PUBLIC | Sí | A | El rol admin caller se deriva de `auth.uid()` antes del UPDATE. |
| `cambiar_rol_proveedor(uuid,text)` | Sí | Heredado de PUBLIC | Sí | A | Empresa y rol caller se derivan de `auth.uid()` antes del UPDATE. |
| `cancelar_cita_paciente(integer,text)` | Sí | Heredado de PUBLIC | Sí | A | El UPDATE exige `pacientes.auth_user_id = auth.uid()`; anon no retorna ni modifica filas. |
| `consultar_reveal_log(bigint,text,integer)` | No | Explícito a anon | Sí | A | Gate fail-closed `private.tiene_rol(['super_admin'])` antes de la lectura. |
| `contactos_chat()` | Sí | Heredado de PUBLIC | Sí | A | Empresa activa se resuelve por `cp.id = auth.uid()`; NULL retorna vacío. |
| `crear_cita(bigint,uuid,uuid,date,time,time,text,text,text,uuid)` | No | Explícito a anon | Sí | A | Las cuatro alternativas de autorización se atan a `auth.uid()`/roles derivados. |
| `destinatarios_conversacion(uuid)` | Sí | Heredado de PUBLIC | Sí | A | Primera rama `IF NOT es_miembro_conversacion(...) THEN RETURN`; helper depende del caller. |
| `detalle_entrega_delivery(bigint)` | No | Explícito a anon | Sí | A | Permiso y visibilidad; la fila exige `delivery_id = auth.uid()`. |
| `enviar_mensaje_chat(uuid,text)` | Sí | Heredado de PUBLIC | Sí | A | Exige `es_miembro_conversacion`; inserta autor/lectura con `auth.uid()`. |
| `es_miembro_conversacion(uuid)` | Sí | Heredado de PUBLIC | Sí | A | `cuentas_proveedor WHERE id = auth.uid()`; empresa NULL ⇒ `RETURN false`. |
| `estado_plan_visitas()` | Sí | Heredado de PUBLIC | Sí | A | `mi_empresa_proveedor()` NULL ⇒ `RETURN` sin filas. |
| `get_auth_user_pais_id()` | Sí | Heredado de PUBLIC | Sí | A | `SELECT pais_id FROM perfiles WHERE id = auth.uid()`; anon ⇒ NULL. |
| `get_auth_user_rol()` | Sí | Heredado de PUBLIC | Sí | A | Ídem: sin `auth.uid()` no hay fila. |
| `get_empresa_id_proveedor()` | Sí | Heredado de PUBLIC | Sí | A | Filtra por `id = auth.uid()` y `rol_en_empresa='admin'`. |
| `get_empresa_id_session()` | Sí | Heredado de PUBLIC | Sí | A | Filtra por `id = auth.uid()`. |
| `get_planes_visitador_proveedor(uuid)` | Sí | Heredado de PUBLIC | **No** | **C** | **Fail-open trivaluado.** Con `p_empresa_id` explícito `v_empresa` no es NULL, y el gate `v_empresa <> mi_empresa_proveedor() AND NOT ...` vale `NULL AND true = NULL`, así que el `RETURN` nunca se ejecuta. Medido: anon leyó 1 fila. |
| `get_slots_ocupados(uuid,date,date)` | Sí | Heredado de PUBLIC | **No** | **C** | Ni una mención de `auth.uid()`. Medido: anon leyó 2 filas de `visitas_agendadas` de un médico real. |
| `get_visitas_proveedor()` | Sí | Heredado de PUBLIC | Sí | A | `v_empresa_id` sale de `auth.uid()`; NULL ⇒ `WHERE = NULL` ⇒ `'[]'`. |
| `handle_new_paciente()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger de `auth.users`; Postgres rechaza invocarla como RPC. |
| `insertar_historial_cita()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger; no invocable como RPC. |
| `insertar_historial_receta()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger; no invocable como RPC. |
| `invitaciones_laboratorio_pendientes()` | Sí | Heredado de PUBLIC | Sí | A | Las dos ramas del `OR` cuelgan de `mi_empresa_proveedor()`; NULL ⇒ 0 filas. |
| `invitar_miembro_proveedor(text,text,text,text)` | Sí | Heredado de PUBLIC | Sí | A | `v_caller_rol IS DISTINCT FROM 'admin'` es TRUE con NULL ⇒ `RAISE`. |
| `laboratorios_para_medico()` | Sí | Heredado de PUBLIC | Sí | A | `e.pais_id = v_pais` con `v_pais` NULL ⇒ 0 filas (fail-closed, documentado en el cuerpo). |
| `liberar_examen_al_paciente(integer)` | No | Explícito a anon | Sí | A | Las cuatro alternativas del gate cuelgan de `auth.uid()`; anon ⇒ `PT002`. |
| `liberar_orden_al_paciente(uuid)` | No | Explícito a anon | Sí | A | Las condiciones de autoría viven en el `WHERE` del UPDATE; anon ⇒ `{"liberados":0}`. |
| `marcar_leido_chat(uuid)` | Sí | Heredado de PUBLIC | Sí | A | `IF NOT puede_ver_conversacion(...) THEN RETURN`. |
| `mensajes_conversacion(uuid)` | Sí | Heredado de PUBLIC | Sí | A | `IF NOT puede_ver_conversacion(...) THEN RAISE 'No autorizado'`. |
| `metricas_campana_proveedor()` | No | Explícito a anon | Sí | A | `cp.empresa_id = mi_empresa_proveedor()`; NULL ⇒ 0 filas. |
| `mi_clinica_id()` | Sí | Heredado de PUBLIC | Sí | A | `private.clinicas_de(auth.uid())`. |
| `mi_clinica_medico()` | Sí | Heredado de PUBLIC | Sí | A | Cuelga de `obtener_clinica_principal_medico(auth.uid())`. |
| `mi_empresa_proveedor()` | Sí | Heredado de PUBLIC | Sí | A | `WHERE id = auth.uid() AND activo`. |
| `mi_equipo_proveedor()` | Sí | Heredado de PUBLIC | Sí | A | Ídem. |
| `mi_rol_proveedor()` | Sí | Heredado de PUBLIC | Sí | A | Ídem. |
| `mis_conversaciones()` | Sí | Heredado de PUBLIC | Sí | A | `WHERE c.empresa_id = mi_empresa_proveedor() AND puede_ver_conversacion(...)`. |
| `mis_impresiones_campana_recientes()` | No | Explícito a anon | Sí | A | `cm.perfil_id = auth.uid()`; NULL ⇒ 0 filas. |
| `obtener_admins_ezpay()` | Sí | Heredado de PUBLIC | **No** | **C** | Sin `auth.uid()` y sin parámetros: invocable a ciegas. Medido: anon obtuvo los 3 `user_id` con rol `super_admin`/`ezpay_admin`/`admin_finanzas`. |
| `obtener_clinica_principal_medico(uuid)` | Sí | Heredado de PUBLIC | **No** | **C** | Sin `auth.uid()`; devuelve la clínica principal de cualquier `medico_id`. Medido: anon leyó 1 fila. Es helper interno de `laboratorios_para_medico` y `mi_clinica_medico`. |
| `obtener_contexto_visita(bigint)` | No | Explícito a anon | Sí | A | Gate copiado de `exp_select_medico`, con `COALESCE`; anon ⇒ `42501`. |
| `otorgar_capacidad_empresa(uuid,text,timestamptz)` | No | Explícito a anon | Sí | A | `if not coalesce(private.tiene_rol(...), false) then raise` — el `COALESCE` lo hace fail-closed. |
| `otorgar_puntos_referido()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger; no invocable como RPC. |
| `paciente_examenes()` | No | Explícito a anon | Sí | A | `paciente_id IN (SELECT ... WHERE auth_user_id = auth.uid())`; anon ⇒ 0 filas. |
| `puede_auditar_chat()` | Sí | Heredado de PUBLIC | Sí | A | `EXISTS(... id = auth.uid())` ⇒ false. |
| `puede_ver_conversacion(uuid)` | Sí | Heredado de PUBLIC | Sí | A | Cuelga de `es_miembro_conversacion` + `puede_auditar_chat` + `mi_empresa_proveedor`. |
| `registrar_campana_metrica(integer,uuid,integer,text,text,boolean,text,uuid)` | Sí | Heredado de PUBLIC | **No** | **C** | Sin `auth.uid()` y es un INSERT. Medido: anon insertó una fila en `campana_metricas` con `perfil_id`/`paciente_id`/`clickeado` arbitrarios. |
| `registrar_proveedor(text,text,text,uuid,text,text,text,text,text,text)` | Sí | Heredado de PUBLIC | Sí | A | `IF v_user_id IS NULL THEN RAISE 'Usuario no autenticado'`. El alta pública corre DESPUÉS del `signUp`, ya con sesión. |
| `responder_invitacion_laboratorio(uuid,boolean)` | Sí | Heredado de PUBLIC | Sí | A | `mi_empresa_proveedor()` NULL ⇒ `RAISE`. El token por sí solo no alcanza. |
| `set_default_estado_propuesta()` | Sí | Heredado de PUBLIC | N/A (trigger) | A | Trigger; no invocable como RPC. |
| `sincronizar_mis_canales()` | Sí | Heredado de PUBLIC | Sí | A | `v_empresa` sale de `auth.uid()`; NULL ⇒ `RETURN`. |
| `slots_ocupados_cita(uuid,date,date)` | Sí | Heredado de PUBLIC | **No** | **C** | Sin `auth.uid()`; devuelve fecha+hora de las `citas` de cualquier médico. Medido: anon leyó 11 filas. |
| `supervisa_cuenta_proveedor(uuid)` | Sí | Heredado de PUBLIC | Sí | A | `EXISTS(... e.supervisor_id = auth.uid())` ⇒ false. |

## Grants explícitos a anon sin PUBLIC

- `actualizar_estado_cita(bigint,text)`
- `asignar_medico_cita(bigint,uuid)`
- `consultar_reveal_log(bigint,text,integer)`
- `crear_cita(bigint,uuid,uuid,date,time,time,text,text,text,uuid)`
- `detalle_entrega_delivery(bigint)`
- `liberar_examen_al_paciente(integer)`
- `liberar_orden_al_paciente(uuid)`
- `metricas_campana_proveedor()`
- `mis_impresiones_campana_recientes()`
- `obtener_contexto_visita(bigint)`
- `otorgar_capacidad_empresa(uuid,text,timestamptz)`
- `paciente_examenes()`

**Total: 12** (5 del primer lote + 7 de este). Las 12 son ejecutables por `anon` unicamente por su
grant explicito: revocarlo no obliga a tocar PUBLIC. Las otras 50 lo heredan de PUBLIC.

## Grupo C — exposicion real sin sesion (6)

Las seis se EJERCITARON como `anon` contra produccion, dentro de `BEGIN`/`ROLLBACK`. No se dedujo del
texto del gate: se midio que devuelve.

| Funcion | Severidad | Que permite sin sesion | Medido |
|---|---|---|---|
| `registrar_campana_metrica(...)` | **Alta** | **ESCRITURA.** Insertar filas arbitrarias en `campana_metricas` con `perfil_id`, `paciente_id`, `clickeado` y `contexto` a eleccion. Falsea impresiones y clicks —la base de la facturacion y de los reportes de publicidad— y permite inflar la tabla sin limite. | anon inserto 1 fila (la tabla tiene 1496 hoy) |
| `get_planes_visitador_proveedor(uuid)` | **Media-alta** | Leer los planes de visitador contratados de CUALQUIER empresa: visitas incluidas, usadas, restantes, fechas y estado. Fail-open trivaluado, la misma clase que documenta PA-FAILOPEN (mig 222). | anon leyo 1 fila pasando un `empresa_id` |
| `obtener_admins_ezpay()` | **Media** | Enumerar los `user_id` de todas las cuentas privilegiadas (`super_admin`, `ezpay_admin`, `admin_finanzas`). Sin parametros: se invoca a ciegas, no hace falta conocer ningun id previo. | anon obtuvo los 3 |
| `slots_ocupados_cita(uuid,date,date)` | **Media-baja** | Leer fecha y hora de todas las citas de un medico. No expone identidad del paciente, pero si la agenda completa del medico y, por diferencia, su carga de trabajo. | anon leyo 11 filas |
| `get_slots_ocupados(uuid,date,date)` | **Media-baja** | Idem sobre `visitas_agendadas` (visitas de visitador medico). | anon leyo 2 filas |
| `obtener_clinica_principal_medico(uuid)` | **Baja** | Resolver la clinica principal de cualquier `medico_id`. Helper interno de otras dos funciones; sin call-site propio en el front. | anon leyo 1 fila |

## Grupo B — camino pre-login legitimo (0)

**Ninguna de las 62 lo necesita.** Los candidatos por nombre se descartaron midiendo, no suponiendo:

- `registrar_proveedor` corta con `RAISE 'Usuario no autenticado'`; el alta publica llama primero a
  `supabase.auth.signUp()`, asi que cuando llega a la RPC ya hay sesion.
- `responder_invitacion_laboratorio` exige `mi_empresa_proveedor()`: el token por si solo no alcanza.
- `handle_new_paciente` y los otros cuatro triggers no son invocables como RPC.
- `registrar_campana_metrica` parecia necesitar anon para impresiones anonimas, pero sus tres
  consumidores (`BannerPublicidad`, `BannerPublicidadGlobal`, `BannerPublicidadProfesional`) se
  montan solo en dashboards con sesion: `ClinicaDashboardPage`, `MedicoDashboardPage`,
  `DashboardPage` y `WebAppDashboard`. Por eso quedo en C y no en B.

## Nota de procedencia

Las primeras 20 filas de la tabla (de `abrir_canal_administracion` a `enviar_mensaje_chat`) venian
del lote anterior y se transcriben tal como estaban; no se re-verificaron en esta pasada. Las 42
restantes y las secciones de Grupo B y C son de este lote.

