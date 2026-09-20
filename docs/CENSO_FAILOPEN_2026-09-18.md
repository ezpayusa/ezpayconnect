# Censo del patron fail-open trivaluado — esquema `public`

Medicion contra produccion enlazada, 18-sep-2026. Todo dentro de `BEGIN`/`ROLLBACK`.

**El patron**: un gate de autorizacion armado con `OR`/`AND` sobre comparaciones sueltas. Si alguna
puede valer NULL, `NULL OR false = NULL` y `NOT NULL = NULL`, y un `IF` con condicion NULL **no entra
al THEN**: el `RAISE`/`RETURN` nunca ocurre y el gate queda abierto.

## Como se llego a la lista (y que se descarto en el camino)

Se analizaron las **266** funciones `plpgsql`+`sql` de `public` con un parser que balancea parentesis
y parte la condicion en operandos de nivel superior. El detector se equivoco dos veces y las dos se
corrigieron **midiendo**, no razonando:

| Corrida | Candidatas | Por que bajo |
|---:|---:|---|
| 1 | 73 | — |
| 2 | 45 | matcheaba el `IF` de `END IF` y capturaba condiciones inexistentes |
| 3 | 25 | trataba toda llamada a helper como NULL-able; se leyeron los helpers vivos |
| final | **25 medidas** | Paso A descarta 10 mas por el helper; Paso B ejercita el resto |

**Helpers medidos (cuerpo vivo en prod). Ninguno puede devolver NULL:**

```
private.tiene_rol                -> SELECT COALESCE(private.rol_usuario() = ANY (p_roles), false)
private.es_admin_pais            -> SELECT COALESCE(public.get_auth_user_rol() = 'admin_pais', false)
private.admin_puede_gestionar_empresa -> SELECT COALESCE(..., false)
private.paciente_en_clinica_de   -> EXISTS(...) OR EXISTS(...)
private.paciente_es_mio          -> EXISTS(...)
private.es_medico_de             -> EXISTS(...)
private.medico_atiende_paciente  -> EXISTS(...)
private.puede_aprobar_visitas    -> EXISTS(...)
private.medico_es_de_mi_clinica  -> tiene_rol(...) AND EXISTS(...)
public.puede_auditar_chat        -> SELECT EXISTS(...)
public.es_miembro_conversacion   -> plpgsql; su unica rama dudosa es `RETURN v_rol IN (...)`, y
                                    cuentas_proveedor.rol_en_empresa es NOT NULL con default 'admin'
```

Eso saco del censo, entre otras, a `gate_accion_phi`, `listar_documentos_paciente`,
`capturar_signo_vital` y `estado_consentimiento_paciente`, que en la corrida intermedia parecian el
hallazgo grave. **No lo son.**

## Actores del Paso B

- **anon**: sin sesion.
- **paciente**: `authenticated` SIN rol privilegiado — `0dd0c68c-026c-4ebc-9475-e6791cc54933`, paciente
  real de Guatemala. Es el actor que importa para las que no tienen EXECUTE a anon.

Parametros usados, todos apuntando a objetos **ajenos** al actor: `super_admin=41904e2c…`,
`medico=09d243d5…`, `cita CON medico=54`, `cita SIN medico=27`, `signo=715`,
`clinica=c76d862c…`, `empresa CON planes activos=411d6f8c…`, `conv_administracion=1584377f…`.

---

# VEREDICTO C — explotable, medido (3)

| Funcion | Actor | Que se midio | Alcance |
|---|---|---|---|
| **`actualizar_estado_cita(bigint,text)`** | anon **y** paciente | `SIN_ERROR` y el hash de `citas.estado` **cambio** | **ESCRITURA.** Cambia el estado de cualquier cita conociendo su `id` (entero secuencial, hoy hasta 54). Unico freno accidental: el trigger PE001 tapa `'completada'`; el resto de los estados pasan. |
| **`obtener_contexto_visita(bigint)`** | anon **y** paciente | `DEVOLVIO` el jsonb con la nota y las sugerencias de IA | **LECTURA DE PHI.** Dos caminos distintos: **anon** lee CUALQUIER cita (cita 54, con medico → DEVOLVIO); **paciente autenticado** lee las citas **sin medico asignado** (cita 27, `medico_id IS NULL` → DEVOLVIO), porque ahi `NULL = auth.uid()` envenena igual. Hoy **5 de 37 citas** tienen `medico_id` NULL. Con medico asignado el gate SI corta al paciente (cita 54 → `42501`). |
| **`get_planes_visitador_proveedor(uuid)`** | anon **y** paciente | **1 fila** con la empresa `411d6f8c…` (la que tiene planes activos) | Planes de visitador contratados de cualquier empresa: visitas incluidas, usadas, restantes, fechas, estado. La primera corrida dio 0 solo porque la empresa elegida no tenia planes — no por el gate. |

