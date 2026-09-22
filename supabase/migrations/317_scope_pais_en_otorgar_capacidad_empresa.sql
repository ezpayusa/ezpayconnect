-- ############################################################################################
-- 317 - gate de pais en otorgar_capacidad_empresa
-- ############################################################################################
-- otorgar_capacidad_empresa gateaba con tiene_rol(['super_admin','admin_pais']) SIN comparar el
-- pais de la empresa destino contra el del admin_pais. Consecuencia: un admin_pais del pais X podia
-- otorgar una capacidad suelta (laboratorio|farmacia) a una empresa del pais Y -- cruzando la
-- frontera de pais que su rol deberia respetar.
--
-- FIX (cambio minimo): se reemplaza el gate de rol por private.puede_admin_pais(<pais de la empresa
-- destino>, ARRAY['super_admin']). Ese helper:
--   * super_admin  -> pasa por tiene_rol(p_roles), global, sin mirar pais (comportamiento previo).
--   * admin_pais   -> exige p_pais_id IS NOT NULL AND get_auth_user_pais_id() = p_pais_id.
--   * COALESCE(...,false): fail-closed. Si la empresa NO existe, la subconsulta da NULL, p_pais_id
--     queda NULL, el brazo admin_pais es false y el resultado es false => NIEGA. No hay NULL
--     permisivo. (Confirmado contra la definicion viva de private.puede_admin_pais.)
--
-- Chequeo de existencia: NO se agrega uno explicito, a proposito.
--   * El gate va PRIMERO (limite de seguridad). Para admin_pais, empresa inexistente => pais NULL =>
--     el gate ya NIEGA con el MISMO 'No autorizado' que una empresa de otro pais: no se filtra por
--     mensaje si una empresa existe o no.
--   * Para super_admin (que ve todas las empresas igual), la existencia ya la garantiza la FK
--     empresa_capacidades_empresa_id_fkey -> empresas_proveedoras: un p_empresa_id inexistente hace
--     fallar el INSERT con 23503. Un chequeo explicito solo duplicaria eso.
--
-- Errcode: el gate viejo lanzaba 'No autorizado' sin errcode (P0001 por defecto). Se mantiene el
-- mensaje y se fija ERRCODE 42501 (insufficient_privilege), el estandar de negacion de gate de pais
-- del proyecto -- no consume ningun codigo PC/PA nuevo.
--
-- Firma, retorno (jsonb), volatilidad (VOLATILE), SECURITY DEFINER y search_path='' IDENTICOS.
-- ############################################################################################

CREATE OR REPLACE FUNCTION public.otorgar_capacidad_empresa(p_empresa_id uuid, p_codigo text, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- GATE DE PAIS (mig 317): admin_pais solo sobre empresas de SU pais; super_admin global.
  -- Fail-closed via COALESCE(...,false) dentro de puede_admin_pais: empresa inexistente o sin
  -- pais_id => la subconsulta da NULL => admin_pais NIEGA. No hay NULL permisivo.
  if not private.puede_admin_pais(
           (select pais_id from public.empresas_proveedoras where id = p_empresa_id),
           array['super_admin']) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_codigo not in ('laboratorio','farmacia') then
    return jsonb_build_object('ok', false, 'error', 'Codigo de capacidad no permitido por esta funcion');
  end if;

  insert into public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, hasta, activada_por)
  values (p_empresa_id, p_codigo, true, 'suelta', p_hasta, auth.uid())
  on conflict (empresa_id, capacidad_codigo)
  do update set activa = true, hasta = excluded.hasta, activada_por = auth.uid(), updated_at = now();

  return jsonb_build_object('ok', true);
end;
$function$;

COMMENT ON FUNCTION public.otorgar_capacidad_empresa(uuid, text, timestamp with time zone) IS
  'Otorga una capacidad suelta (laboratorio|farmacia) a una empresa. Gate de pais (mig 317): super_admin global, o admin_pais SOLO sobre empresas de su propio pais, via private.puede_admin_pais(<pais de la empresa destino>). Fail-closed: empresa inexistente o sin pais_id => admin_pais niega con 42501. Antes gateaba con tiene_rol([super_admin,admin_pais]) sin comparar el pais de la empresa, y un admin_pais podia otorgar a empresas de otro pais.';
