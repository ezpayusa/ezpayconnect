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

Este script cuenta tres cosas sobre el propio archivo y falla (exit 1) si alguna CRECE.

POR QUE ES UN SCRIPT Y NO UN PROBE
-----------------------------------
Un probe no puede leer su propio fuente: pg_read_file() lee del SERVIDOR y exige superusuario o
pg_read_server_files, y este archivo vive en la maquina del cliente. P516 dentro del harness solo
PUBLICA el baseline para que quien lea la salida sepa que este gate existe; el que cuenta es este.

LAS TRES METRICAS
----------------
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

USO
---
    python tests/rls/b2_guard.py            # sobre tests/rls/probes_escritura.sql
    python tests/rls/b2_guard.py <archivo>  # sobre otro (util para la copia de scratch)
    npm run harness:guard

Sale 0 si ninguna metrica crecio, 1 si alguna crecio. Si BAJAN, lo dice y recuerda actualizar el
baseline en este archivo y en P516.
"""
import io
import re
import sys

# ============================== BASELINE DECLARADO ==============================
# Al bajar una metrica, actualizar ACA y en el comentario de P516 del harness, EN EL MISMO COMMIT
# que la baja. Un baseline que se actualiza "despues" es un baseline que alguien olvida.
BASELINE_TOP_LEVEL = 0            # fase 1 de B2 (2026-09-03), CERRADO
BASELINE_CAST_DIRECTO = 0         # fase 2.1 CERRADA (155 -> 103 -> 51 -> 0, tres tandas)
BASELINE_DO_SIN_HANDLER = 211     # CORREGIDO 2026-09-03: el 319 anterior estaba inflado en 108
                                  # por tres fallas del detector. fase 2.2: 211 -> ~156
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


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    top, blocks, cast = analizar(path)
    sin_h = [b for b in blocks if not b[1]]

    print('b2_guard — %s' % path)
    print('  top_level_dml_ddl : %d   (baseline %d)' % (len(top), BASELINE_TOP_LEVEL))
    print('  cast_directo      : %d   (baseline %d)  [bloques sin handler con current_setting()::T]'
          % (len(cast), BASELINE_CAST_DIRECTO))
    print('  do_sin_handler    : %d   (baseline %d)  [%d bloques DO en total]'
          % (len(sin_h), BASELINE_DO_SIN_HANDLER, len(blocks)))

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

    if not fallo:
        bajo = []
        if len(top) < BASELINE_TOP_LEVEL:
            bajo.append('top_level_dml_ddl -> %d' % len(top))
        if len(cast) < BASELINE_CAST_DIRECTO:
            bajo.append('cast_directo -> %d' % len(cast))
        if len(sin_h) < BASELINE_DO_SIN_HANDLER:
            bajo.append('do_sin_handler -> %d' % len(sin_h))
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
