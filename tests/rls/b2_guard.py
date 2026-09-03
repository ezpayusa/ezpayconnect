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

Este script cuenta dos cosas sobre el propio archivo y falla (exit 1) si alguna CRECE.

POR QUE ES UN SCRIPT Y NO UN PROBE
-----------------------------------
Un probe no puede leer su propio fuente: pg_read_file() lee del SERVIDOR y exige superusuario o
pg_read_server_files, y este archivo vive en la maquina del cliente. P516 dentro del harness solo
PUBLICA el baseline para que quien lea la salida sepa que este gate existe; el que cuenta es este.

LAS DOS METRICAS
----------------
1) top_level_dml_ddl — sentencias DML/DDL fuera de todo bloque DO.
   Baseline 0. La fase 1 de B2 envolvio las 14 que quedaban (FX12-FX18).
   EXCLUSION documentada: `CREATE ... pg_temp.*`. Es DDL transaccional sobre un schema temporal, no
   puede corromper ningun fixture y desaparece con el ROLLBACK. Hoy hay exactamente una: la funcion
   del censo que consumen P480/P481.

2) do_sin_handler — bloques DO sin `EXCEPTION WHEN`.
   Baseline 319. DEUDA CON FECHA, igual que la allowlist del centinela P480: la ataca la FASE 2 de
   B2. Que este en el baseline no dice "esta bien", dice "esta contado y tiene fase asignada".
   REGLA ESTRICTA: `RAISE EXCEPTION` NO cuenta como handler — es lo contrario de un handler. Contarlo
   daria 298 y estaria mal. Esta distincion importa: el 209 que figuraba en el diagnostico de la
   fase A no se pudo reproducir con ninguna regla, asi que el baseline se re-fundo aca, con la regla
   escrita y un parser que reproduce exactamente las 18 sentencias top-level del archivo previo al
   paquete (commit 2386d75). Un baseline que nadie puede recomputar no sirve de gate.

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
# Al bajar una metrica, actualizar ACA y en el comentario de P516 del harness.
BASELINE_TOP_LEVEL = 0      # fase 1 de B2 (2026-09-03)
BASELINE_DO_SIN_HANDLER = 319    # deuda con fecha: la ataca la fase 2
# ===============================================================================

DEFAULT = 'tests/rls/probes_escritura.sql'
TAG = re.compile(r'\$([a-zA-Z_][a-zA-Z0-9_]*)?\$')
DML = re.compile(
    r'^\s*(UPDATE|INSERT|DELETE|ALTER\s+TABLE|CREATE\s+(?:OR\s+REPLACE\s+)?'
    r'(?:FUNCTION|TABLE|INDEX)|DROP|TRUNCATE|GRANT|REVOKE)\b', re.I)
PGTEMP = re.compile(r'\bpg_temp\.', re.I)


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
                    blocks.append(tuple(do))
                    do = None
            else:
                if not pila and re.search(r'\bDO\s*$|\bDO\s*' + re.escape(tag), s[:t.end()], re.I):
                    do = [i, False]
                pila.append(tag)
        if pila and do is not None and re.search(r'\bEXCEPTION\s+WHEN\b', s, re.I):
            do[1] = True
        if not pila and DML.search(s) and not PGTEMP.search(s):
            top.append((i, l.strip()[:120]))
    return top, blocks


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    top, blocks = analizar(path)
    sin_h = [b for b in blocks if not b[1]]

    print('b2_guard — %s' % path)
    print('  top_level_dml_ddl : %d   (baseline %d)' % (len(top), BASELINE_TOP_LEVEL))
    print('  do_sin_handler    : %d   (baseline %d)  [%d bloques DO en total]'
          % (len(sin_h), BASELINE_DO_SIN_HANDLER, len(blocks)))

    fallo = False
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
