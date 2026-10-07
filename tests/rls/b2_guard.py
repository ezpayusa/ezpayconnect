#!/usr/bin/env python3
"""
b2_guard.py — GATE DE ESTRUCTURA DEL HARNESS (frente B2)

QUE VIGILA Y POR QUE
--------------------
El harness `tests/rls/probes_escritura.sql` corre como UNA SOLA TRANSACCION. Eso significa que
cualquier sentencia que reviente fuera de un handler NO da rojo: MATA LA TRANSACCION ENTERA y el
SELECT de veredictos nunca llega a ejecutarse. La salida es vacia, y una salida vacia se lee como
"todavia no lo corri", no como "esta roto". Ya paso dos veces:

  * 2026-07-02 (commit 18cf819): las migs 202/204 introdujeron gates de capacidad que los fixtures no
    satisfacian. El harness abortaba desde entonces y nadie lo noto durante DOS MESES.
  * 2026-09-03 (lote 1 del paquete PA-FAILOPEN): cuatro UPDATE top-level escribieron empresa_id=NULL
    -> 23502 -> muerte de la transaccion, otra vez sin una sola fila de salida.

Este script cuenta cuatro cosas sobre el propio archivo y falla (exit 1) si alguna CRECE.

POR QUE ES UN SCRIPT Y NO UN PROBE
-----------------------------------
Un probe no puede leer su propio fuente: pg_read_file() lee del SERVIDOR y exige superusuario o
pg_read_server_files, y este archivo vive en la maquina del cliente. P516 dentro del harness solo
PUBLICA el baseline para que quien lea la salida sepa que este gate existe; el que cuenta es este.

LAS CUATRO METRICAS
-------------------
1) top_level_dml_ddl — sentencias DML/DDL fuera de todo bloque DO.
   Baseline 0. La fase 1 de B2 envolvio las 14 que quedaban (FX12-FX18).
   EXCLUSION documentada: `CREATE ... pg_temp.*`. Es DDL transaccional sobre un schema temporal, no
   puede corromper ningun fixture y desaparece con el ROLLBACK. Hoy hay exactamente una: la funcion
   del censo que consumen P480/P481.

2) cast_directo — bloques DO SIN handler que castean current_setting sin NULLIF.
   Baseline 0. La fase 2.1 lo llevo de 155 a 0 en tres tandas (52+52+51 bloques, 287 ocurrencias).
   Quedan 133 bloques CON handler que tienen el mismo cast y NO se tocaron a proposito: su handler
   puede estar aseverando ese SQLSTATE deliberadamente, y cambiarlo le cambiaria el veredicto.

3) do_sin_handler — bloques DO sin EXCEPTION handler.
   Baseline 211. DEUDA CON FECHA, igual que la allowlist del centinela P480: la ataca la FASE 2.2.
   Que este en el baseline no dice "esta bien", dice "esta contado y tiene fase asignada".
   REGLA: ver tiene_handler(). Se evalua el cuerpo completo (no linea a linea) y `RAISE EXCEPTION`
   NO cuenta como handler.
   El baseline 319 que estuvo committeado entre ea671cb y cf16351 estaba INFLADO EN 108 y por lo
   tanto era PERMISIVO: no habria disparado hasta que alguien agregara 108 bloques sin handler.
   El detector tiene test propio en tests/rls/b2_guard_test.py, con los casos positivos Y el
   negativo (RAISE EXCEPTION), que es el error simetrico e invisible.

4) catchall_verde — handlers `EXCEPTION WHEN OTHERS` que publican un valor VERDE de forma
   INCONDICIONAL: `set_config('probe.<x>', '<literal>'...)` cuyo literal NO empieza con un prefijo de
   PREFIJOS_ROJOS (importado de harness_run.py: lo que el runner no cuenta rojo), fuera de todo IF/CASE
   que mire el error (SQLSTATE, SQLERRM, GET STACKED DIAGNOSTICS, un nombre de condicion o una variable
   cargada con el error). El fin del handler se resuelve por anidamiento (IF, CASE, BEGIN, LOOP). Cualquier error
   (una firma que cambio, un 22P02 del fixture, un deadlock) sale VERDE: el probe no distingue el
   rechazo que mide de una rotura (clase P44, censo de veredictos 2026-10-07, tmp/censo_veredictos).
   Se cuenta por set_config, no por bloque. No es deuda con fecha: es un techo para que la clase no
   CREZCA; un probe nuevo tiene que mirar el SQLSTATE (patron GET STACKED DIAGNOSTICS de P1-P6).
   Ver catchall_verde(). Quedan FUERA a proposito: las variables a las que se les asigna un verde en
   el handler y se publican despues (no hay forma estatica barata de seguirlas) y las keys dinamicas.

USO
---
    python tests/rls/b2_guard.py            # sobre tests/rls/probes_escritura.sql
    python tests/rls/b2_guard.py <archivo>  # sobre otro (util para la copia de scratch)
    npm run harness:guard

Sale 0 si ninguna metrica crecio, 1 si alguna crecio. Si BAJAN, lo dice y recuerda actualizar el
baseline en este archivo y en P516.
"""
import io
import os
import re
import sys

