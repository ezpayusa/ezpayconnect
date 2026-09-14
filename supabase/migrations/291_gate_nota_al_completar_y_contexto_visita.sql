-- 291: ninguna cita se completa sin nota + el contexto de la visita es recuperable
--
-- Problema medido el 13-sep contra prod: de 1 cita en estado 'completada', 1 no tiene nota. El
-- boton "Finalizar" de ConsultaPage solo cambia citas.estado y nunca llama a guardarNotaSOAP.
--
-- POR QUE UN TRIGGER Y NO UN GUARD EN LA RPC: ninguna de las dos pantallas usa
-- actualizar_estado_cita. useCitas.updateCita y useMedicoCitas.updateCitaEstado hacen UPDATE
-- DIRECTO a public.citas por PostgREST, y la policy viva citas_update_medico (USING medico_id =
-- auth.uid()) lo permite sin condicion. Un guard dentro de la RPC habria dejado abierto el unico
-- camino que la aplicacion realmente recorre. El trigger cubre las tres vias (UPDATE directo, RPC
-- y cualquier script futuro) con una sola barrera. Precedente en esta misma tabla y columna:
-- trg_reset_notif_cancel ya es un BEFORE UPDATE OF estado.
--
-- ERRCODE: familia PE (expediente), nueva. PC NO es de citas/consultas — es de capacidades/pais
-- (PC001-PC024 tomados). Censo del 13-sep: PA comercial, PC capacidades, PP push promocional,
-- PR recetas, PT push transaccional, PV visitadores. Este cambio gasta un solo codigo: PE001.

-- ------------------------------------------------------------------------------------------
-- 1. Una nota por cita, como garantia de la base y no como supuesto del front
-- ------------------------------------------------------------------------------------------
-- useConsultas.fetchConsultaPorCita lee con .maybeSingle(): con dos notas de la misma cita la
-- pantalla revienta al cargar. El supuesto ya existia, no vivia en ningun lado. Medido antes de
-- crearlo: 0 citas con nota duplicada, asi que no rompe ninguna fila viva. Molde de la mig 282
-- (indice unico PARCIAL, porque cita_id es NULL en las notas que no cuelgan de una cita).
CREATE UNIQUE INDEX IF NOT EXISTS expediente_notas_una_por_cita
  ON public.expediente_notas (cita_id) WHERE cita_id IS NOT NULL;

-- ------------------------------------------------------------------------------------------
-- 2. El predicado, UNA sola vez
-- ------------------------------------------------------------------------------------------
-- Lo consultan el trigger y la RPC. Escrito dos veces, es cuestion de tiempo que se separen.
--
-- SECURITY DEFINER NO ES DECORATIVO ACA: sin eso el EXISTS se evalua bajo la RLS del llamante, y
-- un admin de clinica que cierra la cita (y que por las policies de expediente_notas puede no ver
-- esa nota) recibiria un falso "no hay nota" y quedaria bloqueado. La pregunta es si la nota
-- EXISTE, no si quien pregunta puede verla.
CREATE OR REPLACE FUNCTION private.cita_tiene_nota(p_cita_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.expediente_notas n WHERE n.cita_id = p_cita_id);
$$;

REVOKE EXECUTE ON FUNCTION private.cita_tiene_nota(bigint) FROM PUBLIC;

-- ------------------------------------------------------------------------------------------
-- 3. El gate: a 'completada' no se llega sin nota
-- ------------------------------------------------------------------------------------------
-- El mensaje NO lleva el prefijo 'PE001: ' que usan los PA0xx. Los PA viajan a erroresRpc.ts, que
-- los cambia por un texto para el usuario; este no pasa por ese mapa — cae directo en el
-- toast.error de la pantalla, asi que el mensaje ES el texto que lee el medico.
--
-- SECURITY DEFINER TAMBIEN ACA, Y NO POR LA RLS: una funcion de trigger corre con los privilegios
-- del que dispara el UPDATE. Sin DEFINER, `authenticated` necesita EXECUTE sobre
-- private.cita_tiene_nota, que esta REVOCADA — y el UPDATE muere con 42501 "permission denied for
-- function cita_tiene_nota" en vez de con PE001. Medido en el dry-run del 13-sep: P678 daba 42501.
-- La alternativa era GRANT-earle el helper a authenticated, pero eso convierte al helper en un
-- oraculo publico de "esta cita tiene nota". Con DEFINER, ninguna de las dos funciones es invocable
-- de afuera y el trigger igual las usa.
CREATE OR REPLACE FUNCTION private.exigir_nota_al_completar()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT private.cita_tiene_nota(NEW.id) THEN
    RAISE EXCEPTION 'Debe guardar la nota de la consulta antes de finalizar'
      USING ERRCODE = 'PE001';
  END IF;
  RETURN NEW;