**Las tres son la MISMA falla**: una comparacion suelta contra `auth.uid()` o contra
`mi_empresa_proveedor()` dentro de un `OR`/`AND`, sin `COALESCE`.

---

# VEREDICTO A — no explotable, medido (22)

## Ejercitadas con los dos actores

| Funcion | anon | paciente | Por que es A |
|---|---|---|---|
| `obtener_perfil(uuid)` | `42501` | `0 filas` | anon no tiene EXECUTE; con `auth.uid()` real la comparacion da false y el `RETURN` dispara |
| `obtener_clinica_usuario(uuid)` | `42501` | `P0001` | idem; ademas el gate tiene `OR auth.uid() IS NULL` que lo cierra |
| `liberar_examen_al_paciente(integer)` | `PT002` | `PT002` | corta antes de llegar al `UPDATE` |
| `actualizar_clinica(uuid,text,text,text,text)` | `42501` | `P0001` | el hash de `clinicas.nombre` no se movio |
| `validar_signo_vital(bigint)` | `42501` | `P0001` | — |
| `activar_modulo_visitadores(uuid,integer,date)` | `42501` | `PC001` | — |
| `solicitar_personalizacion(text,text,text,text)` | `42501` | `PT003` | `solicitudes_personalizacion` sin delta |
| `guardar_foto_publica_asesor(text)` | `42501` | `PA031` | `split_part` nunca devuelve NULL: era falso positivo del detector |
| `cambiar_estado_miembro_proveedor(uuid,boolean)` | `P0001` | `P0001` | — |
| `cambiar_rol_proveedor(uuid,text)` | `P0001` | `P0001` | el gate real usa `IS DISTINCT FROM`; lo marcado era la regla "no te saques el ultimo admin" |
| `crear_cita(bigint,uuid,uuid,date,…)` | `P0001` | `P0001` | — |
| `mensajes_conversacion(uuid)` | `P0001` | `P0001` | — |
| `enviar_mensaje_chat(uuid,text)` | `P0001` | `P0001` | `chat_mensajes_internos` sin delta (4 → 4) |
| `abrir_canal_equipo(uuid)` | `P0001` | `P0001` | `chat_conversaciones` sin delta (5 → 5) |
| `destinatarios_conversacion(uuid)` | `0 filas` | `0 filas` | — |
| `puede_ver_conversacion(uuid)` | `false` | `false` | devuelve false, no NULL |
| `marcar_leido_chat(uuid)` | `SIN_ERROR` | `SIN_ERROR` | corre pero `chat_lecturas` sin delta (6 → 6): el `RETURN` temprano dispara |

## Descartadas en el Paso A (el helper del que dependen no puede ser NULL)

| Funcion | Operando que se creia NULL-able | Medicion que la descarta |
|---|---|---|
| `listar_canjes_pendientes()` | `private.es_admin_pais()` | `COALESCE(..., false)` |
| `listar_propuestas_especialidad(text)` | `private.es_admin_pais()` | idem |
| `listar_solicitudes_personalizacion(text)` | `private.es_admin_pais()` | idem |
| `notificar_empresa_estado(uuid)` | `es_admin_pais() AND admin_puede_gestionar_empresa()` | los dos con `COALESCE` |

## No alcanzable

| Funcion | Por que |
|---|---|
| `asociar_medico_clinica(uuid,uuid,boolean)` | **No tiene EXECUTE ni para anon ni para authenticated.** Su gate tiene el patron (`es_admin_clinica` puede dar NULL con `p_clinica` NULL), pero no hay actor que la alcance. |

---

# Lista definitiva para la migracion 300

Las **3** funciones con veredicto C de este censo:

1. `actualizar_estado_cita(bigint, text)`
2. `obtener_contexto_visita(bigint)`
3. `get_planes_visitador_proveedor(uuid)`

Las dos que ya estaban confirmadas (`get_planes_visitador_proveedor` y `actualizar_estado_cita`) son
parte de estas tres. **La unica nueva es `obtener_contexto_visita`** — y es la mas seria de las tres,
porque lo que filtra es PHI (nota clinica + sugerencias de IA) y porque su camino de
`authenticated` no depende de que a nadie se le abra el acceso anon: basta una cita sin medico
asignado, y hay 5 en produccion.

## Pendiente separado, NO es este patron

Las 6 del censo anterior (`docs/CENSO_SECURITY_DEFINER_ANON_2026-09-18.md`, Grupo C) son otra clase: no tienen
gate en absoluto, no uno que falla abierto. Van a la 300 tambien, pero el fix es distinto —
ahi hay que ponerles un gate, no arreglarle el `COALESCE` a uno existente:
`registrar_campana_metrica`, `obtener_admins_ezpay`, `slots_ocupados_cita`, `get_slots_ocupados`,
`obtener_clinica_principal_medico`.
