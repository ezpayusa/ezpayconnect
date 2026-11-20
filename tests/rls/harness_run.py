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

ANTES DE ENVIAR (desde el 20-oct-2026)
    La Management API corta el cuerpo de la consulta en ~3 MiB de JSON (413 request entity too
    large, medido el 20-oct con la 379). El runner manda una COPIA del harness sin las lineas que
    son solo comentario (primer caracter no blanco = '--'); el archivo en disco no cambia. Imprime
    los bytes antes y despues y las lineas quitadas, y aborta ANTES de enviar si el cuerpo pasa de
    LIMITE_BODY (2.9 MiB): el proximo limite tiene que avisar con margen, no dar un 413.

MODO PARTIDO (desde el 17-nov-2026, output/diseno-split-harness-17nov.md, opcion B)
    El cuerpo crece ~30 KB por migracion y el techo es por REQUEST. El archivo puede partirse con tres marcadores, cada
    uno en una linea EXACTA, sola y en la columna 0:
        -- @@HARNESS_PRELUDIO_FIN@@   fin del preludio (cabecera, BEGIN y precondicion global): se repite en cada parte
        -- @@HARNESS_PARTE@@          corte entre partes; K cortes = K+1 partes (puede no haber ninguno: 1 parte)
        -- @@HARNESS_RESULTADOS@@     desde aca hasta el final: el SELECT de veredictos, P000 y el ROLLBACK
    Se detectan sobre el texto ORIGINAL, ANTES de quitar los comentarios (son lineas de comentario a proposito: el .sql
    sigue siendo valido y quitar_comentarios_linea los borraria si se buscaran despues). Si el archivo no tiene NINGUN
    marcador, el runner hace exactamente lo de siempre: el mismo cuerpo, byte a byte, en un solo request.
    Con marcadores, cada parte es un request y una transaccion propios, en SERIE (nunca en paralelo):
        preludio + cuerpo de la parte + colector + ROLLBACK
    El colector devuelve el valor no vacio de cada clave 'probe.x' que lee el bloque de resultados (extraidas de su
    texto: hoy son todas literales). No se puede usar pg_settings: en PG 17 los placeholders de set_config no aparecen
    ahi (medido el 17-nov: 0 filas). Despues, UN request final repone esas claves con set_config y corre el bloque de
    resultados tal cual: mismas filas, mismo P000, mismos nombres que la corrida monolitica.
    Si una parte falla (exit del cliente, 413, SQL, techo, salida sin el centinela del colector) se registra una fila
    'PARTE_<n>_ERROR' con 'ROJO (...)' y se sigue con las demas; una clave con valores distintos en dos partes da la fila
    'PARTES_CONFLICTO'. Las dos estan fuera de la DEUDA: la corrida sale con exit 1. Piso, vacios y deuda se evaluan
    sobre el total (verificar() de siempre).

INYECCION DE UNA MIGRACION (dry-run)
    Hoy: se copia el harness, se pega el cuerpo de la migracion (sin su BEGIN/COMMIT) justo despues de la linea
    `BEGIN;` y se corre la copia con `-f`. Con marcadores es lo mismo: esa linea esta dentro del preludio, asi que la
    migracion queda al inicio de CADA parte. El request final no la necesita (solo lee settings).

USO
    npm run harness            # corre y verifica
    npm run harness -- -o x.json
    npm run harness -- -f copia.sql   # otro archivo (copia con migracion inyectada o con marcadores de prueba)
    npm run harness:selftest   # prueba que las verificaciones DISPARAN (no toca la base)
