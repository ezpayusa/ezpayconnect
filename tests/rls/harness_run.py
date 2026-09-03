#!/usr/bin/env python3
"""
harness_run.py — CORREDOR DEL HARNESS DE RLS, CON PISO DE FILAS

POR QUE EXISTE
--------------
El harness se corria a mano con `supabase db query --linked -f ...`, y el 2026-09-03 una corrida
devolvio **exit 0 con la salida VACIA** por un corte transitorio del cliente. Para cualquiera que
lea el exit code — una sesion futura, un hook, un CI — eso es indistinguible de un harness verde.
Es exactamente el defecto que el frente B2 existe para eliminar: el harness corre en UNA
transaccion, asi que "sin salida" ya significaba "algo murio", y ahora ademas puede significar
"se corto la conexion". Dos causas distintas, la misma pantalla en blanco, y ninguna da rojo.

Este runner convierte esa ambiguedad en un rojo explicito con mensaje propio.

QUE VERIFICA, EN ORDEN
    1. exit code del cliente
    2. salida no vacia (0 bytes = ROJO, con su propio texto)
    3. JSON parseable (una salida truncada no se lee como exito)
    4. filas >= PISO_FILAS
    5. veredictos vacios (redundante con el centinela P000, a proposito: si el que muere es el
       propio P000, el runner igual lo ve)

USO
    npm run harness            # corre y verifica
    npm run harness -- -o x.json
    npm run harness:selftest   # prueba que las verificaciones DISPARAN (no toca la base)
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HARNESS = os.path.join(REPO, 'tests', 'rls', 'probes_escritura.sql')

# Piso declarado. Al 2026-09-03 el harness emite 564 filas. El piso no persigue el numero exacto
# (agregar probes es normal); ataja la corrida TRUNCADA o VACIA, que es un salto a ~0, no de a una.
PISO_FILAS = 550


def verificar(rc, salida):
    """Devuelve (ok, mensaje, filas). Pura: no toca la red — por eso el self-test puede probarla."""
    if rc != 0:
        return False, 'ROJO: el cliente salio con exit %d' % rc, None
    if not salida or not salida.strip():
        return (False,
                'ROJO: SALIDA VACIA (0 bytes) con exit %d.\n'
                '      El harness corre en UNA transaccion: esto es una corrida MUERTA o CORTADA,\n'
                '      NO un harness verde. Volve a correrlo; si se repite, el problema es el SQL.' % rc,
                None)
    try:
        datos = json.loads(salida)
    except ValueError as e:
        return False, 'ROJO: la salida no es JSON valido (%s). Probable corte a mitad de stream.' % e, None
    filas = datos.get('rows') if isinstance(datos, dict) else datos
    if not isinstance(filas, list):
        return False, 'ROJO: el JSON no trae una lista de filas.', None
    if len(filas) < PISO_FILAS:
        return (False,
                'ROJO: %d filas, por debajo del piso declarado (%d).\n'
                '      Una corrida parcial se lee como verde si nadie cuenta las filas.'
                % (len(filas), PISO_FILAS), len(filas))
    vacios = [f.get('probe') for f in filas if not str(f.get('verdict') or '').strip()]
    if vacios:
        return (False, 'ROJO: %d veredicto(s) VACIO(s): %s' % (len(vacios), ', '.join(vacios[:8])), len(filas))
    return True, 'VERDE: %d filas, 0 vacios (piso %d)' % (len(filas), PISO_FILAS), len(filas)


def self_test():
    """Prueba que las verificaciones DISPARAN. Sin esto, el runner es una promesa sin evidencia."""
    casos = [
        ('salida vacia con exit 0 (el caso real del 2026-09-03)', 0, '', False),
        ('exit distinto de cero', 1, '{"rows":[]}', False),
        ('JSON truncado a mitad de stream', 0, '{"rows":[{"probe":"P1",', False),
        ('menos filas que el piso', 0, json.dumps({'rows': [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(10)]}), False),
        ('un veredicto vacio', 0, json.dumps({'rows': [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(PISO_FILAS)] + [{'probe': 'PX', 'verdict': ''}]}), False),
        ('corrida sana', 0, json.dumps({'rows': [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(PISO_FILAS)]}), True),
    ]
    fallos = []
    for nombre, rc, out, espera in casos:
        ok, msg, _ = verificar(rc, out)
        if ok != espera:
            fallos.append('%s: ok=%s, se esperaba %s (%s)' % (nombre, ok, espera, msg.splitlines()[0]))
        else:
            print('  ok   %s -> %s' % (nombre, msg.splitlines()[0][:60]))
    print()
    if fallos:
        print('*** %d CASO(S) FALLARON ***' % len(fallos))
        for f in fallos:
            print('   - %s' % f)
        return 1
    print('TODOS LOS CASOS PASAN (%d)' % len(casos))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', help='guardar el JSON crudo en este archivo')
    ap.add_argument('-f', '--file', default=HARNESS)
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    if a.self_test:
        return self_test()

    # CreateProcess (Windows) NO aplica PATHEXT, asi que 'supabase' a secas no resuelve al .CMD que
    # instala npm: en bash anda y desde Python revienta. shutil.which si lo resuelve.
    exe = shutil.which('supabase')
    if not exe:
        print('ROJO: no se encontro el cliente `supabase` en el PATH. La corrida NO ocurrio.')
        return 1
    p = subprocess.run([exe, '--workdir', REPO, 'db', 'query', '--linked', '-f', a.file],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    salida = p.stdout.decode('utf-8', 'replace')
    ok, msg, filas = verificar(p.returncode, salida)
    if a.out and salida:
        io.open(a.out, 'w', encoding='utf-8').write(salida)
    print(msg)
    if not ok:
        err = p.stderr.decode('utf-8', 'replace').strip()
        if err:
            print('--- stderr del cliente ---')
            print(err[:1200])
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