# ============================== BASELINE DECLARADO ==============================
# Al bajar una metrica, actualizar ACA y en el comentario de P516 del harness, EN EL MISMO COMMIT
# que la baja. Un baseline que se actualiza "despues" es un baseline que alguien olvida.
BASELINE_TOP_LEVEL = 0            # fase 1 de B2 (2026-09-03), CERRADO
BASELINE_CAST_DIRECTO = 0         # fase 2.1 CERRADA (155 -> 103 -> 51 -> 0, tres tandas)
BASELINE_DO_SIN_HANDLER = 155     # 156 -> 155 (mig 324, P23 gano handler interno). fase 2.2 CERRADA: 211 -> ... -> 156. Los 55 bloques
                                  # que ESCRIBEN estan envueltos, P481 incluido. Los 156 que quedan
                                  # solo LEEN y publican: una caida suya no arrastra estado ajeno, asi
                                  # que este numero deja de ser deuda y pasa a ser el normal.
                                  # El 319 previo estaba inflado en 108 por tres fallas del detector,
                                  # corregidas en aac4562 y fijadas por b2_guard_test.py.
BASELINE_CATCHALL_VERDE = 202     # 139 del lote 3 + 63 por el punto 3 de la review (verde = lo que el runner NO
                                  # cuenta rojo, PREFIJOS_ROJOS importado): son FLAGS internos de fixture que un
                                  # catch-all pone en un valor no rojo y que el probe siguiente lee como "no
                                  # medible": 39 *_ready='0' (+ p291_called, vj_visitas) y 21 'ERR:'/'err' que el
                                  # siguiente convierte en N/A (p.ej. rx_legit -> P421). Los puntos 1 (fin del handler
                                  # por anidamiento) y 2 (IF/CASE solo exime si mira el error) no agregaron ni
                                  # sacaron sitios hoy: 0 y 0. Lote 3 (139) = 134 del censo - P44 + 5 OCULTO + p141_act.
                                  # Techo, no deuda con fecha: que no CREZCA.

# ===============================================================================
#
# POR QUE ~125 VA A SER UN NUMERO ACEPTABLE Y NO "FALTA TERMINAR"
# ---------------------------------------------------------------
# Al cerrar la fase 2 quedan ~125 bloques DO sin handler, y eso es un punto de llegada, no una
# obra a medias. Son bloques de LECTURA PURA: hacen SELECT y publican un veredicto con set_config,
# sin escribir nada ni directa ni indirectamente. Con la fase 2.1 cerrada tampoco pueden morir por
# el cast (el NULLIF convierte el caso '' en NULL en vez de 22P02).
# Lo unico que podria matarlos es un cambio de esquema debajo — una columna que desaparece, un tipo
# que cambia — y ese es un riesgo DISTINTO: no lo arregla un handler, lo arregla actualizar el probe.
# Envolverlos igual seria 125 oportunidades de alterar en silencio lo que mide cada uno, a cambio de
# proteger contra algo que un handler no protege. El guard los vigila para que no CREZCAN, que es
# la garantia que sirve.
# ===============================================================================