"""
import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HARNESS = os.path.join(REPO, 'tests', 'rls', 'probes_escritura.sql')

# Piso declarado. Medido el 2026-09-07 (tras la mig 289): el harness emite 733 filas. El piso NO
# persigue el numero exacto �agregar probes es normal y el numero sube solo�: ataja la corrida
# TRUNCADA o VACIA, que es un salto a ~0, no de a una. Por eso se deja holgura y no se sube a 733.
PISO_FILAS = 680

# ----------------------------------------------------------------------------------------------
# LA DEUDA: las rojas que HOY se aceptan, una por una y con su motivo.
# ----------------------------------------------------------------------------------------------
# Hasta ahora las rojas de deuda se comparaban "texto a texto" a mano en cada corrida. Eso
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
    # --- modulo comercial: aserciones de count(*) contaminadas por datos de produccion ---
    #
    # P472 y P476 SALIERON DE ESTA LISTA el 8-sep-2026. No se arreglo nada: se limpio el ruido.
    # Las dos hacian `count(*)` SIN WHERE sobre `prospectos` / `prospecto_contactos` �tablas que el
    # harness comparte con PRODUCCION� y exigian una cifra absoluta exacta (P472: admA=5 y el
    # string_agg literal 'A1,A2,A3,Rogue,SupA'; P476: super=2). Los 5 prospectos y 1 contacto QA
    # que se borraron en la limpieza del 8-sep inflaban esa cuenta �admA=10 y super=3 en la ultima
    # corrida roja�, asi que al borrarlos las aserciones se cumplen solas.
    # La propiedad de RLS que cada una mide se sigue probando igual: el aislamiento por pais en
    # P472 (las negativas sobre admB nunca dependieron de esas filas) y la herencia del gate del
    # prospecto en P476 (los terminos asA1=1 y medico=0 ya estaban verdes). El defecto no
    # desaparecio: desaparecio lo que lo tapaba.
    #
    # P473 SIGUE EN LA LISTA y comparte el MISMO defecto estructural que las otras dos: una
    # asercion de `count(*)` exacto sobre una tabla compartida con produccion es fragil por diseno.
    # Hoy esta roja porque el super_admin ve los 6 prospectos del fixture MAS los 9 del pais DEMO.
    # NOTA PARA QUIEN LO ENCUENTRE DESPUES: esto se va a volver a romper solo. P472 vuelve a rojo
    # el dia que exista un prospecto real en Guatemala; P476, el dia que exista un contacto real en
    # cualquier pais; P473, con cualquier prospecto nuevo en cualquier lado. El arreglo de fondo es
    # que las tres cuenten SOLO las filas del fixture (por nombre 'P264 %' o por los ids sembrados)
    # en vez de la tabla entera. No es para ahora.
    'P473_super_admin_ve_todos':     'cuenta TODOS los prospectos de la base, no solo los del fixture',
}


# Prefijos que hacen ROJA una fila. ROJO y FALLO de siempre; REGRESION, FUGA, LEAK y PERMITIDO desde el
# 6-oct-2026: el harness los publica como fallas (P45 'REGRESIÓN (P0001)', P146 'FUGA (...)', las negativas
# 'PERMITIDO (...)') y el runner los dejaba pasar en silencio porque solo miraba ROJO/FALLO.
# VISIBLE, ERROR y BLOQUEADO? desde la review del 6-oct-2026 (M1): P114/P127/P129/P133/P151/P159 publican
# 'VISIBLE (...!)' como fuga, P144/P146/P148_n 'ERROR (SQLSTATE)' y P33/P35/P44 'BLOQUEADO? (...)' cuando no
# hay evidencia de que el bloqueo fue el esperado. 'BLOQUEADO?' es un prefijo LITERAL (sin regex): un
# 'BLOQUEADO (42501)' no lo matchea porque despues de BLOQUEADO viene ' ' y no '?'.
PREFIJOS_ROJOS = ('ROJO', 'FALLO', 'REGRESION', 'FUGA', 'LEAK', 'PERMITIDO', 'VISIBLE', 'ERROR', 'BLOQUEADO?')


# Techo del cuerpo que se envia (bytes UTF-8 del SQL ya sin comentarios). La API corta en ~3 MiB de
# JSON (el SQL escapado pesa ~1-2 % mas); 2.9 MiB deja ese margen y avisa antes del 413.
LIMITE_BODY = int(2.9 * 1024 * 1024)


def motivo_cr(texto):
    """Gate de fin de línea (20-nov-2026): None si el cuerpo no trae CR; si trae, el mensaje de por qué NO se envía.

    Un cuerpo en CRLF cambia el md5(prosrc) de las funciones que crea un dry-run inyectado (el de la 396 anotó un md5
    que no era el de prod por eso). Todo lo que se manda a la base va con 0 CR.
    """
    n = texto.count('\r')
    if n == 0:
        return None
    return 'el cuerpo trae %d CR (fin de linea CRLF); no se envia nada a la base: convertir el archivo a LF' % n


def quitar_comentarios_linea(texto):
    """Quita SOLO las lineas cuyo primer caracter no blanco es '--'. Un comentario al final de una
    linea con codigo ('SELECT 1; -- x') queda intacto, igual que todo lo demas. Devuelve
    (texto_nuevo, lineas_quitadas)."""
    lineas = texto.splitlines(True)
    quedan = [l for l in lineas if not l.lstrip().startswith('--')]
    return ''.join(quedan), len(lineas) - len(quedan)


def tamano_ok(n_bytes):
    """True si el cuerpo entra bajo LIMITE_BODY."""
    return n_bytes <= LIMITE_BODY


# ---------------------------------------------- modo partido ----------------------------------------------
MARCA_PRELUDIO = '-- @@HARNESS_PRELUDIO_FIN@@'
MARCA_PARTE = '-- @@HARNESS_PARTE@@'
MARCA_RESULTADOS = '-- @@HARNESS_RESULTADOS@@'
MARCAS = (MARCA_PRELUDIO, MARCA_PARTE, MARCA_RESULTADOS)
# Fila centinela del colector: si no vuelve, la parte no llego a su final (o la API devolvio otro result set).
CENTINELA_COLECTOR = '__harness_parte__'
CLAVE_PROBE = re.compile(r"'(probe\.[A-Za-z0-9_]+)'")


def _es_marca(linea):
    """La linea, sin el fin de linea ni blancos FINALES, es exactamente un marcador. Con sangria NO cuenta: un
    marcador va en la columna 0, fuera de todo bloque."""
    return linea.rstrip('\r\n').rstrip(' \t') in MARCAS


def partir(texto):
    """None si el texto no tiene ningun marcador (modo de siempre). Si tiene, devuelve
    {'preludio': str, 'partes': [str, ...], 'resultados': str} con el texto ORIGINAL (comentarios incluidos; cada
    trozo se limpia despues). Lanza ValueError si los marcadores estan mal puestos."""
    lineas = texto.splitlines(True)
    pos = [(i, l.rstrip('\r\n').rstrip(' \t')) for i, l in enumerate(lineas) if _es_marca(l)]
    # Un marcador con sangria (o pegado a otra cosa) no se toma como marcador; se avisa para que no pase inadvertido.
    casi = [i + 1 for i, l in enumerate(lineas) if '@@HARNESS_' in l and not _es_marca(l)]
    if casi:
        raise ValueError('linea(s) %s mencionan @@HARNESS_ pero no son un marcador exacto en la columna 0' % casi)
    if not pos:
        return None
    pre = [i for i, m in pos if m == MARCA_PRELUDIO]
    res = [i for i, m in pos if m == MARCA_RESULTADOS]
    cortes = [i for i, m in pos if m == MARCA_PARTE]
    if len(pre) != 1 or len(res) != 1:
        raise ValueError('hace falta exactamente un %s y un %s (hay %d y %d)'
                         % (MARCA_PRELUDIO, MARCA_RESULTADOS, len(pre), len(res)))
    if not all(pre[0] < c < res[0] for c in cortes):
        raise ValueError('los %s tienen que estar entre %s y %s' % (MARCA_PARTE, MARCA_PRELUDIO, MARCA_RESULTADOS))
    # Cada marcador tiene que caer ENTRE sentencias: la ultima linea con codigo antes de el termina en ';'. Atrapa el
    # error tipico (un marcador pegado dentro de un DO) sin parsear dollar-quotes; el que se escape, lo ataja la base.
    for i, m in pos:
        previa = next((l for l in reversed(lineas[:i]) if l.strip() and not l.lstrip().startswith('--')), '')
        if not previa.split('--')[0].rstrip().endswith(';'):
            raise ValueError('el marcador %s de la linea %d no esta entre dos sentencias (la anterior no termina en ;)'
                             % (m, i + 1))
    limites = [pre[0]] + cortes + [res[0]]
    return {
        'preludio': ''.join(lineas[:pre[0]]),
        'partes': [''.join(lineas[limites[k] + 1:limites[k + 1]]) for k in range(len(limites) - 1)],
        'resultados': ''.join(lineas[res[0] + 1:]),
    }


def _literal(s):
    return "'" + s.replace("'", "''") + "'"


def claves_de_resultados(resultados):
    """Las claves 'probe.x' que lee el bloque de resultados, en orden de aparicion y sin repetir."""
    vistas, out = set(), []
    for k in CLAVE_PROBE.findall(resultados):
        if k not in vistas:
            vistas.add(k)
            out.append(k)
    return out


def colector(claves, n):
    """SQL que va al final de la parte n (antes del ROLLBACK): el centinela y cada clave con valor no vacio."""
    arr = ',\n'.join(_literal(k) for k in claves)
    return ("SELECT %s AS k, %s AS v\nUNION ALL\nSELECT c.k, current_setting(c.k, true)\n"
            "  FROM unnest(ARRAY[\n%s\n]::text[]) AS c(k)\n WHERE COALESCE(current_setting(c.k, true), '') <> '';\n"
            "ROLLBACK;\n" % (_literal(CENTINELA_COLECTOR), _literal(str(n)), arr))


def leer_colector(salida, n):
    """(dict clave->valor, error o None) a partir de la salida JSON de la parte n."""
    try:
        datos = json.loads(salida)
    except ValueError as e:
        return None, 'la salida no es JSON (%s)' % e
    filas = datos.get('rows') if isinstance(datos, dict) else datos
    if not isinstance(filas, list):
        return None, 'el JSON no trae filas'
    if not any(f.get('k') == CENTINELA_COLECTOR and str(f.get('v')) == str(n) for f in filas if isinstance(f, dict)):
        return None, 'sin el centinela del colector (la parte no llego a su final)'
    return {f['k']: f['v'] for f in filas if f.get('k') != CENTINELA_COLECTOR and f.get('v') not in (None, '')}, None


def fusionar(valores_por_parte):
    """Une los dict de cada parte. Una clave con el MISMO valor en varias partes (las del preludio) es normal; con
    valores distintos es un conflicto. Devuelve (valores, conflictos) con conflictos = [clave, ...]."""
    out, conflictos = {}, []
    for vals in valores_por_parte:
        for k, v in vals.items():
            if k in out and out[k] != v and k not in conflictos:
                conflictos.append(k)
            out[k] = v
    return out, conflictos


def cuerpo_final(valores, resultados_limpio):
    """Request final: repone las claves y corre el bloque de resultados tal cual (trae su ROLLBACK)."""
    if valores:
        filas = ',\n'.join('(%s, %s)' % (_literal(k), _literal(v)) for k, v in sorted(valores.items()))
        reponer = 'SELECT count(set_config(t.k, t.v, false)) FROM (VALUES\n%s\n) AS t(k, v);\n' % filas
    else:
        reponer = ''
    return 'BEGIN;\n' + reponer + resultados_limpio


def _md5(s):
    return hashlib.md5(s.encode('utf-8')).hexdigest()


def _sin_tildes(s):
    """'REGRESIÓN' -> 'REGRESION'. Solo quita marcas diacriticas (NFD + categoria Mn)."""
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def _rojas(filas):
    """ROJA = el verdict, con strip() y upper() y sin tildes, EMPIEZA con uno de PREFIJOS_ROJOS
    (ROJO, FALLO, REGRESION/REGRESIÓN, FUGA, LEAK, PERMITIDO, VISIBLE, ERROR, BLOQUEADO?). Por PREFIJO
    literal, nunca por subcadena ni regex: 'PERMITIDO', 'VISIBLE' o 'ERROR' aparecen dentro de textos que
    describen lo que la probe NO dejo pasar (p. ej. 'OK (... no PERMITIDO ...)', 'OK (no VISIBLE para
    anon)', 'BLOQUEADO (42501)'), y esos no son rojos."""
    out = []
    for f in filas:
        v = str(f.get('verdict') or '').strip()
        if _sin_tildes(v.upper()).startswith(PREFIJOS_ROJOS):
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

    # --- comentarios de linea completa y techo del cuerpo ---
    entrada = 'BEGIN;\n  -- x\n\t-- tab\n--pegado\nSELECT 1; -- x\nSELECT 2;\n'
    salida, n = quitar_comentarios_linea(entrada)
    casos_body = [
        ('"  -- x" (y con tab, y sin espacio) se quita', '  -- x' not in salida and '\t-- tab' not in salida and '--pegado' not in salida and n == 3),
        ('"SELECT 1; -- x" queda intacta', 'SELECT 1; -- x\n' in salida),
        ('el resto queda igual y en orden', salida == 'BEGIN;\nSELECT 1; -- x\nSELECT 2;\n'),
        ('cuerpo en el techo pasa', tamano_ok(LIMITE_BODY)),
        ('cuerpo sobre el techo aborta', not tamano_ok(LIMITE_BODY + 1)),
        ('gate de CR: cuerpo en LF pasa', motivo_cr('BEGIN;\nSELECT 1;\nROLLBACK;\n') is None),
        ('gate de CR: cuerpo en CRLF no se envia y cuenta los CR', (motivo_cr('BEGIN;\r\nSELECT 1;\r\n') or '').startswith('el cuerpo trae 2 CR')),
        ('gate de CR: un solo CR suelto tambien frena', motivo_cr('SELECT 1;\r') is not None),
    ]

    # --- modo partido: marcadores, colector, fusion y request final ---
    def _lanza(texto):
        try:
            partir(texto)
        except ValueError:
            return True
        return False
    base = ('BEGIN;\nDO $$ BEGIN PERFORM 1; END $$;\n' + MARCA_PRELUDIO + '\n'
            "SELECT set_config('probe.a','x',false);\n" + MARCA_PARTE + '\n'
            "SELECT set_config('probe.b','y',false);\n" + MARCA_RESULTADOS + '\n'
            "SELECT 'A', current_setting('probe.a', true) UNION ALL SELECT 'B', current_setting('probe.b', true);\nROLLBACK;\n")
    t = partir(base)
    sin_marcas = 'BEGIN;\n-- @@ algo que no es marcador\nSELECT 1;\nROLLBACK;\n'
    vals, err = leer_colector(json.dumps({'rows': [{'k': CENTINELA_COLECTOR, 'v': '2'}, {'k': 'probe.a', 'v': "it's"},
                                                   {'k': 'probe.z', 'v': ''}]}), 2)
    _, err_sin_centinela = leer_colector(json.dumps({'rows': [{'set_config': ''}]}), 1)
    _, err_otra_parte = leer_colector(json.dumps({'rows': [{'k': CENTINELA_COLECTOR, 'v': '1'}]}), 2)
    fus, conf = fusionar([{'probe.pre': 'OK', 'probe.a': '1'}, {'probe.pre': 'OK', 'probe.b': '2'}])
    _, conf2 = fusionar([{'probe.a': '1'}, {'probe.a': '2'}])
    fin = cuerpo_final({'probe.a': "o'k"}, 'SELECT 1;\nROLLBACK;\n')
    casos_partes = [
        ('sin marcadores -> None (modo de siempre)', partir(sin_marcas) is None),
        ('preludio + 1 corte + resultados -> 2 partes', t is not None and len(t['partes']) == 2),
        ('el preludio llega hasta el marcador y trae el BEGIN', t['preludio'].startswith('BEGIN;') and MARCA_PRELUDIO not in t['preludio']),
        ('cada parte tiene solo su cuerpo', "probe.a" in t['partes'][0] and "probe.b" not in t['partes'][0] and "probe.b" in t['partes'][1]),
        ('resultados = desde el marcador hasta el final', t['resultados'].startswith("SELECT 'A'") and t['resultados'].endswith('ROLLBACK;\n')),
        ('sin cortes (solo preludio y resultados) -> 1 parte', len(partir(base.replace(MARCA_PARTE + '\n', ''))['partes']) == 1),
        ('marcador con sangria -> error', _lanza(base.replace('\n' + MARCA_PARTE, '\n  ' + MARCA_PARTE))),
        ('corte sin preludio -> error', _lanza(base.replace(MARCA_PRELUDIO + '\n', ''))),
        ('dos marcadores de resultados -> error', _lanza(base + MARCA_RESULTADOS + '\n')),
        ('corte despues de resultados -> error', _lanza(base + MARCA_PARTE + '\n')),
        ('corte dentro de una sentencia -> error', _lanza(base.replace("'y',false);\n" + MARCA_RESULTADOS, "'y',false)\n" + MARCA_RESULTADOS))),
        ('claves del bloque de resultados, sin repetir', claves_de_resultados(t['resultados']) == ['probe.a', 'probe.b']),
        ('colector: centinela, comillas escapadas y ROLLBACK', "'__harness_parte__'" in colector(["probe.o'x"], 3) and "'probe.o''x'" in colector(["probe.o'x"], 3) and colector([], 1).endswith('ROLLBACK;\n')),
        ('colector leido: sin el centinela ni los vacios', err is None and vals == {'probe.a': "it's"}),
        ('colector sin centinela -> error de la parte', err_sin_centinela is not None),
        ('colector con el centinela de OTRA parte -> error', err_otra_parte is not None),
        ('fusion: mismo valor en dos partes no es conflicto', conf == [] and fus == {'probe.pre': 'OK', 'probe.a': '1', 'probe.b': '2'}),
        ('fusion: valores distintos -> conflicto', conf2 == ['probe.a']),
        ('request final: BEGIN, set_config escapado y el bloque tal cual', fin.startswith('BEGIN;\n') and "('probe.a', 'o''k')" in fin and fin.endswith('SELECT 1;\nROLLBACK;\n')),
        ('una fila PARTE_n_ERROR hace la corrida ROJA', not verificar(0, json.dumps({'rows': _sana() + [{'probe': 'PARTE_2_ERROR', 'verdict': 'ROJO (exit 1)'}]}))[0]),
    ]
    casos_body += casos_partes
    for nombre, ok in casos_body:
        if ok:
            print('  ok   %s' % nombre)
        else:
            fallos.append(nombre)
    print()
    total = len(casos) + len(casos_body)
    if fallos:
        print('*** %d CASO(S) FALLARON ***' % len(fallos))
        for f in fallos:
            print('   - %s' % f)
        return 1
    print('TODOS LOS CASOS PASAN (%d)' % total)
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
    def enviar(cuerpo):
        """Un request: escribe el cuerpo en un temporal y corre el cliente. Devuelve (rc, stdout, stderr)."""
        # Defensa por request (cada parte y el final): con CR no se corre el cliente.
        m = motivo_cr(cuerpo)
        if m:
            return 97, '', m
        fd, tmp = tempfile.mkstemp(prefix='harness_body_', suffix='.sql')
        try:
            with io.open(fd, 'w', encoding='utf-8', newline='') as fh:
                fh.write(cuerpo)
            p = subprocess.run([exe, '--workdir', REPO, 'db', 'query', '--output', 'json',
                                '--linked', '-f', tmp],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=entorno)
        finally:
            os.remove(tmp)
        return p.returncode, p.stdout.decode('utf-8', 'replace'), p.stderr.decode('utf-8', 'replace')

    # Cuerpo a enviar: el harness sin las lineas que son solo comentario (el archivo no cambia).
    with io.open(a.file, 'r', encoding='utf-8', newline='') as fh:
        original = fh.read()
    # Gate de CR sobre el archivo entero, ANTES de partir o enviar nada (newline='' conserva los CR tal cual).
    m = motivo_cr(original)
    if m:
        print('ROJO: %s. La corrida NO se envio.' % m)
        return 1
    try:
        trozos = partir(original)
    except ValueError as e:
        print('ROJO: marcadores de parte mal puestos: %s. La corrida NO se envio.' % e)
        return 1

    if trozos is None:
        # ---- modo de siempre: un request con el archivo entero, byte a byte igual que antes del split ----
        cuerpo, quitadas = quitar_comentarios_linea(original)
        b_antes, b_despues = len(original.encode('utf-8')), len(cuerpo.encode('utf-8'))
        print('body: %d bytes -> %d bytes (%d lineas de comentario quitadas; techo %d)'
              % (b_antes, b_despues, quitadas, LIMITE_BODY))
        print('body md5 %s (un solo request, sin marcadores de parte)' % _md5(cuerpo))
        if not tamano_ok(b_despues):
            print('ROJO: el cuerpo sin comentarios pesa %d bytes y pasa el techo de %d (2.9 MiB).\n'
                  '      La API corta en ~3 MiB (413). La corrida NO se envio: achicar el harness o\n'
                  '      partirlo antes de seguir.' % (b_despues, LIMITE_BODY))
            return 1
        rc, salida, stderr = enviar(cuerpo)
    else:
        # ---- modo partido: una transaccion por parte, en serie, y un request final con los veredictos ----
        preludio, _ = quitar_comentarios_linea(trozos['preludio'])
        resultados, _ = quitar_comentarios_linea(trozos['resultados'])
        claves = claves_de_resultados(resultados)
        print('modo partido: %d parte(s); %d claves de veredicto en el bloque de resultados; techo %d por request'
              % (len(trozos['partes']), len(claves), LIMITE_BODY))
        errores, valores_por_parte = [], []
        for n, texto in enumerate(trozos['partes'], 1):
            cuerpo_n = preludio + quitar_comentarios_linea(texto)[0] + colector(claves, n)
            b = len(cuerpo_n.encode('utf-8'))
            print('  parte %d: %d bytes, margen %d (%.0f%%), md5 %s'
                  % (n, b, LIMITE_BODY - b, 100.0 * (LIMITE_BODY - b) / LIMITE_BODY, _md5(cuerpo_n)))
            if not tamano_ok(b):
                errores.append(('PARTE_%d_ERROR' % n, 'ROJO (pasa el techo: %d > %d; no se envio)' % (b, LIMITE_BODY)))
                continue
            rc_n, out_n, err_n = enviar(cuerpo_n)
            if rc_n != 0:
                errores.append(('PARTE_%d_ERROR' % n, 'ROJO (el cliente salio con exit %d: %s)'
                                % (rc_n, ' '.join(err_n.split())[-300:])))
                continue
            vals, err = leer_colector(out_n, n)
            if err:
                errores.append(('PARTE_%d_ERROR' % n, 'ROJO (%s)' % err))
                continue
            print('           %d clave(s) con valor' % len(vals))
            valores_por_parte.append(vals)
        valores, conflictos = fusionar(valores_por_parte)
        if conflictos:
            errores.append(('PARTES_CONFLICTO', 'ROJO (%d clave(s) con valores distintos en dos partes: %s)'
                            % (len(conflictos), ', '.join(conflictos[:20]))))
        final = cuerpo_final(valores, resultados)
        b = len(final.encode('utf-8'))
        print('  final  : %d bytes, margen %d, md5 %s (%d claves repuestas)' % (b, LIMITE_BODY - b, _md5(final), len(valores)))
        if not tamano_ok(b):
            print('ROJO: el request final pasa el techo (%d > %d). La corrida NO se completo.' % (b, LIMITE_BODY))
            return 1
        rc, salida, stderr = enviar(final)
        # Las filas de error de las partes se suman a las del request final: verificar() las ve como rojas fuera de la
        # deuda (exit 1), y el piso y la deuda se evaluan sobre el total.
        if rc == 0 and errores:
            try:
                datos = json.loads(salida)
                filas_f = datos.get('rows') if isinstance(datos, dict) else datos
                filas_f = list(filas_f) + [{'probe': p, 'verdict': v, 'esperado_post_fix': 'parte sin errores'}
                                           for p, v in errores]
                salida = json.dumps({'rows': filas_f}, ensure_ascii=False)
            except (ValueError, TypeError, AttributeError):
                pass  # salida invalida: verificar() la rechaza igual
        for p_, v_ in errores:
            print('  %s %s' % (p_, v_))

    ok, msg, filas = verificar(rc, salida)
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
        err = stderr.strip()
        if err:
            print('--- stderr del cliente ---')
            print(err[:1200])
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
