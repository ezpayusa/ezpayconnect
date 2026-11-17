#!/usr/bin/env python3
"""
comparar_corridas.py — COMPARA DOS CORRIDAS DEL HARNESS POR VEREDICTO (paso 1 del split)

POR QUE EXISTE
--------------
El harness va a partirse en varios requests (output/diseno-split-harness-17nov.md). Partirlo cambia una cosa que el
analisis estatico no ve: lo que una parte escribe y no deshace deja de verlo la siguiente. La unica forma de saber si
eso movio algun veredicto es comparar una corrida partida contra una monolitica. Este script es esa comparacion, y
sirve igual para cualquier par de corridas (por ejemplo, pre y post de una migracion).

QUE COMPARA
-----------
Por NOMBRE de probe, no por orden (en la corrida partida las filas salen agrupadas por parte):
    1. probes que faltan o sobran de cada lado (salvo P000, ver abajo) y nombres duplicados ....... exit 1
    2. cambio de CLASE de veredicto ............................................................. exit 1
       clase = el prefijo rojo que matchea (PREFIJOS_ROJOS de harness_run.py, la MISMA regla del runner), o si no es
       rojo, el primer token del veredicto (OK, OK-SENAL, N/A, BLOQUEADO, PENDIENTE, DET, ...). Un OK que pasa a
       'N/A (fixture ...)' es un cambio de clase: es la forma tipica de "perdi un fixture" y no da rojo por si sola.
    3. misma clase y texto distinto DESPUES de normalizar (uuid, timestamps, hex de 8 y numeros):
         - si el probe esta en ACEPTADOS_TEXTO (ruido conocido) ...................................... aceptado
         - si no .................................................................................... exit 1
P000 (centinela anti-null): la monolitica tiene UNA fila 'P000_CENTINELA...'; la partida, una por parte. Cada P000 del
lado B se compara en clase contra el del lado A, y el conteo 'N veredictos' se SUMA por lado: tiene que coincidir.

ENTRADA
-------
Lo que guarda `npm run harness -- -o <archivo>`: el JSON crudo del cliente, {"rows": [...]} o una lista de filas, con
los campos `probe` y `verdict`.

USO
---
    python tests/rls/comparar_corridas.py A.txt B.txt
    python tests/rls/comparar_corridas.py A.txt B.txt --aceptar-texto P948,P1009,DET_p1009
--aceptar-texto suma prefijos a ACEPTADOS_TEXTO SOLO para esa ejecucion (la lista del archivo no cambia). Es para
diferencias de texto revisadas una por una en una verificacion puntual; un cambio de CLASE sigue siendo exit 1.
Sale 0 solo si no hay faltantes/sobrantes (salvo P000), ni duplicados, ni cambios de clase, ni diferencias de texto
fuera de ACEPTADOS_TEXTO. Solo stdlib.
"""
import argparse
import io
import json
import os
import re
import sys

# Misma regla de "roja" que el runner: PREFIJOS_ROJOS se define en harness_run.py (y b2_guard.py la importa igual).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness_run import PREFIJOS_ROJOS, _sin_tildes  # noqa: E402

# ============================== CONFIGURACION ==============================
# Ruido conocido: probes cuyo TEXTO cambia entre dos corridas de la misma base sin que cambie nada (fixtures
# posicionales que eligen otro actor). Medido el 17-nov-2026 entre harness-388-inyectada y harness-388-post: estas dos
# son las unicas diferencias de texto normalizado. Se matchea por PREFIJO del nombre del probe. Solo cubre el TEXTO: un
# cambio de clase en estos probes sigue siendo exit 1.
ACEPTADOS_TEXTO = (
    'VA_FX',   # VA_FX_fixture_validacion: elige la ficha real de GT por posicion (QA-TJ-A / QA-ASE-02)
    'P825',    # P825_invariante_visibilidad_cuentas: el conteo y el rol del actor dependen de la posicion
)
# Prefijo de las filas del centinela anti-null (una en la monolitica, una por parte en la partida).
P000 = 'P000_CENTINELA'
# ===========================================================================

UUID = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', re.I)
TS = re.compile(r'\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}(?::?\d{2})?)?')
HEX8 = re.compile(r'\b[0-9a-f]{8}\b', re.I)
NUM = re.compile(r'\d+')
# Fin del primer token: espacio, parentesis, dos puntos, coma o raya (la '-' NO corta: 'OK-SENAL' es un token).
FIN_TOKEN = re.compile(r'[\s(:,—–]')
N_VEREDICTOS = re.compile(r'\b(\d+)\s+veredictos\b')


def leer(path):
    """Filas [(probe, verdict)] de una salida del runner. Acepta {"rows": [...]} o una lista."""
    datos = json.load(io.open(path, encoding='utf-8'))
    filas = datos.get('rows') if isinstance(datos, dict) else datos
    if not isinstance(filas, list):
        raise ValueError('%s: no trae una lista de filas' % path)
    return [(str(f.get('probe') or ''), str(f.get('verdict') or '')) for f in filas]


def clase(verdict):
    v = _sin_tildes(verdict.strip().upper())
    if not v:
        return 'VACIO'
    for p in PREFIJOS_ROJOS:
        if v.startswith(p):
            return 'ROJA:' + p
    return FIN_TOKEN.split(v, 1)[0] or 'VACIO'


def normalizar(verdict):
    v = UUID.sub('<uuid>', verdict.strip())
    v = TS.sub('<ts>', v)
    v = HEX8.sub('<id8>', v)
    return NUM.sub('<n>', v)


def aceptado(probe, aceptados=ACEPTADOS_TEXTO):
    return probe.startswith(tuple(aceptados))


