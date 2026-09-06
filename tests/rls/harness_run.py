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

# Piso declarado. Al 2026-09-06 el harness emite 688 filas. El piso no persigue el numero exacto
# (agregar probes es normal); ataja la corrida TRUNCADA o VACIA, que es un salto a ~0, no de a una.
PISO_FILAS = 680

# ----------------------------------------------------------------------------------------------
# LA DEUDA: las rojas que HOY se aceptan, una por una y con su motivo.
# ----------------------------------------------------------------------------------------------
# Hasta ahora las 13 rojas de deuda se comparaban "texto a texto" a mano en cada corrida. Eso
# funciona mientras alguien lo haga, y deja de funcionar el dia que no. Aca la lista es dato del
# programa: una roja NUEVA rompe la corrida, y una roja de la lista que se ponga VERDE tambien
# —porque o se arreglo (y hay que sacarla) o alguien la anestesio (y hay que enterarse)—.
#
# Los nombres son el campo `probe` del JSON, copiados de una corrida real. Si una probe se
# renombra, esta lista deja de coincidir y el runner lo dice: es el efecto buscado.
DEUDA = {
    # --- frente de despacho / farmacia (previo al modulo comercial) ---
    'P163_bandeja_aislamiento':      'bandeja de recetas entrantes: aislamiento incompleto',
    'P209_farmed_proveedor_anon':    'farmacias-medicamentos visibles a anon',
    'P222_farmacias_anon':           'policy anon vestigial sobre farmacias',
    # --- frente de notificaciones / PHI ---
    'P411_evt4fold_push_x2':         'evento 4-fold: push duplicado al paciente',
    'P414_helper_estructural_6rpc':  'notificar_visita_resultado no pasa por el helper',
    # --- frente de buzon (confinamiento por empresa) ---
    'Pbuz_lista_confinada':          'buzon: la lista no queda confinada',
    'Pbuz_detalle_confinado':        'buzon: el detalle no queda confinado',
    # --- frente de QR / preview de receta ---
    'Pqr_preview_confinable':        'preview de receta por QR: confinamiento',
    'Pqr_preview_exento':            'preview de receta por QR: caso exento',
    'Pqr_preview_grandfather':       'preview de receta por QR: caso grandfather',
    # --- modulo comercial: scope de admin_pais sobre prospectos ---
    'P472_admin_pais_scope':         'admin_pais ve prospectos de mas de los suyos',
    'P473_super_admin_ve_todos':     'super_admin ve todos los prospectos (contraparte de P472)',
    'P476_contactos_heredan_gate':   'los contactos no heredan el gate del prospecto',
    # --- modulo comercial: pendiente conocido, NO un descubrimiento ---
    'P625_co_DOBLE_checkout_doc':    'doble checkout sin guard — pendiente #3 del modulo comercial',
}


