-- AdminFacile V15.4.3
-- À exécuter dans Supabase > SQL Editor.
-- Le bucket admin-documents doit rester privé.

drop policy if exists "adminfacile_select_own_documents" on storage.objects;
drop policy if exists "adminfacile_insert_own_documents" on storage.objects;
drop policy if exists "adminfacile_update_own_documents" on storage.objects;
drop policy if exists "adminfacile_delete_own_documents" on storage.objects;

create policy "adminfacile_select_own_documents"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'admin-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

create policy "adminfacile_insert_own_documents"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'admin-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

create policy "adminfacile_update_own_documents"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'admin-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = auth.uid()::text
    )
  )
)
with check (
  bucket_id = 'admin-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

create policy "adminfacile_delete_own_documents"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'admin-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);
