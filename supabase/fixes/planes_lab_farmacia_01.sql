-- Planes lab/farmacia: capacidades nuevas + RPC de otorgamiento + backfill de existentes.
-- Idempotente. Aplicar con: supabase db query --linked -f supabase/fixes/planes_lab_farmacia_01.sql

-- 1) Códigos de capacidad nuevos en el catálogo (destino FK de empresa_capacidades)
insert into public.capacidades_catalogo (codigo, nombre, descripcion, orden, activo, pais_id)
values
  ('laboratorio', 'Laboratorio clínico', 'Acceso al módulo de laboratorio clínico', 5, true, null),
  ('farmacia',    'Farmacia',            'Acceso al módulo de farmacia',            6, true, null)
on conflict (codigo) do update set activo = true, nombre = excluded.nombre, descripcion = excluded.descripcion;

-- 2) RPC para otorgar/renovar una capacidad de empresa (la usa el admin al verificar el pago)
create or replace function public.otorgar_capacidad_empresa(
  p_empresa_id uuid,
  p_codigo text,
  p_hasta timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(private.tiene_rol(array['super_admin','admin_pais']), false) then
    raise exception 'No autorizado';
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
$$;

revoke all on function public.otorgar_capacidad_empresa(uuid, text, timestamptz) from public;
grant execute on function public.otorgar_capacidad_empresa(uuid, text, timestamptz) to authenticated;

-- 3) BACKFILL — cubrir a los existentes con hasta=NULL (sin vencimiento, grandfathered) ANTES de cualquier gate
insert into public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, hasta)
select ep.id, 'laboratorio', true, 'suelta', null
from public.empresas_proveedoras ep
where ep.tipo = 'laboratorio_clinico' and ep.estado = 'activa'
on conflict (empresa_id, capacidad_codigo) do nothing;

insert into public.empresa_capacidades (empresa_id, capacidad_codigo, activa, origen, hasta)
select ep.id, 'farmacia', true, 'suelta', null
from public.empresas_proveedoras ep
where ep.tipo = 'farmacia' and ep.estado = 'activa'
on conflict (empresa_id, capacidad_codigo) do nothing;
