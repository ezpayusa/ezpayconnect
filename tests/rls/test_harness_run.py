#!/usr/bin/env python3
"""
test_harness_run.py — test del CLASIFICADOR de rojas de harness_run.py (_rojas).

Compatible con pytest (funciones test_*) y ejecutable sin pytest: `python tests/rls/test_harness_run.py`.
Prueba que la clasificacion es por PREFIJO: los prefijos de falla salen rojos (en mayuscula, minuscula y
con o sin tilde) y un texto que solo MENCIONA una palabra de falla adentro no.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness_run  # noqa: E402


def _es_roja(verdict):
    return bool(harness_run._rojas([{'probe': 'PX', 'verdict': verdict}]))


def test_rojo():
    assert _es_roja('ROJO (leak vivo)')


def test_fallo():
    assert _es_roja('FALLO (42501)')


def test_fallo_leak():
    assert _es_roja('FALLO/LEAK (x)')


def test_regresion_con_tilde():
    assert _es_roja('REGRESIÓN (P0001)')


def test_regresion_sin_tilde():
    assert _es_roja('REGRESION (P0001)')


def test_regresion_minuscula():
    assert _es_roja('regresión (x)')


def test_fuga():
    assert _es_roja('FUGA (a=false b=true)')


def test_leak():
    assert _es_roja('LEAK (x)')


def test_permitido():
    assert _es_roja('PERMITIDO (insertó signos vitales directo: mig 162 rota)')


def test_permitido_con_espacios():
    assert _es_roja('  PERMITIDO? (alcanzó el cuerpo)  ')


def test_ok_que_menciona_permitido_no_es_roja():
    assert not _es_roja('OK (BLOQUEADO: lo que antes era PERMITIDO ya no pasa)')


def test_bloqueado_no_es_roja():
    assert not _es_roja('BLOQUEADO (42501)')


def test_ok_que_menciona_fuga_y_regresion_no_es_roja():
    assert not _es_roja('OK (sin FUGA ni REGRESIÓN)')


def test_na_y_det_no_son_rojas():
    assert not _es_roja('N/A (sin fixture)')
    assert not _es_roja('DET borradas=1')


if __name__ == '__main__':
    casos = [(n, f) for n, f in sorted(globals().items()) if n.startswith('test_') and callable(f)]
    fallos = 0
    for nombre, f in casos:
        try:
            f()
            print('  ok   %s' % nombre)
        except AssertionError:
            fallos += 1
            print('  FALLO %s' % nombre)
    print()
    print('%d/%d casos pasan' % (len(casos) - fallos, len(casos)))
    sys.exit(1 if fallos else 0)