def n_veredictos(verdict):
    m = N_VEREDICTOS.search(verdict)
    return int(m.group(1)) if m else None


def comparar(a, b, aceptados=ACEPTADOS_TEXTO):
    """Devuelve (lineas_de_reporte, errores). Pura: no lee archivos, para poder probarla. `aceptados` = prefijos de
    probes cuyo TEXTO puede cambiar (nunca su clase)."""
    out, errores = [], 0

    def mapa(filas, lado):
        m, dup = {}, []
        for probe, v in filas:
            if probe in m:
                dup.append(probe)
            m[probe] = v
        return m, dup

    ma, dup_a = mapa(a, 'A')
    mb, dup_b = mapa(b, 'B')
    out.append('filas: A=%d B=%d' % (len(a), len(b)))
    for lado, dup in (('A', dup_a), ('B', dup_b)):
        if dup:
            errores += len(dup)
            out.append('ERROR  nombres duplicados en %s: %s' % (lado, ', '.join(sorted(set(dup)))))

    # --- P000: una fila en la monolitica, una por parte en la partida ---
    p0a = sorted(k for k in ma if k.startswith(P000))
    p0b = sorted(k for k in mb if k.startswith(P000))
    if not p0a or not p0b:
        errores += 1
        out.append('ERROR  falta el centinela P000 (A: %s / B: %s)' % (p0a or '-', p0b or '-'))
    else:
        ref = clase(ma[p0a[0]])
        for lado, nombres, m in (('A', p0a, ma), ('B', p0b, mb)):
            for k in nombres:
                if clase(m[k]) != ref:
                    errores += 1
                    out.append('ERROR  P000 cambia de clase: %s %s = %s (referencia %s)' % (lado, k, clase(m[k]), ref))
        suma_a = [n_veredictos(ma[k]) for k in p0a]
        suma_b = [n_veredictos(mb[k]) for k in p0b]
        if None in suma_a or None in suma_b:
            errores += 1
            out.append('ERROR  P000 sin conteo legible (A: %s / B: %s)' % (suma_a, suma_b))
        elif sum(suma_a) != sum(suma_b):
            errores += 1
            out.append('ERROR  P000: suma de veredictos A=%d (%d fila/s) B=%d (%d fila/s)'
                       % (sum(suma_a), len(p0a), sum(suma_b), len(p0b)))
        else:
            out.append('ok     P000: %d veredicto(s) por lado (A %d fila/s, B %d fila/s), clase %s'
                       % (sum(suma_a), len(p0a), len(p0b), ref))

    # --- faltantes y sobrantes (sin P000) ---
    solo_a = [k for k in ma if k not in mb and not k.startswith(P000)]
    solo_b = [k for k in mb if k not in ma and not k.startswith(P000)]
    for etiqueta, lista in (('solo en A (faltan en B)', solo_a), ('solo en B (sobran en B)', solo_b)):
        if lista:
            errores += len(lista)
            out.append('ERROR  %s: %d' % (etiqueta, len(lista)))
            for k in lista:
                out.append('         %s' % k)

    # --- clase y texto ---
    comunes = [k for k in ma if k in mb and not k.startswith(P000)]
    cambio_clase, texto_mal, texto_ok = [], [], []
    for k in comunes:
        ca, cb = clase(ma[k]), clase(mb[k])
        if ca != cb:
            cambio_clase.append((k, ca, cb))
        elif normalizar(ma[k]) != normalizar(mb[k]):
            (texto_ok if aceptado(k, aceptados) else texto_mal).append(k)
    out.append('comunes: %d' % len(comunes))
    out.append('%s  cambios de CLASE: %d' % ('ERROR' if cambio_clase else 'ok   ', len(cambio_clase)))
    for k, ca, cb in cambio_clase:
        out.append('         %s: %s -> %s' % (k, ca, cb))
        out.append('             A: %s' % ma[k][:180])
        out.append('             B: %s' % mb[k][:180])
    out.append('%s  texto distinto NO aceptado: %d' % ('ERROR' if texto_mal else 'ok   ', len(texto_mal)))
    for k in texto_mal:
        out.append('         %s' % k)
        out.append('             A: %s' % ma[k][:180])
        out.append('             B: %s' % mb[k][:180])
    out.append('aviso  texto distinto ACEPTADO (%s): %d' % ('/'.join(aceptados), len(texto_ok)))
    for k in texto_ok:
        out.append('         %s' % k)
        out.append('             A: %s' % ma[k][:180])
        out.append('             B: %s' % mb[k][:180])
    errores += len(cambio_clase) + len(texto_mal)
    return out, errores


def main():
    try:
        sys.stdout.reconfigure(errors='replace')
    except (AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser(description='Compara dos corridas del harness por veredicto.')
    ap.add_argument('a')
    ap.add_argument('b')
    ap.add_argument('--aceptar-texto', default='', metavar='PREFIJO[,PREFIJO...]',
                    help='prefijos que se suman a ACEPTADOS_TEXTO solo para esta ejecucion (solo texto, nunca clase)')
    args = ap.parse_args()
    extra = tuple(p.strip() for p in args.aceptar_texto.split(',') if p.strip())
    aceptados = ACEPTADOS_TEXTO + extra
    print('A = %s' % args.a)
    print('B = %s' % args.b)
    if extra:
        print('aceptados SOLO en esta ejecucion (--aceptar-texto): %s' % ', '.join(extra))
    lineas, errores = comparar(leer(args.a), leer(args.b), aceptados)
    for l in lineas:
        print(l)
    print()
    if errores:
        print('DISTINTAS: %d diferencia(s) que bloquean (exit 1)' % errores)
        return 1
    print('EQUIVALENTES (exit 0)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
