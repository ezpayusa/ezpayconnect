#!/usr/bin/env python3
"""
b2_guard_test.py — TEST DEL DETECTOR DE b2_guard.py

POR QUE EXISTE
--------------
El detector de este gate se equivoco TRES veces en un solo dia, y las tres en la misma direccion
(inflar "sin handler", volviendo el gate PERMISIVO). El baseline llego a estar committeado en 319
cuando el real era 211: no habria disparado hasta que alguien agregara 108 bloques sin handler.
Un gate cuyo detector no esta probado no es un gate, es una decoracion.

Este test cubre las tres formas que fallaban Y EL ERROR SIMETRICO — `RAISE EXCEPTION`, que contiene
la palabra EXCEPTION y NO es un handler. Ese caso es el mas peligroso de todos porque falla en la
direccion INVISIBLE: subcontaria los sin-handler, el gate se pondria mas estricto de la cuenta y
nadie lo notaria hasta que un cambio legitimo lo hiciera fallar sin motivo aparente.

USO
---
    python tests/rls/b2_guard_test.py
Sale 0 si todos los casos pasan, 1 si alguno falla (con el detalle de cual).
"""
import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import b2_guard  # noqa: E402

# Cada caso: (nombre, sql, espera_handler)
CASOS = [
    ("POS-1 EXCEPTION WHEN en la MISMA linea", """
DO $$
BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','ROJO',false);
END $$;
""", True),

    ("POS-2 EXCEPTION y WHEN en LINEAS DISTINTAS", """
DO $$
BEGIN
  PERFORM 1;
EXCEPTION
  WHEN insufficient_privilege THEN PERFORM set_config('probe.x','BLOQ',false);
  WHEN others THEN PERFORM set_config('probe.x','otro',false);
END $$;
""", True),

    ("POS-3 handler en la LINEA DE CIERRE", """
DO $$
BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','ROJO',false); END $$;
""", True),

    ("POS-4 bloque DO de UNA SOLA LINEA, CON handler",
     "\nDO $$ BEGIN PERFORM 1; EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','R',false); END $$;\n",
     True),

    ("NEG-1 bloque DO de UNA SOLA LINEA, SIN handler",
     "\nDO $$ BEGIN PERFORM set_config('probe.x','OK',false); END $$;\n",
     False),

    ("NEG-2 multilinea SIN handler", """
DO $$
DECLARE v int;
BEGIN
  SELECT 1 INTO v;
  PERFORM set_config('probe.x','OK '||v,false);
END $$;
""", False),

    # EL CASO SIMETRICO: contiene la palabra EXCEPTION pero NO es un handler.
    ("NEG-3 RAISE EXCEPTION en el cuerpo, SIN handler", """
DO $$
BEGIN
  IF NOT true THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('probe.x','OK',false);
END $$;
""", False),

    ("NEG-4 RAISE EXCEPTION seguido de un CASE WHEN, SIN handler", """
DO $$
BEGIN
  RAISE EXCEPTION 'x';
  PERFORM set_config('probe.x', CASE WHEN true THEN 'a' ELSE 'b' END, false);
END $$;
""", False),

    ("POS-5 RAISE EXCEPTION *y* un handler de verdad", """
DO $$
BEGIN
  RAISE EXCEPTION 'PROBE_UNDO';
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','undo',false);
END $$;
""", True),

    # Handler ANIDADO dentro de un bloque cuyo nivel exterior no tiene handler.
    # LIMITACION CONOCIDA Y DOCUMENTADA: el detector cuenta el bloque como "con handler" porque el
    # handler existe en su cuerpo, aunque solo proteja al sub-bloque. Distinguirlo exigiria parsear
    # el anidamiento BEGIN/END de verdad. Se deja asi a proposito y el test FIJA esa conducta, para
    # que si alguien la cambia lo haga a sabiendas y no por accidente.
    ("LIMITACION handler ANIDADO cuenta como handler", """
DO $$
BEGIN
  BEGIN
    PERFORM 1;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM set_config('probe.x','OK',false);
END $$;
""", True),

    ("NEG-5 la palabra EXCEPTION dentro de un comentario NO cuenta", """
DO $$
BEGIN
  -- EXCEPTION WHEN OTHERS THEN esto es un comentario, no un handler
  PERFORM set_config('probe.x','OK',false);
END $$;
""", False),

    # EL ERROR SIMETRICO DE VERDAD. `RAISE EXCEPTION` resulto ser codigo muerto (ver tiene_handler);
    # el caso que SI puede ocurrir es que un texto de veredicto mencione las dos palabras. Si el
    # detector se lo come, subcuenta los sin-handler y el gate se vuelve estricto de mas EN SILENCIO.
    ("NEG-6 'EXCEPTION WHEN' dentro de una CADENA NO cuenta", """
DO $$
BEGIN
  PERFORM set_config('probe.x','el bloque no tiene EXCEPTION WHEN, esto es texto',false);
END $$;
""", False),

    ("POS-6 cadena que las menciona *y* un handler real", """
DO $$
BEGIN
  PERFORM set_config('probe.x','menciona EXCEPTION WHEN en el texto',false);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','ROJO',false);
END $$;
""", True),
]