DEFAULT = 'tests/rls/probes_escritura.sql'
TAG = re.compile(r'\$([a-zA-Z_][a-zA-Z0-9_]*)?\$')
DML = re.compile(
    r'^\s*(UPDATE|INSERT|DELETE|ALTER\s+TABLE|CREATE\s+(?:OR\s+REPLACE\s+)?'
    r'(?:FUNCTION|TABLE|INDEX)|DROP|TRUNCATE|GRANT|REVOKE)\b', re.I)
PGTEMP = re.compile(r'\bpg_temp\.', re.I)
# 3a metrica: cast DIRECTO sobre current_setting, sin NULLIF. `current_setting('x',true)` devuelve
# NULL si nunca se seteo, pero el harness setea CADENAS VACIAS a proposito (88 coalesce(...,'')
# dentro de set_config + 7 literales), y ''::uuid es 22P02 -> mata la transaccion igual que un
# NOT NULL. Se cuenta por BLOQUE sin handler, no por ocurrencia: un bloque con handler puede estar
# aseverando ese SQLSTATE a proposito, asi que esos quedan fuera del alcance.
CAST_DIRECTO = re.compile(
    r'current_setting\s*\([^()]*\)\s*::\s*(uuid|int|integer|bigint|numeric|date|timestamp)', re.I)
HANDLER = re.compile(r'\bEXCEPTION\b\s+\bWHEN\b', re.I)
LITERAL = re.compile(r"'(?:[^']|'')*'")   # cadena SQL, con '' como comilla escapada


def tiene_handler(cuerpo):
    """True si el bloque tiene un EXCEPTION handler.

    DETECCION CORREGIDA (2026-09-03). La version anterior miraba linea por linea con
    `EXCEPTION\\s+WHEN` mientras el bloque estaba abierto, y fallaba de TRES formas, las tres
    INFLANDO el conteo de "sin handler" y volviendo el gate PERMISIVO:
      1. `EXCEPTION` y `WHEN` en LINEAS DISTINTAS (forma real en el archivo, p.ej. el bloque de P33).
      2. El handler en la LINEA DE CIERRE: el flag ya se habia apagado al procesar el tag de cierre.
      3. Bloques DO de UNA SOLA LINEA: nunca se llegaba a chequear.
    Ahora se evalua el CUERPO COMPLETO (slice de lineas) y `\\s` cruza saltos de linea.

    EL ERROR SIMETRICO — el que falla en la direccion INVISIBLE, subcontando los sin-handler y
    volviendo el gate mas estricto de la cuenta sin que nadie lo note: contar como handler algo que
    contiene las palabras pero no lo es. El caso real es `EXCEPTION WHEN` DENTRO DE UNA CADENA
    (p.ej. un texto de veredicto que las mencione). Por eso se quitan los literales SQL antes de
    buscar. Hoy no hay ninguno en el archivo, pero el dia que alguien escriba un veredicto que las
    mencione, el detector no se lo tiene que comer.

    NO se excluye `RAISE EXCEPTION`: se probo y es CODIGO MUERTO. En `RAISE EXCEPTION 'msg'` lo que
    sigue a EXCEPTION es un literal, no WHEN, asi que el regex no matchea nunca ahi — y
    `RAISE EXCEPTION WHEN` no es sintaxis valida de plpgsql (0 ocurrencias en el archivo). Una
    exclusion que ningun test puede disparar es peor que no tenerla: parece cubierta y no lo esta.
    """
    return bool(HANDLER.search(LITERAL.sub("''", cuerpo)))


