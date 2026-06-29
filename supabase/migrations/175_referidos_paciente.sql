-- 175 Ola 1 backend "invitar amigo / referidos paciente"
-- Atribución PURA: el amigo NO hereda clínica. Código PERMANENTE por paciente. Solo registro de quién invitó a quién.
-- Escritura SOLO por RPC DEFINER. NO expone registrar_referido_atribucion a authenticated todavía (Ola 3 define el caller).

-- ============================================================
-- 1) TABLA referidos_paciente — código permanente, 1 fila por paciente referidor
-- ============================================================
CREATE TABLE IF NOT EXISTS public.referidos_paciente (
  id                    bigserial PRIMARY KEY,
  referidor_paciente_id bigint NOT NULL UNIQUE REFERENCES public.pacientes(id),
  codigo                text   NOT NULL UNIQUE,
  clinica_origen_id     uuid   REFERENCES public.clinicas(id),  -- snapshot de clinica_primaria_id al generar; nullable
  created_at            timestamptz NOT NULL DEFAULT now()
);

-- Grants: escritura solo por RPC DEFINER. authenticated conserva SELECT (gobernado por RLS); anon nada.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.referidos_paciente FROM authenticated;
REVOKE ALL ON public.referidos_paciente FROM anon;

ALTER TABLE public.referidos_paciente ENABLE ROW LEVEL SECURITY;
-- El referidor ve SOLO su propia fila. Sin INSERT/UPDATE/DELETE directo (solo RPC).
DROP POLICY IF EXISTS "Referidor ve su codigo" ON public.referidos_paciente;
CREATE POLICY "Referidor ve su codigo" ON public.referidos_paciente
  FOR SELECT TO authenticated
  USING (private.paciente_es_mio(referidor_paciente_id));

-- ============================================================
-- 2) TABLA referidos_atribucion — APPEND-ONLY, 1 fila por amigo registrado vía referido
-- ============================================================
CREATE TABLE IF NOT EXISTS public.referidos_atribucion (
  id                         bigserial PRIMARY KEY,
  codigo                     text   NOT NULL REFERENCES public.referidos_paciente(codigo),
  referido_nuevo_paciente_id bigint NOT NULL UNIQUE REFERENCES public.pacientes(id),  -- UNIQUE = un paciente solo se atribuye UNA vez
  registrado_at              timestamptz NOT NULL DEFAULT now()
);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.referidos_atribucion FROM authenticated;
REVOKE ALL ON public.referidos_atribucion FROM anon;

ALTER TABLE public.referidos_atribucion ENABLE ROW LEVEL SECURITY;
-- El referidor ve las atribuciones bajo SU código (quién aceptó su invitación). Sin escritura directa.
DROP POLICY IF EXISTS "Referidor ve atribuciones de su codigo" ON public.referidos_atribucion;
CREATE POLICY "Referidor ve atribuciones de su codigo" ON public.referidos_atribucion
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.referidos_paciente rp
    WHERE rp.codigo = referidos_atribucion.codigo
      AND private.paciente_es_mio(rp.referidor_paciente_id)
  ));

-- ============================================================
-- 3) RPC generar_codigo_referido() — idempotente, código único server-side
-- ============================================================
CREATE OR REPLACE FUNCTION public.generar_codigo_referido()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_uid      uuid;
  v_pid      bigint;
  v_clinica  uuid;
  v_codigo   text;
  v_existing RECORD;
  -- base32 sin caracteres ambiguos (sin 0/O, 1/I/L): 31 símbolos
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;

  SELECT id, clinica_primaria_id INTO v_pid, v_clinica
  FROM public.pacientes WHERE auth_user_id = v_uid;
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_auth'; END IF;  -- el caller no es un paciente

  -- IDEMPOTENTE: si ya tiene código, devolverlo tal cual.
  SELECT codigo, clinica_origen_id INTO v_existing
  FROM public.referidos_paciente WHERE referidor_paciente_id = v_pid;
  IF FOUND THEN
    RETURN jsonb_build_object('codigo', v_existing.codigo, 'clinica_origen_id', v_existing.clinica_origen_id);
  END IF;

  -- generar código único (loop anti-colisión contra el UNIQUE), 8 chars.
  LOOP
    v_codigo := '';
    FOR i IN 1..8 LOOP
      v_codigo := v_codigo || substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.referidos_paciente WHERE codigo = v_codigo);
  END LOOP;

  -- snapshot de la clínica primaria al generar; ON CONFLICT cubre carrera concurrente del mismo paciente.
  INSERT INTO public.referidos_paciente (referidor_paciente_id, codigo, clinica_origen_id)
  VALUES (v_pid, v_codigo, v_clinica)
  ON CONFLICT (referidor_paciente_id) DO NOTHING;

  SELECT codigo, clinica_origen_id INTO v_existing
  FROM public.referidos_paciente WHERE referidor_paciente_id = v_pid;
  RETURN jsonb_build_object('codigo', v_existing.codigo, 'clinica_origen_id', v_existing.clinica_origen_id);
END;
$function$;

REVOKE ALL     ON FUNCTION public.generar_codigo_referido() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.generar_codigo_referido() TO authenticated;

-- ============================================================
-- 4) RPC registrar_referido_atribucion(_codigo, _nuevo_paciente_id) — append-only, idempotente
--    ⚠️ NO expuesto a authenticated aún. RIESGO: _nuevo_paciente_id viene por parámetro, no derivado de
--    auth.uid() → un authenticated podría atribuir un paciente ajeno. Mitigación en Ola 3: derivar
--    _nuevo_paciente_id del auth.uid() del propio amigo recién creado (no del parámetro) antes de hacer GRANT.
-- ============================================================
CREATE OR REPLACE FUNCTION public.registrar_referido_atribucion(_codigo text, _nuevo_paciente_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_referidor bigint;
  v_inserted  bigint;
BEGIN
  -- resolver el código; si no existe, fallar sin filtrar nada.
  SELECT referidor_paciente_id INTO v_referidor
  FROM public.referidos_paciente WHERE codigo = _codigo;
  IF NOT FOUND THEN RAISE EXCEPTION 'codigo_invalido'; END IF;

  -- anti auto-referido
  IF v_referidor = _nuevo_paciente_id THEN RAISE EXCEPTION 'auto_referido'; END IF;

  -- idempotencia: el UNIQUE en referido_nuevo_paciente_id bloquea doble atribución.
  INSERT INTO public.referidos_atribucion (codigo, referido_nuevo_paciente_id)
  VALUES (_codigo, _nuevo_paciente_id)
  ON CONFLICT (referido_nuevo_paciente_id) DO NOTHING
  RETURNING id INTO v_inserted;

  IF v_inserted IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'estado', 'ya_atribuido');
  END IF;
  RETURN jsonb_build_object('ok', true, 'estado', 'registrado');
END;
$function$;

-- NO expuesto todavía: sin GRANT a authenticated (Ola 3 define el caller seguro).
REVOKE ALL ON FUNCTION public.registrar_referido_atribucion(text, bigint) FROM PUBLIC, anon, authenticated;