def _rojas(filas):
    """ROJA = el verdict, con strip(), empieza con ROJO o FALLO. Nada de subcadenas sueltas:
    'PERMITIO' aparece dentro de textos que describen lo que la probe NO dejo pasar."""
    out = []
    for f in filas:
        v = str(f.get('verdict') or '').strip()
        if v.upper().startswith('ROJO') or v.upper().startswith('FALLO'):
            out.append((str(f.get('probe') or '?'), v))
    return out


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
    if salida.lstrip()[:1] in ('\u250c', '\u2502', '\u251c', '\u2514'):
        # Diagnostico propio: "no es JSON valido" mandaba a buscar un corte de stream que no existia.
        return (False,
                'ROJO: el cliente devolvio una TABLA, no JSON. El runner pide --output json; si esto\n'
                '      aparece, el flag se perdio o el CLI lo ignora. NO es un corte de stream.',
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

    # --- clasificacion de rojas contra la deuda ---
    rojas = _rojas(filas)
    nombres = set(n for n, _ in rojas)
    fuera = sorted(n for n in nombres if n not in DEUDA)
    if fuera:
        return (False,
                'ROJO: %d roja(s) FUERA de la deuda: %s' % (len(fuera), ', '.join(fuera)),
                len(filas))
    verdes = sorted(n for n in DEUDA if n not in nombres)
    if verdes:
        return (False,
                'ROJO: deuda que salio VERDE (arreglada o anestesiada — actualizar la lista a '
                'proposito): %s' % ', '.join(verdes),
                len(filas))
    return (True,
            'VERDE: %d filas, 0 vacios (piso %d): %d rojas, todas en la deuda (%d)'
            % (len(filas), PISO_FILAS, len(rojas), len(DEUDA)),
            len(filas))


def _sana(omitir=None):
    """Una corrida sintetica que cumple todo: piso de filas, ningun vacio, y como rojas EXACTAMENTE
    las de la deuda. `omitir` deja una entrada de la deuda en verde, para el caso que lo prueba."""
    filas = [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(PISO_FILAS)]
    for nombre in DEUDA:
        filas.append({'probe': nombre, 'verdict': 'OK (arreglada)' if nombre == omitir else 'ROJO (deuda conocida)'})
    return filas


def self_test():
    """Prueba que las verificaciones DISPARAN. Sin esto, el runner es una promesa sin evidencia."""
    casos = [
        ('salida vacia con exit 0 (el caso real del 2026-09-03)', 0, '', False),
        ('exit distinto de cero', 1, '{"rows":[]}', False),
        ('JSON truncado a mitad de stream', 0, '{"rows":[{"probe":"P1",', False),
        ('salida en formato tabla (sin --output json)', 0,
         '\u250c\u2500\u2500\u2500\u2510\n\u2502 x \u2502\n\u251c\u2500\u2500\u2500\u2524\n\u2502 1 \u2502\n\u2514\u2500\u2500\u2500\u2518', False),
        ('menos filas que el piso', 0, json.dumps({'rows': [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(10)]}), False),
        ('un veredicto vacio', 0, json.dumps({'rows': [{'probe': 'P%d' % i, 'verdict': 'OK'} for i in range(PISO_FILAS)] + [{'probe': 'PX', 'verdict': ''}]}), False),
        ('corrida sana', 0, json.dumps({'rows': _sana()}), True),
        ('roja fuera de la deuda', 0, json.dumps({'rows': _sana() + [{'probe': 'P999_nueva', 'verdict': 'ROJO (algo)'}]}), False),
        ('deuda que salio verde', 0, json.dumps({'rows': _sana(omitir='P222_farmacias_anon')}), False),
        ('rojas exactamente las de la deuda', 0, json.dumps({'rows': _sana()}), True),
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
    # stdout de Windows redirigido a un pipe usa cp1252: los veredictos con '∅' o acentos raros
    # lanzarian UnicodeEncodeError. Se reemplaza el caracter; perder un simbolo es aceptable,
    # perder una fila de la lista de rojas no lo es.
    try:
        sys.stdout.reconfigure(errors='replace')
    except (AttributeError, ValueError):
        pass

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
    # El CLI 2.100 escribe ~/.supabase/telemetry.json ANTES de hacer nada y muere con EPERM en
    # sandboxes sin escritura fuera del repo: la corrida no ocurria y parecia un fallo de SQL.
    # Estas dos variables lo apagan, y van en el env del SUBPROCESO, no en el del runner.
    entorno = dict(os.environ, SUPABASE_TELEMETRY_DISABLED='1', DO_NOT_TRACK='1')
    # --output json EXPLICITO: sin el flag el CLI 2.100 decide el formato por entorno (detecta si
    # lo corre un agente) y en una shell limpia imprime una TABLA con bordes que este runner
    # rechazaba como "no es JSON valido".
    p = subprocess.run([exe, '--workdir', REPO, 'db', 'query', '--output', 'json',
                        '--linked', '-f', a.file],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=entorno)
    salida = p.stdout.decode('utf-8', 'replace')
    ok, msg, filas = verificar(p.returncode, salida)
    if a.out and salida:
        io.open(a.out, 'w', encoding='utf-8').write(salida)

    # Las rojas se imprimen SIEMPRE, antes del veredicto. Que el runner las liste es lo que hace
    # que nadie tenga que armar el resumen a mano y presentarlo como si lo hubiera dicho el programa.
    if filas:
        try:
            datos = json.loads(salida)
        except ValueError:
            datos = None
        # El try envuelve SOLO el json.loads. Cuando envolvia tambien la impresion, se comia el
        # UnicodeEncodeError de la primera linea con un caracter fuera de cp1252 (el harness usa
        # '∅') y el runner imprimia 8 de 13 rojas SIN decir nada: exactamente la clase de silencio
        # que este runner existe para eliminar. UnicodeEncodeError hereda de ValueError.
        if datos is not None:
            rojas = _rojas(datos.get('rows') if isinstance(datos, dict) else datos)
            print('--- %d roja(s) ---' % len(rojas))
            for nombre, v in sorted(rojas):
                marca = ' ' if nombre in DEUDA else '!'
                print('  %s %-38s %s' % (marca, nombre, v[:100]))
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