# 4a metrica. Las palabras clave se buscan sobre el texto con los literales ENMASCARADOS (mismo largo,
# contenido reemplazado), para que un 'CASE' o un 'END' dentro de un texto de veredicto no corte ni
# condicione el handler; el literal publicado se lee del texto original en la misma posicion.
#
# VERDE = lo que el RUNNER no cuenta como rojo: se importa PREFIJOS_ROJOS de harness_run.py en vez de
# tener una lista propia (review del censo, punto 3): 'OK? (', 'PENDIENTE', 'RECHAZA', 'OK-SENAL'...
# pasan como verdes para el runner, asi que para este gate tambien. El literal vacio no cuenta: un
# veredicto vacio ya es rojo (verificar() del runner y P000).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness_run import PREFIJOS_ROJOS, _sin_tildes  # noqa: E402

WHEN_OTHERS = re.compile(r'\bWHEN\s+OTHERS\s+THEN\b', re.I)
SET_PROBE = re.compile(r"set_config\s*\(\s*'probe\.[^']*'\s*,\s*'((?:[^']|'')*)'", re.I)
TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*|;|'x*'", re.I)
# Una condicion EXIME solo si mira el error (punto 2). Nombres de condicion de Postgres: los que usa el
# harness y los de la familia *_violation / *_privilege / undefined_*; OTHERS no exime (es el catch-all).
ERROR_EN_COND = re.compile(
    r'\b(SQLSTATE|SQLERRM|RETURNED_SQLSTATE|MESSAGE_TEXT|PG_EXCEPTION_DETAIL|PG_EXCEPTION_HINT|'
    r'\w+_violation|\w+_privilege|undefined_\w+|raise_exception|no_data_found|too_many_rows|'
    r'invalid_text_representation|division_by_zero|deadlock_detected|lock_not_available)\b', re.I)
ASIGNA_ERROR = re.compile(r'\b([A-Za-z_]\w*)\s*:=\s*[^;]*?\b(SQLSTATE|SQLERRM)\b', re.I)
DIAG = re.compile(r'\bGET\s+STACKED\s+DIAGNOSTICS\b([^;]*)', re.I)


def _enmascarar(texto):
    return LITERAL.sub(lambda m: "'" + 'x' * (len(m.group(0)) - 2) + "'", texto)


def es_verde(literal):
    """True si el runner NO lo contaria como rojo (y no esta vacio)."""
    v = literal.strip()
    return bool(v) and not _sin_tildes(v.upper()).startswith(PREFIJOS_ROJOS)


def _vars_de_error(texto):
    """Variables a las que el handler les asigna el error: GET STACKED DIAGNOSTICS a = ..., b = ...;
    y v := ... SQLSTATE/SQLERRM ... ;"""
    out = set()
    for m in DIAG.finditer(texto):
        out.update(x.lower() for x in re.findall(r'([A-Za-z_]\w*)\s*=', m.group(1)))
    out.update(m.group(1).lower() for m in ASIGNA_ERROR.finditer(texto))
    return out


def _mira_error(cond, vars_err):
    if ERROR_EN_COND.search(cond):
        return True
    return any(re.search(r'\b' + re.escape(v) + r'\b', cond, re.I) for v in vars_err)


