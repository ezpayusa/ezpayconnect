-- Foto del médico: bucket público + policies de storage + RPC de guardado.
-- Idempotente. Aplicar con: supabase db query --linked -f supabase/fixes/foto_medico_01.sql

-- 1) Bucket público
insert into storage.buckets (id, name, public)
values ('fotos-medicos', 'fotos-medicos', true)
on conflict (id) do update set public = true;

-- 2) Policies en storage.objects (idempotentes)
drop policy if exists "fotos_medicos_public_select" on storage.objects;
create policy "fotos_medicos_public_select"
  on storage.objects for select
  to public
  using (bucket_id = 'fotos-medicos');

drop policy if exists "fotos_medicos_owner_insert" on storage.objects;
create policy "fotos_medicos_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'fotos-medicos' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists "fotos_medicos_owner_update" on storage.objects;
create policy "fotos_medicos_owner_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'fotos-medicos' and split_part(name, '/', 1) = auth.uid()::text)
  with check (bucket_id = 'fotos-medicos' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists "fotos_medicos_owner_delete" on storage.objects;
create policy "fotos_medicos_owner_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'fotos-medicos' and split_part(name, '/', 1) = auth.uid()::text);

-- 3) RPC de guardado (DEFINER, escribe ambas columnas para auth.uid())
create or replace function public.guardar_foto_medico(p_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_prefix text := 'https://fqnsmvkxsuujahhmpzuk.supabase.co/storage/v1/object/public/fotos-medicos/' || coalesce(v_uid::text, '') || '/';
begin
  if v_uid is null then
    raise exception 'no_auth';
  end if;
  -- Guarda: solo aceptar una URL del propio prefijo del bucket público (evita URLs externas arbitrarias).
  if p_url is null or left(p_url, length(v_prefix)) <> v_prefix then
    return jsonb_build_object('ok', false, 'error', 'URL no valida');
  end if;
  update public.medicos  set foto_url   = p_url where id = v_uid;
  update public.perfiles set avatar_url = p_url where id = v_uid;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardar_foto_medico(text) from public;
grant execute on function public.guardar_foto_medico(text) to authenticated;
