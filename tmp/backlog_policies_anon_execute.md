# Backlog — sacar las 10 funciones de policies del EXECUTE de `anon`

**Esto NO es parte de la mig 301.** La 301 las deja explícitamente afuera. Esta nota existe para que
la excepción quede como deuda escrita y no como un detalle olvidado adentro de un header de SQL.

Medido contra prod enlazada el 18-sep-2026.

## Qué queda abierto

La mig 301 le revoca el `EXECUTE` a `anon` en 49 funciones `SECURITY DEFINER` de `public` y cierra la
fábrica de default privilege. Quedan **11** ejecutables por `anon`:

- `registrar_proveedor` — excepción por **producto** (único flujo pre-login). No es deuda.
- las otras **10** — excepción **técnica**, y esto sí es deuda:

```
get_auth_user_rol          get_auth_user_pais_id      mi_empresa_proveedor
mi_rol_proveedor           mi_clinica_id              puede_ver_conversacion
supervisa_cuenta_proveedor get_empresa_id_proveedor   get_empresa_id_session
admin_clinica_de_medico
```

## Por qué no se pudieron revocar

Las 10 viven adentro del `USING` de policies RLS. **Una policy se evalúa con los privilegios del
LLAMANTE** — la lección que la mig 284 dejó rompiendo prod unos minutos. Revocarles el `EXECUTE` no
le niega filas a `anon`: hace que la tabla entera le lance **`42501`**.

No es teoría. La **primera** versión de la 301 las incluía, y el dry-run murió con
`42501: permission denied for function get_auth_user_pais_id`. Ese error es el que motivó recortar el
alcance de 59 a 49.

**Fue un error de scoping mío**: busqué call-sites en `src/` y nunca miré si las funciones se llamaban
desde adentro de una policy. Un censo de privilegios que sólo mira el frontend no ve esta clase.

## Tamaño real del frente

| | |
|---|---:|
| Policies que mencionan alguna de las 10 | **78** |
| Tablas distintas involucradas | **38** |
| De esas, tablas donde `anon` tiene `SELECT` (las que romperían) | **30** |

Desglose por función (tablas / policies / tablas con `SELECT` para `anon`):

| función | tablas | policies | con anon SELECT |
|---|---:|---:|---:|
| `mi_empresa_proveedor` | 23 | 31 | 18 |
| `get_auth_user_rol` | 13 | 14 | 10 |
| `get_auth_user_pais_id` | 10 | 10 | 9 |
| `mi_rol_proveedor` | 8 | 12 | 7 |
| `puede_ver_conversacion` | 3 | 3 | 3 |
| `mi_clinica_id` | 2 | 2 | 2 |
| `supervisa_cuenta_proveedor` | 2 | 2 | 2 |
| `get_empresa_id_session` | 1 | 2 | 1 |
| `get_empresa_id_proveedor` | 1 | 1 | 1 |
| `admin_clinica_de_medico` | 1 | 1 | 1 |

Las 10 además tienen `=X/postgres` en su ACL, o sea que el `EXECUTE` les llega **también por
`PUBLIC`**: un `REVOKE ... FROM anon` solo no las toca. Medido — fue lo que hizo que la primera
contraprueba por mutación de la 301 no disparara.

## Qué habría que hacer (no resuelto acá)

Reescribir las 78 policies para que no dependan del `EXECUTE` de `anon` sobre funciones de `public`.
Las direcciones posibles, ninguna evaluada todavía:

1. **Mover los helpers a `private`** y que las policies llamen ahí. Hay precedente vivo en el repo
   (`private.tiene_rol`, `private.es_medico_de`, etc. ya se usan adentro de policies). Habría que
   medir si el esquema `private` cambia quién puede ejecutar qué desde una policy.
2. **Agregar `TO authenticated`** a las policies, para que `anon` ni las evalúe. Cambia la semántica
   de cada policy y hay que revisarlas una por una: alguna puede estar sirviendo tráfico anónimo a
   propósito.
3. **Revocarle `SELECT` a `anon` sobre las 30 tablas.** Es el corte más limpio, y también el más
   riesgoso: exige confirmar que ninguna pantalla pública lee de ahí.

Cualquiera de las tres es un frente propio, con su propio recon, su propio dry-run y sus propias
probes. **No entra en la 301.**

## Cómo está vigilado mientras tanto

No queda a ciegas. En `tests/rls/probes_escritura.sql`:

- **P739** compara el CONJUNTO de `SECDEF` ejecutables por `anon` contra la lista de 11 esperadas, y
  publica lo que sobra y lo que falta. Si alguien agrega una función nueva que nace con `anon`, o si
  saca una de las 10 sin reescribir su policy, P739 se pone rojo.
- **P741** es el control negativo: verifica que las 10 conserven el `EXECUTE` **y** ejercita 5 de las
  tablas que dependen de ellas (`perfiles`, `citas`, `cuentas_proveedor`, `pacientes`, `clinicas`)
  confirmando que le responden a `anon` sin `42501`.

Contraprobado por mutación: revocarle el `EXECUTE` a `get_auth_user_rol` (de `PUBLIC` y de `anon`)
hace abortar el autochequeo nombrando la función y las 5 tablas rotas.