def _escanear_handler(masc, ini):
    """Recorre el handler desde `ini` (despues del THEN) con una pila de construcciones (IF, CASE, BEGIN,
    LOOP) y devuelve (fin, ramas): `fin` = offset del WHEN (proximo handler) o del END que cierra el
    bloque, ambos a NIVEL DEL HANDLER (punto 1: ni el END IF ni el END de un sub-bloque ni el WHEN de
    un CASE interno lo cortan); `ramas` = lista de (desde, hasta, [condiciones del camino]) que dice,
    para cada tramo del handler, que condiciones lo encierran. Cada frame lleva las condiciones de sus
    ramas previas: una rama ELSE hereda las de las ramas anteriores (es su negacion)."""
    toks = [(m.group(0), m.start(), m.end()) for m in TOKEN.finditer(masc, ini)]
    pila = []          # frames: {'k': IF|CASE|BEGIN|LOOP, 'previas': [...], 'actual': str, 'exc': bool}
    ramas, desde = [], ini
    def camino():
        out = []
        for f in pila:
            out.extend(f['previas'])
            if f['actual']:
                out.append(f['actual'])
        return out
    def corte(pos):
        nonlocal desde
        ramas.append((desde, pos, camino()))
        desde = pos
    def cond_hasta(i, fin_kw):
        """Texto desde el token i hasta el primer token fin_kw de ese nivel (THEN/LOOP); devuelve (texto, j)."""
        j = i
        while j < len(toks) and toks[j][0].upper() not in fin_kw:
            j += 1
        a = toks[i][1] if i < len(toks) else len(masc)
        b = toks[j][1] if j < len(toks) else len(masc)
        return masc[a:b], j
    i, prev = 0, ''
    while i < len(toks):
        w, s, e = toks[i]
        W = w.upper()
        if W == 'END':
            nxt = toks[i + 1][0].upper() if i + 1 < len(toks) else ''
            if not pila:
                corte(s)
                return s, ramas
            corte(s)
            pila.pop()
            i += 2 if nxt in ('IF', 'CASE', 'LOOP') else 1
            desde = toks[i - 1][2]
            prev = 'END'
            continue
        if W == 'WHEN':
            if not pila:
                corte(s)
                return s, ramas
            top = pila[-1]
            if prev in ('EXIT', 'CONTINUE'):
                prev = W; i += 1; continue
            if top['k'] in ('CASE', 'BEGIN'):
                corte(s)
                if top['actual']:
                    top['previas'].append(top['actual'])
                c, j = cond_hasta(i + 1, ('THEN',))
                top['actual'] = (top.get('sel', '') + ' ' + c).strip()
                i = j + 1; desde = toks[j][2] if j < len(toks) else len(masc); prev = 'THEN'
                continue
        elif W == 'IF':
            corte(s)
            c, j = cond_hasta(i + 1, ('THEN',))
            pila.append({'k': 'IF', 'previas': [], 'actual': c, 'exc': False})
            i = j + 1; desde = toks[j][2] if j < len(toks) else len(masc); prev = 'THEN'
            continue
        elif W == 'ELSIF' and pila and pila[-1]['k'] == 'IF':
            corte(s)
            top = pila[-1]
            top['previas'].append(top['actual'])
            c, j = cond_hasta(i + 1, ('THEN',))
            top['actual'] = c
            i = j + 1; desde = toks[j][2] if j < len(toks) else len(masc); prev = 'THEN'
            continue
        elif W == 'ELSE' and pila and pila[-1]['k'] in ('IF', 'CASE'):
            corte(s)
            top = pila[-1]
            top['previas'].append(top['actual'])
            top['actual'] = ''
        elif W == 'CASE':
            corte(s)
            sel, j = cond_hasta(i + 1, ('WHEN',))
            pila.append({'k': 'CASE', 'previas': [], 'actual': '', 'sel': sel.strip(), 'exc': False})
            desde = toks[j - 1][2] if j > i + 1 else e
            i = j; prev = 'CASE'
            continue
        elif W == 'BEGIN':
            corte(s)
            pila.append({'k': 'BEGIN', 'previas': [], 'actual': '', 'exc': False})
        elif W == 'EXCEPTION' and pila and pila[-1]['k'] == 'BEGIN':
            corte(s)
            pila[-1]['exc'] = True
        elif W == 'LOOP':
            corte(s)
            pila.append({'k': 'LOOP', 'previas': [], 'actual': '', 'exc': False})
        prev = W
        i += 1
    corte(len(masc))
    return len(masc), ramas