# 4a metrica: catchall_verde. Cada caso: (nombre, sql, cuantos catch-all verdes espera). Fija las DOS
# direcciones: lo que tiene que contar (verde para cualquier SQLSTATE) y lo que NO (el handler mira el
# SQLSTATE, o publica rojo). Un detector que no cuenta nada pasaria los negativos; uno que cuenta todo,
# los positivos: por eso van los dos.
CASOS_CATCHALL = [
    ("CAV-POS-1 WHEN OTHERS -> 'OK ...' cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','OK (anon sin acceso: '||SQLSTATE||')',false);
END $$;
""", 1),

    ("CAV-POS-2 WHEN OTHERS -> 'N/A ...' cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN others THEN PERFORM set_config('probe.x','N/A (no se pudo armar el caso)',false);
END $$;
""", 1),

    ("CAV-POS-3 WHEN OTHERS -> 'BLOQUEADO ('||SQLSTATE (la clase P44) cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION
  WHEN others THEN PERFORM set_config('probe.x','BLOQUEADO ('||SQLSTATE||')',false);
END $$;
""", 1),

    ("CAV-POS-4 WHEN OTHERS -> 'OCULTO (' cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN others THEN PERFORM set_config('probe.x','OCULTO ('||SQLSTATE||')',false);
END $$;
""", 1),

    ("CAV-POS-5 sub-bloque anidado; el set_config de 'role' no cuenta, el del probe si", """
DO $$ BEGIN
  BEGIN PERFORM 1;
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('role','none',true); PERFORM set_config('probe.x','OK (42501)',false);
  END;
END $$;
""", 1),

    ("CAV-POS-6 'CASE' y 'END' DENTRO del texto del veredicto no cortan ni condicionan el handler", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','OK (CASE cubierto hasta el END)',false);
END $$;
""", 1),

    ("CAV-NEG-1 WHEN OTHERS con IF s='42501' -> BLOQUEADO / ELSE FALLO NO cuenta", """
DO $$ DECLARE s TEXT; BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
  IF s = '42501' THEN PERFORM set_config('probe.x','BLOQUEADO (RLS rechazo: 42501)',false);
  ELSE PERFORM set_config('probe.x','FALLO (otra constraint: '||s||')',false); END IF;
END $$;
""", 0),

    ("CAV-NEG-2 WHEN OTHERS -> 'FALLO ...' NO cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','FALLO ('||SQLSTATE||' '||SQLERRM||')',false);
END $$;
""", 0),

    ("CAV-NEG-3 WHEN OTHERS -> 'ROJO ...' NO cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','ROJO (corto con '||SQLSTATE||')',false);
END $$;
""", 0),

    ("CAV-NEG-4 CASE WHEN SQLSTATE dentro del set_config NO cuenta (patron Pinvit)", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN others THEN PERFORM set_config('probe.x', CASE WHEN SQLSTATE='42501' THEN 'OK (42501)' ELSE 'FALLO ('||SQLSTATE||')' END, false);
END $$;
""", 0),

    ("CAV-NEG-5 handler ESPECIFICO (insufficient_privilege) -> BLOQUEADO NO cuenta; el OTHERS publica FALLO", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('probe.x','BLOQUEADO (42501)',false);
  WHEN others THEN PERFORM set_config('probe.x','FALLO ('||SQLSTATE||')',false);
END $$;
""", 0),

    ("CAV-NEG-6 'BLOQUEADO?' es rojo para el runner: NO cuenta", """
DO $$ BEGIN
  PERFORM 1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','BLOQUEADO? ('||SQLSTATE||')',false);
END $$;
""", 0),

    ("CAV-NEG-7 'OK' publicado FUERA del handler (camino feliz) NO cuenta", """
DO $$ BEGIN
  PERFORM set_config('probe.x','OK (permitio)',false);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('probe.x','FALLO ('||SQLSTATE||')',false);
END $$;
""", 0),
]


def main():
    fallos = []
    for nombre, sql, espera in CASOS_CATCHALL:
        fd, path = tempfile.mkstemp(suffix='.sql')
        os.close(fd)
        io.open(path, 'w', encoding='utf-8').write(sql)
        try:
            _, blocks, _ = b2_guard.analizar(path)
            obtuvo = len(b2_guard.catchall_del_archivo(path, blocks))
            if len(blocks) != 1:
                fallos.append('%s: se detectaron %d bloques DO, se esperaba 1' % (nombre, len(blocks)))
            elif obtuvo != espera:
                fallos.append('%s: catchall_verde=%d, se esperaba %d' % (nombre, obtuvo, espera))
            else:
                print('  ok   %s' % nombre)
        finally:
            os.unlink(path)
    for nombre, sql, espera in CASOS:
        fd, path = tempfile.mkstemp(suffix='.sql')
        os.close(fd)
        io.open(path, 'w', encoding='utf-8').write(sql)
        try:
            _, blocks, _ = b2_guard.analizar(path)
            if len(blocks) != 1:
                fallos.append('%s: se detectaron %d bloques DO, se esperaba 1' % (nombre, len(blocks)))
                continue
            obtuvo = blocks[0][1]
            if obtuvo != espera:
                fallos.append('%s: handler=%s, se esperaba %s' % (nombre, obtuvo, espera))
            else:
                print('  ok   %s' % nombre)
        finally:
            os.unlink(path)

    print()
    if fallos:
        print('*** %d CASO(S) FALLARON ***' % len(fallos))
        for f in fallos:
            print('   - %s' % f)
        return 1
    print('TODOS LOS CASOS PASAN (%d: %d de handler + %d de catchall_verde)'
          % (len(CASOS) + len(CASOS_CATCHALL), len(CASOS), len(CASOS_CATCHALL)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