END
$$;

-- Nadie la llama a mano: la dispara el trigger. Postgres chequea EXECUTE sobre la funcion de
-- trigger al CREATE TRIGGER, no en cada disparo, asi que revocarla no la apaga.
REVOKE EXECUTE ON FUNCTION private.exigir_nota_al_completar() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_exigir_nota_al_completar ON public.citas;

-- El WHEN hace dos cosas, las dos pedidas: deja intactos los otros cinco estados (agendada,
-- confirmada, cancelada, en_espera/en_curso, no_show) y no dispara cuando una cita YA completada
-- se vuelve a tocar — sin la mitad `OLD.estado IS DISTINCT FROM`, un UPDATE que ni siquiera
-- cambia el estado quedaria bloqueado por una nota que se borro despues.
CREATE TRIGGER trg_exigir_nota_al_completar
  BEFORE UPDATE OF estado ON public.citas
  FOR EACH ROW
  WHEN (NEW.estado = 'completada' AND OLD.estado IS DISTINCT FROM 'completada')
  EXECUTE FUNCTION private.exigir_nota_al_completar();

-- ------------------------------------------------------------------------------------------
-- 4. El contexto de la visita, en un solo jsonb
-- ------------------------------------------------------------------------------------------
-- Insumo del futuro "resumen de la ultima visita": la nota de la cita + lo que el asistente de IA
-- produjo durante esa consulta, junto y ordenado.
--
-- ALCANCE, Y POR QUE LAS DOS MITADES NO LO COMPARTEN: la policy viva de auditoria_ia es
-- `medico_id = auth.uid()` y NADA MAS — ni el admin de clinica ni el super_admin ven esas filas
-- hoy. Como esta funcion es SECURITY DEFINER, darle a las sugerencias el mismo scope que a la
-- nota habria AMPLIADO de hecho el acceso a texto generado por IA sobre datos medicos a dos roles
-- que hoy no lo tienen. La nota va con el scope de sus policies; las sugerencias, solo a su autor.
-- Nadie sale de aca viendo algo que sin esta funcion no podria ver.
CREATE OR REPLACE FUNCTION public.obtener_contexto_visita(p_cita_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_cita public.citas%ROWTYPE;
  v_nota_id integer;
  v_nota jsonb;
  v_ia jsonb;
BEGIN
  SELECT * INTO v_cita FROM public.citas WHERE id = p_cita_id;

  -- Cita inexistente y cita ajena responden IGUAL. Distinguirlas convierte a esta funcion en un
  -- oraculo de existencia de citas para cualquier authenticated. Mismo criterio que la mig 267.
  IF NOT FOUND
     OR NOT (
          v_cita.medico_id = auth.uid()
          -- las tres mitades de exp_select_medico, copiadas de la policy viva
          OR COALESCE(private.es_medico_de(v_cita.paciente_id::bigint), false)
          OR COALESCE(private.medico_atiende_paciente(v_cita.paciente_id::bigint), false)
          -- "Admin clinica ve expediente de su clinica"
          OR COALESCE(private.medico_es_de_mi_clinica(v_cita.medico_id::uuid), false)
          -- exp_superadmin_all
          OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
     ) THEN
    RAISE EXCEPTION 'no_autorizado' USING ERRCODE = '42501';
  END IF;

  SELECT n.id, to_jsonb(n.*) INTO v_nota_id, v_nota
    FROM public.expediente_notas n WHERE n.cita_id = p_cita_id;

  -- Sin nota no hay consulta_id, y sin consulta_id no hay con que atar las filas de IA: el array
  -- sale vacio, no NULL, para que el consumidor no tenga que distinguir dos formas de "nada".
  SELECT COALESCE(
           jsonb_agg(jsonb_build_object(
             'prompt', a.prompt, 'respuesta_ia', a.respuesta_ia, 'created_at', a.created_at
           ) ORDER BY a.created_at),
           '[]'::jsonb)
    INTO v_ia
    FROM public.auditoria_ia a
   WHERE v_nota_id IS NOT NULL
     AND a.consulta_id = v_nota_id
     AND a.medico_id = auth.uid();

  RETURN jsonb_build_object(
    'cita_id',        p_cita_id,
    'nota',           v_nota,
    'sugerencias_ia', COALESCE(v_ia, '[]'::jsonb)
  );
END
$$;

REVOKE EXECUTE ON FUNCTION public.obtener_contexto_visita(bigint) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.obtener_contexto_visita(bigint) TO authenticated;