def catchall_verde(cuerpo):
    """Lista de (offset, literal) de los set_config('probe.*', '<verde para el runner>' ...) publicados
    dentro de un handler WHEN OTHERS cuyo CAMINO (IF/CASE que los encierran, y ramas previas si es un
    ELSE) no mira el error. Una condicion mira el error si menciona SQLSTATE, SQLERRM, RETURNED_SQLSTATE,
    MESSAGE_TEXT, un nombre de condicion de Postgres, o una variable que el handler cargo con el error
    (GET STACKED DIAGNOSTICS o := SQLSTATE/SQLERRM). Un handler anidado dentro de otro se cuenta una sola vez."""
    masc = _enmascarar(cuerpo)
    vistos = {}
    for h in WHEN_OTHERS.finditer(masc):
        fin, ramas = _escanear_handler(masc, h.end())
        vars_err = _vars_de_error(masc[h.end():fin])
        for s in SET_PROBE.finditer(cuerpo, h.end(), fin):
            if s.start() in vistos:
                continue
            lit = s.group(1).replace("''", "'")
            if not es_verde(lit):
                continue
            conds = next((c for a, b, c in ramas if a <= s.start() < b), [])
            if any(_mira_error(c, vars_err) for c in conds):
                continue
            vistos[s.start()] = lit.strip()
    return sorted(vistos.items())


def analizar(path):
    """Recorre el archivo llevando una pila de tags dollar-quoted. Todo lo que quede fuera de un
    bloque abierto es TOP-LEVEL. Un `DO $tag$` abre un bloque DO; el mismo `$tag$` lo cierra."""
    lineas = io.open(path, encoding='utf-8').read().split('\n')
    pila, do, top, blocks = [], None, [], []
    for i, l in enumerate(lineas, 1):
        s = re.sub(r'--.*$', '', l)              # los comentarios no cuentan
        for t in TAG.finditer(s):
            tag = t.group(0)
            if pila and pila[-1] == tag:
                pila.pop()
                if not pila and do is not None:
                    do[2] = i
                    blocks.append(tuple(do))
                    do = None
            else:
                if not pila and re.search(r'\bDO\s*$|\bDO\s*' + re.escape(tag), s[:t.end()], re.I):
                    do = [i, False, None]
                pila.append(tag)
        if not pila and DML.search(s) and not PGTEMP.search(s):
            top.append((i, l.strip()[:120]))
    # El handler y el cast se evaluan sobre el CUERPO COMPLETO (slice de lineas), NO linea a linea
    # mientras el bloque esta abierto: esa forma se perdia el handler de la linea de cierre y el de
    # los bloques de una sola linea. Ver tiene_handler() para las tres fallas y el caso simetrico.
    cast, resueltos = [], []
    for ini, _, fin in blocks:
        cuerpo = '\n'.join(re.sub(r'--.*$', '', x) for x in lineas[ini - 1:fin])
        h = tiene_handler(cuerpo)
        resueltos.append((ini, h, fin))
        if not h and CAST_DIRECTO.search(cuerpo):
            cast.append((ini, fin))
    return top, resueltos, cast


def catchall_del_archivo(path, blocks):
    """(linea, literal) de cada catch-all verde, sobre los mismos bloques DO que analizar()."""
    lineas = io.open(path, encoding='utf-8').read().split('\n')
    out = []
    for ini, _, fin in blocks:
        tramo = [re.sub(r'--.*$', '', x) for x in lineas[ini - 1:fin]]
        cuerpo = '\n'.join(tramo)
        for off, lit in catchall_verde(cuerpo):
            out.append((ini + cuerpo.count('\n', 0, off), lit))
    return out


