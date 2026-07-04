-- ============================================================================
-- Migración 230 (FIX DE FONDO): auto-provisión de la fila `pacientes` vía trigger
-- AFTER INSERT ON auth.users. Reemplaza el insert client-side (roto por RLS al no haber
-- sesión con email-confirm ON). SECURITY DEFINER → corre como owner, sin depender de
-- sesión ni de RLS. Gateado por raw_user_meta_data->>'tipo' = 'paciente' para NO crear
-- pacientes por signups de médico/proveedor/visitador/admin (que también insertan en auth.users).
-- Idempotente vía índice único parcial + ON CONFLICT DO NOTHING.
-- ============================================================================

BEGIN;

-- (1) Unique PARCIAL para idempotencia real del ON CONFLICT + garantía anti-duplicado.
--     WHERE auth_user_id IS NOT NULL preserva los pacientes legacy sin cuenta auth (NULL).
CREATE UNIQUE INDEX IF NOT EXISTS pacientes_auth_user_id_key
  ON public.pacientes (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- (2) Función SECURITY DEFINER: crea el paciente desde la metadata del signup.
CREATE OR REPLACE FUNCTION public.handle_new_paciente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_pais_default constant uuid := 'cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909';
  v_meta jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
  -- Gate: SOLO signups del portal de paciente.
  IF v_meta->>'tipo' IS DISTINCT FROM 'paciente' THEN
    RETURN NEW;
  END IF;

  BEGIN
    INSERT INTO public.pacientes (
      auth_user_id, email, nombre, apellido, telefono,
      fecha_nacimiento, genero, pais_id, activo
    ) VALUES (
      NEW.id,
      NEW.email,
      COALESCE(v_meta->>'nombre', ''),
      COALESCE(v_meta->>'apellido', ''),
      NULLIF(v_meta->>'telefono', ''),
      NULLIF(v_meta->>'fecha_nacimiento', '')::date,
      NULLIF(v_meta->>'genero', ''),
      COALESCE(NULLIF(v_meta->>'pais_id', '')::uuid, v_pais_default),
      true
    )
    ON CONFLICT (auth_user_id) WHERE auth_user_id IS NOT NULL DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Nunca tragar en silencio: log a Postgres logs. NO se aborta el alta de auth.users.
    RAISE WARNING '[handle_new_paciente] fallo creando paciente auth_user_id=% email=%: %',
      NEW.id, NEW.email, SQLERRM;
  END;

  RETURN NEW;
END;
$fn$;

-- (3) Trigger AFTER INSERT.
DROP TRIGGER IF EXISTS on_auth_user_created_paciente ON auth.users;
CREATE TRIGGER on_auth_user_created_paciente
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_paciente();

COMMIT;
