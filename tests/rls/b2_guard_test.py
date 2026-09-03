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


def main():
    fallos = []
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
    print('TODOS LOS CASOS PASAN (%d)' % len(CASOS))
    return 0


if __name__ == '__main__':
    sys.exit(main())