def main():
    # --listar en cualquier posicion (review del censo, punto 7); el primer argumento que no sea opcion es el archivo
    listar = '--listar' in sys.argv[1:]
    args = [a for a in sys.argv[1:] if a != '--listar']
    path = args[0] if args else DEFAULT
    top, blocks, cast = analizar(path)
    sin_h = [b for b in blocks if not b[1]]
    cav = catchall_del_archivo(path, blocks)

    print('b2_guard — %s' % path)
    print('  top_level_dml_ddl : %d   (baseline %d)' % (len(top), BASELINE_TOP_LEVEL))
    print('  cast_directo      : %d   (baseline %d)  [bloques sin handler con current_setting()::T]'
          % (len(cast), BASELINE_CAST_DIRECTO))
    print('  do_sin_handler    : %d   (baseline %d)  [%d bloques DO en total]'
          % (len(sin_h), BASELINE_DO_SIN_HANDLER, len(blocks)))
    print('  catchall_verde    : %d   (baseline %d)  [WHEN OTHERS que publica un valor no rojo sin mirar el SQLSTATE]'
          % (len(cav), BASELINE_CATCHALL_VERDE))
    if listar:
        for n, lit in cav:
            print('     L%-6d %s' % (n, lit[:90]))

    fallo = False
    if len(cast) > BASELINE_CAST_DIRECTO:
        fallo = True
        print()
        print('  *** ROJO: %d bloque(s) nuevos con cast directo sobre current_setting ***'
              % (len(cast) - BASELINE_CAST_DIRECTO))
        print('  El harness setea cadenas vacias a proposito y \'\'::uuid es 22P02: mata la')
        print('  transaccion entera. Usa NULLIF(current_setting(\'x\', true), \'\')::T.')
        for ini, fin in cast[:10]:
            print('     bloque DO L%d-%d' % (ini, fin))
    if len(top) > BASELINE_TOP_LEVEL:
        fallo = True
        print()
        print('  *** ROJO: aparecieron %d sentencia(s) DML/DDL a nivel TOP-LEVEL ***'
              % (len(top) - BASELINE_TOP_LEVEL))
        print('  Una sentencia top-level que revienta MATA la transaccion entera y el harness no')
        print('  devuelve NADA. Envolvela en un DO con EXCEPTION handler que publique un veredicto')
        print('  visible (patron FX12-FX18), y si depende de un valor derivado, verifica la premisa')
        print('  ANTES de escribir en vez de escribir NULL.')
        for n, t in top:
            print('     L%-6d %s' % (n, t))
    if len(sin_h) > BASELINE_DO_SIN_HANDLER:
        fallo = True
        print()
        print('  *** ROJO: %d bloque(s) DO nuevos sin EXCEPTION handler ***'
              % (len(sin_h) - BASELINE_DO_SIN_HANDLER))
        print('  El baseline es deuda con fecha, no una licencia para agregar mas.')
    if len(cav) > BASELINE_CATCHALL_VERDE:
        fallo = True
        print()
        print('  *** ROJO: %d catch-all(s) verde(s) nuevo(s): WHEN OTHERS que publica verde para CUALQUIER error ***'
              % (len(cav) - BASELINE_CATCHALL_VERDE))
        print('  Un probe asi no distingue el rechazo que mide de una rotura (firma cambiada, 22P02 del fixture,')
        print('  deadlock): todo sale verde. Mira el SQLSTATE y el mensaje (GET STACKED DIAGNOSTICS, patron P1-P6)')
        print('  y publica FALLO en el resto. Lista completa: python tests/rls/b2_guard.py <archivo> --listar')

    if not fallo:
        bajo = []
        if len(top) < BASELINE_TOP_LEVEL:
            bajo.append('top_level_dml_ddl -> %d' % len(top))
        if len(cast) < BASELINE_CAST_DIRECTO:
            bajo.append('cast_directo -> %d' % len(cast))
        if len(sin_h) < BASELINE_DO_SIN_HANDLER:
            bajo.append('do_sin_handler -> %d' % len(sin_h))
        if len(cav) < BASELINE_CATCHALL_VERDE:
            bajo.append('catchall_verde -> %d' % len(cav))
        if bajo:
            print()
            print('  VERDE, y ademas BAJO: %s' % ', '.join(bajo))
            print('  Actualiza el baseline en b2_guard.py y en el comentario de P516.')
        else:
            print()
            print('  VERDE (ninguna metrica crecio)')
    return 1 if fallo else 0


if __name__ == '__main__':
    sys.exit(main())
